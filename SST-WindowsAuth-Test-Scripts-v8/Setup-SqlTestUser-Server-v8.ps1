#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '8.0'
$DefaultPassword = 'SST-Test-2026!'
$ExpectedServerName = 'DIR-VIRTUAL-SER'

Write-Host "SST SERVER SETUP SCRIPT - VERSION $ScriptVersion" -ForegroundColor Cyan
Write-Host 'Creates the server-side matching local Windows account and grants it SQL Server sysadmin for disposable testing.' -ForegroundColor DarkGray
Write-Host

function Read-RequiredValue {
    param([Parameter(Mandatory)][string]$Prompt)

    do {
        $value = (Read-Host $Prompt).Trim()
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value
}

function Read-DefaultValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Default
    )

    $value = (Read-Host "$Prompt [$Default]").Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value
}

$ActualServerName = $env:COMPUTERNAME
if ($ActualServerName -ne $ExpectedServerName) {
    Write-Warning "This script expects the SQL server computer name to be '$ExpectedServerName', but this computer reports '$ActualServerName'."
    Write-Warning 'The actual computer name will be used for the Windows login. Rename/restart the VM first if the expected name is required.'
}

$TesterUser = Read-RequiredValue 'Enter the tester username'
if ($TesterUser -notmatch '^[A-Za-z0-9._-]{1,20}$') {
    throw 'Username must be 1-20 characters and contain only letters, numbers, period, underscore, or hyphen.'
}

$AccountPassword = Read-DefaultValue 'Enter the tester account password' $DefaultPassword
if ([string]::IsNullOrWhiteSpace($AccountPassword)) {
    throw 'The tester account password cannot be blank.'
}

$SqlInstance = Read-DefaultValue 'Enter the SQL instance name' 'SST'
$SqlPortText = Read-DefaultValue 'Enter the SQL TCP port' '52525'

[int]$SqlPort = 0
if (-not [int]::TryParse($SqlPortText, [ref]$SqlPort) -or $SqlPort -lt 1 -or $SqlPort -gt 65535) {
    throw 'The SQL TCP port must be a number from 1 through 65535.'
}

$SecurePassword = ConvertTo-SecureString $AccountPassword -AsPlainText -Force

Write-Host
Write-Host "Configuring server-local account '$ActualServerName\$TesterUser'..." -ForegroundColor Cyan

$ExistingUser = Get-LocalUser -Name $TesterUser -ErrorAction SilentlyContinue
if ($null -eq $ExistingUser) {
    New-LocalUser `
        -Name $TesterUser `
        -Password $SecurePassword `
        -AccountNeverExpires `
        -PasswordNeverExpires `
        -Description 'SST workgroup SQL test account' | Out-Null

    Write-Host 'Local user created.' -ForegroundColor Green
}
else {
    Set-LocalUser `
        -Name $TesterUser `
        -Password $SecurePassword `
        -AccountNeverExpires `
        -PasswordNeverExpires $true `
        -Description 'SST workgroup SQL test account'

    if (-not $ExistingUser.Enabled) {
        Enable-LocalUser -Name $TesterUser
    }

    Write-Host 'Existing local user updated and password reset.' -ForegroundColor Green
}

$LocalUser = Get-LocalUser -Name $TesterUser
$WindowsLogin = $LocalUser.SID.Translate([System.Security.Principal.NTAccount]).Value

# Ensure normal local logon/network access through the built-in Users group.
$UsersGroup = Get-LocalGroup -SID 'S-1-5-32-545'
$AlreadyInUsers = Get-LocalGroupMember -Group $UsersGroup.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.SID -eq $LocalUser.SID }

if (-not $AlreadyInUsers) {
    Add-LocalGroupMember -Group $UsersGroup.Name -Member $LocalUser
}

Write-Host "Resolved Windows login: $WindowsLogin" -ForegroundColor DarkGray
Write-Host
Write-Host "Connecting locally to SQL instance '$SqlInstance' through TCP port $SqlPort..." -ForegroundColor Cyan

$ConnectionString = "Server=tcp:localhost,$SqlPort;Initial Catalog=master;Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;Connect Timeout=15;Application Name=SST Test User Setup v$ScriptVersion"
$Connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)

try {
    $Connection.Open()

    $Command = $Connection.CreateCommand()
    $Command.CommandTimeout = 30
    $Command.CommandText = @'
DECLARE @LoginName sysname = @Login;
DECLARE @Sql nvarchar(max);

IF SUSER_ID(@LoginName) IS NULL
BEGIN
    SET @Sql = N'CREATE LOGIN ' + QUOTENAME(@LoginName) + N' FROM WINDOWS;';
    EXEC sys.sp_executesql @Sql;
END;

IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin', @LoginName), 0) <> 1
BEGIN
    SET @Sql = N'ALTER SERVER ROLE [sysadmin] ADD MEMBER ' + QUOTENAME(@LoginName) + N';';
    EXEC sys.sp_executesql @Sql;
END;

SELECT
    @LoginName AS LoginName,
    ISNULL(IS_SRVROLEMEMBER(N'sysadmin', @LoginName), 0) AS IsSysadmin;
'@

    [void]$Command.Parameters.Add('@Login', [System.Data.SqlDbType]::NVarChar, 128)
    $Command.Parameters['@Login'].Value = $WindowsLogin

    $Reader = $Command.ExecuteReader()
    try {
        if (-not $Reader.Read()) {
            throw 'SQL Server returned no verification row.'
        }

        $ConfiguredLogin = [string]$Reader['LoginName']
        $IsSysadmin = [int]$Reader['IsSysadmin']
    }
    finally {
        $Reader.Close()
    }

    if ($IsSysadmin -ne 1) {
        throw "SQL login '$ConfiguredLogin' exists but sysadmin membership could not be verified."
    }

    Write-Host "SQL login configured: $ConfiguredLogin" -ForegroundColor Green
    Write-Host 'SQL sysadmin granted: Yes' -ForegroundColor Green
}
catch {
    throw "Could not configure the SQL login. Run this script using a Windows account that is already a SQL sysadmin. SQL endpoint attempted: tcp:localhost,$SqlPort. Details: $($_.Exception.Message)"
}
finally {
    if ($Connection.State -ne [System.Data.ConnectionState]::Closed) {
        $Connection.Close()
    }
    $Connection.Dispose()
}

Write-Host
Write-Host 'SERVER SETUP COMPLETE' -ForegroundColor Green
Write-Host "Server computer : $ActualServerName"
Write-Host "Tester username : $TesterUser"
Write-Host "Windows login   : $WindowsLogin"
Write-Host "Tester password : $AccountPassword"
Write-Host "SQL instance    : $SqlInstance"
Write-Host "SQL endpoint    : tcp:$ExpectedServerName,$SqlPort"
Write-Host
Write-Warning 'This script grants sysadmin and uses an easy password by default. Use only in disposable test environments.'
