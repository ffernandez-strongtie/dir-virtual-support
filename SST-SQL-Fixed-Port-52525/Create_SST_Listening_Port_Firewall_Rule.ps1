# Run as Administrator
$RuleName = 'SST_Listening_Port'
$Port = 52525

if (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue) {
    Remove-NetFirewallRule -DisplayName $RuleName
}

New-NetFirewallRule \
    -DisplayName $RuleName \
    -Direction Inbound \
    -Action Allow \
    -Protocol TCP \
    -LocalPort $Port \
    -Profile Any

Write-Host "Firewall rule created: $RuleName on TCP $Port"
