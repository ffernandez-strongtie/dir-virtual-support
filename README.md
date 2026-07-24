# SST SQL Server VM Support

This repository contains PowerShell scripts and setup guides for running the **SST** SQL Server instance in a Windows VM test environment without a domain controller.

It addresses two common problems:

1. **Unreliable SQL connectivity** caused by disabled TCP/IP, dynamic ports, or missing firewall rules.
2. **Windows Authentication failures** between workgroup VMs, including `Cannot generate SSPI context` errors.

## Quick Setup

### 1. Configure SQL Server networking

On the SQL Server VM, run:

- `Enable_SQL_TCP_52525.ps1`
- `Create_SST_Listening_Port_Firewall_Rule.ps1`

These scripts configure SST to listen on fixed TCP port **52525** and create the required inbound firewall rule.

See [SST-SQL-Fixed-Port-52525-Setup.md](./SST-SQL-Fixed-Port-52525-Setup.md).

### 2. Configure Windows Authentication without a domain

Run the Version 8 account scripts using the same tester username and password on both machines:

- Server: `Setup-SqlTestUser-Server-v8.ps1`
- Client: `Setup-SqlTestUser-Client-v8.ps1`

After running the client script, sign out and sign in using the local tester account:

```text
.\<tester-username>
```

See [SST-Windows-Authentication-VM-Setup-v8.md](./SST-Windows-Authentication-VM-Setup-v8.md).

## SQL Endpoint

Use Windows Authentication with:

```text
tcp:DIR-VIRTUAL-SER,52525
```

## Important

These scripts are intended for isolated or disposable test VMs. The Version 8 account scripts grant broad local and SQL Server permissions to simplify provisioning. Windows services must also be configured to run under the local tester account when they connect to SQL Server using Windows Authentication.
