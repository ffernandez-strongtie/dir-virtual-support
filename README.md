# Virtualized CS Director Instructions

This repository contains the instructions for installing the POC of CS Director which supports multiple users on the same machine connectinng to a dedicated server running Microsoft SQL.

## Instructions

Follow the instruction in this order:

- [CSDirector Server Guide](./CSDirector%20Server%20Guide/README.md) (must be installed before the client)
- [CSDirector Client Guide](./CSDirector%20Client%20Guide/README.md)


## Workgroup or VM Support

This repository contains PowerShell scripts and setup guides for running the **SST** SQL Server instance in a Windows VM test environment without a domain controller.

It addresses two common problems:

1. **Unreliable SQL connectivity** caused by disabled TCP/IP, dynamic ports, or missing firewall rules.
2. **Windows Authentication failures** between workgroup VMs, including `Cannot generate SSPI context` errors.

### Quick Setup

#### 1. Configure SQL Server networking

On the SQL Server VM, run:

- `Enable_SQL_TCP_52525.ps1`
- `Create_SST_Listening_Port_Firewall_Rule.ps1`

These scripts configure SST to listen on fixed TCP port **52525** and create the required inbound firewall rule.

See [SQL Fixed Port](./utilities/sql-fixed-port/README.md).

#### 2. Configure Windows Authentication without a domain

Run the Version 8 account scripts using the same tester username and password on both machines:

- Server: `Setup-SqlTestUser-Server-v8.ps1`
- Client: `Setup-SqlTestUser-Client-v8.ps1`

After running the client script, sign out and sign in using the local tester account:

```text
.\<tester-username>
```

See [Auth Without Domain Conttroller](./utilities/auth-without-domain-controller/README.md).

### SQL Endpoint

Use Windows Authentication with:

```text
tcp:DIR-VIRTUAL-SER,52525
```

### Important

These scripts are intended for isolated or disposable test VMs. The Version 8 account scripts grant broad local and SQL Server permissions to simplify provisioning. Windows services must also be configured to run under the local tester account when they connect to SQL Server using Windows Authentication.
