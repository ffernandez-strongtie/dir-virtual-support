# Run as Administrator

$ServiceName = 'MSSQL$SST'
$RuleName = 'SST_Listening_Port'

# Verify that PowerShell is running as Administrator
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
$IsAdministrator = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdministrator) {
    Write-Error 'Run PowerShell as Administrator, then run this script again.'
    exit 1
}

# Find the SST SQL Server service
$SqlService = Get-CimInstance Win32_Service |
    Where-Object { $_.Name -eq $ServiceName }

if (-not $SqlService) {
    Write-Error "SQL Server service '$ServiceName' was not found."
    exit 1
}

if ($SqlService.State -ne 'Running') {
    Write-Error "SQL Server service '$ServiceName' is not running."
    exit 1
}

Write-Host ""
Write-Host "SQL Server service: $ServiceName"
Write-Host "Process ID: $($SqlService.ProcessId)"

# Find TCP listening ports owned by the SQL Server process
$ListeningPorts = @(
    Get-NetTCPConnection `
        -State Listen `
        -OwningProcess $SqlService.ProcessId `
        -ErrorAction Stop |
    Select-Object -ExpandProperty LocalPort -Unique |
    Sort-Object
)

if ($ListeningPorts.Count -eq 0) {
    Write-Error "No TCP listening ports were found for '$ServiceName'."
    Write-Host "Confirm that TCP/IP is enabled and restart the SST SQL Server service."
    exit 1
}

$PortList = $ListeningPorts -join ','

Write-Host ""
Write-Host "Detected listening TCP port(s): $PortList" -ForegroundColor Cyan
Write-Host ""

# Remove the previous firewall rule if it exists
$ExistingRules = Get-NetFirewallRule `
    -DisplayName $RuleName `
    -ErrorAction SilentlyContinue

if ($ExistingRules) {
    $ExistingRules | Remove-NetFirewallRule
    Write-Host "Removed existing firewall rule: $RuleName"
}

# Create the inbound firewall rule
New-NetFirewallRule `
    -DisplayName $RuleName `
    -Description "Allows inbound TCP traffic to the detected SST SQL Server listening port." `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $ListeningPorts `
    -Action Allow `
    -Enabled True `
    -Profile Any |
    Out-Null

Write-Host ""
Write-Host "Firewall rule created successfully." -ForegroundColor Green
Write-Host "Rule name: $RuleName"
Write-Host "TCP port(s): $PortList"