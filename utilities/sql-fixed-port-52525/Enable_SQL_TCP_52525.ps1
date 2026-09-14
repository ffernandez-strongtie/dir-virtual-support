#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$instance = 'SST'
$port = 52525
$moduleName = 'SqlServer'

try {
    # Allow module scripts to run in this PowerShell session only
    Set-ExecutionPolicy `
        -Scope Process `
        -ExecutionPolicy Bypass `
        -Force

    # Install the SqlServer PowerShell module if it is missing
    if (-not (Get-Module -Name $moduleName -ListAvailable)) {
        Write-Host "SqlServer PowerShell module is missing. Installing..."

        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
            Register-PSRepository -Default
        }

        Set-PSRepository `
            -Name PSGallery `
            -InstallationPolicy Trusted

        Install-Module `
            -Name $moduleName `
            -Scope AllUsers `
            -Force `
            -AllowClobber

        Write-Host "SqlServer PowerShell module installed."
    }

    Import-Module $moduleName -Force

    Write-Host "Enabling TCP/IP for SQL instance $instance"

    $mc = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
    $sqlInstance = $mc.ServerInstances[$instance]

    if (-not $sqlInstance) {
        throw "SQL Server instance '$instance' was not found."
    }

    $tcp = $sqlInstance.ServerProtocols['Tcp']

    if (-not $tcp) {
        throw "TCP/IP configuration was not found for instance '$instance'."
    }

    $tcp.IsEnabled = $true

    foreach ($ip in $tcp.IPAddresses) {
        $dynamicPorts = $ip.IPAddressProperties['TcpDynamicPorts']
        $staticPort = $ip.IPAddressProperties['TcpPort']

        if ($dynamicPorts) {
            $dynamicPorts.Value = ''
        }

        if ($staticPort) {
            $staticPort.Value = $port.ToString()
        }
    }

    $tcp.Alter()

    Restart-Service `
        -Name "MSSQL`$$instance" `
        -Force `
        -ErrorAction Stop

    Write-Host `
        "Done. SQL TCP/IP enabled and configured for port $port" `
        -ForegroundColor Green
}
catch {
    Write-Error "Configuration failed: $($_.Exception.Message)"
    exit 1
}