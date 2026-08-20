#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '8.0'
$DefaultPassword = 'SST-Test-2026!'
$ExpectedClientName = 'DIR-VIRTUAL-CLI'
$DefaultServerName = 'DIR-VIRTUAL-SER'

Write-Host "SST CLIENT ACCOUNT SETUP - VERSION $ScriptVersion" -ForegroundColor Cyan
Write-Host 'Run this once from the work-account desktop as Administrator. It creates the matching local tester account.' -ForegroundColor DarkGray
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

$ActualClientName = $env:COMPUTERNAME
if ($ActualClientName -ne $ExpectedClientName) {
    Write-Warning "This script expects the client computer name to be '$ExpectedClientName', but this computer reports '$ActualClientName'."
    Write-Warning 'The actual computer name will be used for the local account display. Rename/restart the VM first if the expected name is required.'
}

$TesterUser = Read-RequiredValue 'Enter the tester username'
if ($TesterUser -notmatch '^[A-Za-z0-9._-]{1,20}$') {
    throw 'Username must be 1-20 characters and contain only letters, numbers, period, underscore, or hyphen.'
}

$AccountPassword = Read-DefaultValue 'Enter the tester account password' $DefaultPassword
if ([string]::IsNullOrWhiteSpace($AccountPassword)) {
    throw 'The tester account password cannot be blank.'
}

$ServerName = Read-DefaultValue 'Enter the SQL server computer name' $DefaultServerName
$SqlInstance = Read-DefaultValue 'Enter the SQL instance name' 'SST'
$SqlPortText = Read-DefaultValue 'Enter the SQL TCP port' '52525'

[int]$SqlPort = 0
if (-not [int]::TryParse($SqlPortText, [ref]$SqlPort) -or $SqlPort -lt 1 -or $SqlPort -gt 65535) {
    throw 'The SQL TCP port must be a number from 1 through 65535.'
}

$SecurePassword = ConvertTo-SecureString $AccountPassword -AsPlainText -Force

Write-Host
Write-Host "Creating matching local account '$ActualClientName\$TesterUser'..." -ForegroundColor Cyan

$ExistingUser = Get-LocalUser -Name $TesterUser -ErrorAction SilentlyContinue
if ($null -eq $ExistingUser) {
    New-LocalUser `
        -Name $TesterUser `
        -Password $SecurePassword `
        -AccountNeverExpires `
        -PasswordNeverExpires `
        -Description 'SST workgroup tester account' | Out-Null

    Write-Host 'Local tester account created.' -ForegroundColor Green
}
else {
    Set-LocalUser `
        -Name $TesterUser `
        -Password $SecurePassword `
        -AccountNeverExpires `
        -PasswordNeverExpires $true `
        -Description 'SST workgroup tester account'

    if (-not $ExistingUser.Enabled) {
        Enable-LocalUser -Name $TesterUser
    }

    Write-Host 'Existing local tester account updated and password reset.' -ForegroundColor Green
}

$LocalUser = Get-LocalUser -Name $TesterUser

# Make the disposable tester account a local administrator so testers can install software and manage services.
# The SID is language-independent, so this works on non-English Windows installations too.
$AdministratorsGroup = Get-LocalGroup -SID 'S-1-5-32-544'
$AlreadyAdministrator = Get-LocalGroupMember -Group $AdministratorsGroup.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.SID -eq $LocalUser.SID }

if (-not $AlreadyAdministrator) {
    Add-LocalGroupMember -Group $AdministratorsGroup.Name -Member $LocalUser
    Write-Host 'Added tester account to the local Administrators group.' -ForegroundColor Green
}
else {
    Write-Host 'Tester account is already a local administrator.' -ForegroundColor Green
}

# Remove Credential Manager entries created by the obsolete credential-caching approach for the current work account.
foreach ($Target in @($ServerName, "${ServerName}:$SqlPort")) {
    & cmdkey.exe "/delete:$Target" 2>$null | Out-Null
}

Write-Host
Write-Host "Testing TCP connectivity to $ServerName on port $SqlPort..." -ForegroundColor Cyan
$TcpTest = Test-NetConnection -ComputerName $ServerName -Port $SqlPort -WarningAction SilentlyContinue
if ($TcpTest.TcpTestSucceeded) {
    Write-Host 'TCP test succeeded.' -ForegroundColor Green
}
else {
    Write-Warning "The local account was created, but TCP $SqlPort could not be reached on $ServerName."
}

Write-Host
Write-Host 'CLIENT ACCOUNT SETUP COMPLETE' -ForegroundColor Green
Write-Host "Client computer  : $ActualClientName"
Write-Host "Local login      : .\$TesterUser"
Write-Host "Full local login : $ActualClientName\$TesterUser"
Write-Host "Tester password  : $AccountPassword"
Write-Host "SQL instance     : $SqlInstance"
Write-Host "SQL endpoint     : tcp:$ServerName,$SqlPort"
Write-Host
Write-Host 'NEXT STEP:' -ForegroundColor Yellow
Write-Host '1. Sign out of Windows.'
Write-Host "2. At the sign-in screen choose Other user, and sign in as .\$TesterUser"
Write-Host "3. Use password: $AccountPassword"
Write-Host '4. Launch/install the application normally under that local account.'
Write-Host
Write-Warning 'Desktop applications will use this account automatically. A Windows service uses this identity only when its Log On account is configured to this tester account.'
Write-Warning 'This is intentionally permissive and uses an easy password by default. Use only in disposable test VMs.'
