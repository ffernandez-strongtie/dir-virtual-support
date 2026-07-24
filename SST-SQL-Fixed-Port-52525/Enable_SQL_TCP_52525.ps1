# Run as Administrator
$instance = "SST"
$port = 52525

Write-Host "Enabling TCP/IP for SQL instance $instance"

$mc = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$tcp = $mc.ServerInstances[$instance].ServerProtocols['Tcp']

$tcp.IsEnabled = $true

foreach ($ip in $tcp.IPAddresses) {
    try {
        $ip.IPAddressProperties['TcpDynamicPorts'].Value = ''
        $ip.IPAddressProperties['TcpPort'].Value = $port.ToString()
    } catch {}
}

$tcp.Alter()

Restart-Service -Name "MSSQL`$$instance" -Force

Write-Host "Done. SQL TCP/IP enabled and configured for port $port"
