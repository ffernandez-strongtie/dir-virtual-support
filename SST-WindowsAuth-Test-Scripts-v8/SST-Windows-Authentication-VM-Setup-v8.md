# Windows Authentication for SST in a Non-Domain VM Test Environment

## Overview

If you are experiencing SQL Server connection failures in a virtual-machine environment that is **not connected to a domain controller**, Windows Authentication may fail even though:

- the SQL Server port is reachable;
- the SQL Server instance is listening;
- the firewall rule is correct; and
- the same Microsoft work account is used to sign in to both VMs.

Typical errors include:

```text
The target principal name is incorrect.
Cannot generate SSPI context.
```

The reason is that legacy SQL Server Windows Authentication uses the Windows identity of the process or service making the connection. In a workgroup, there is no shared domain authority that both machines can use to validate that identity. Signing in to both VMs with the same Microsoft work account does not make the two computers members of the same traditional Windows security domain.

For disposable test environments, the simplest domain-free solution is to create **matching local Windows accounts** on the SQL Server VM and the client VM:

- the username must be the same on both machines;
- the password must be the same on both machines;
- the tester signs in to the client VM using that local account; and
- SQL Server is configured to recognize the corresponding local account on the server.

The Version 8 scripts automate this setup.

## Environment Used by the Scripts

The scripts expect these default values:

```text
SQL Server computer: DIR-VIRTUAL-SER
Client computer:     DIR-VIRTUAL-CLI
SQL instance:        SST
SQL TCP port:        52525
Default password:    SST-Test-2026!
```

The username is entered when each script runs. Use the **same username and password on both machines**.

The SQL connection endpoint is:

```text
tcp:DIR-VIRTUAL-SER,52525
```

Because a fixed TCP port is supplied, the instance name does not need to be included in the server address.

---

# Part 1: Configure the SQL Server VM

Run the server script on `DIR-VIRTUAL-SER` while signed in with a Windows account that is already a SQL Server `sysadmin`.

The server script:

1. Creates or updates a local Windows account using the username and password you enter.
2. Ensures the account is enabled and does not expire.
3. Creates the corresponding Windows login in SQL Server.
4. Grants that login the SQL Server `sysadmin` role for simplified disposable testing.

> **Important:** The script intentionally grants broad permissions. It is intended only for isolated or disposable test VMs.

## Run the Version 8 server script

Open **PowerShell as Administrator**, go to the folder containing the script, and run:

```powershell
cd "$HOME\Downloads"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Unblock-File ".\Setup-SqlTestUser-Server-v8.ps1"
.\Setup-SqlTestUser-Server-v8.ps1
```

The execution-policy change applies only to the current PowerShell window. Closing the window restores the previous policy.

## Server prompts

The script asks for:

```text
Enter the tester username:
Enter the tester account password [SST-Test-2026!]:
Enter the SQL instance name [SST]:
Enter the SQL TCP port [52525]:
```

Example:

```text
Tester username: FrankF
Password:        press Enter to use SST-Test-2026!
SQL instance:    press Enter to use SST
SQL TCP port:    press Enter to use 52525
```

When complete, the script should report that the Windows login was configured and granted SQL Server `sysadmin` access.

If the server script has already completed successfully for that username and password, it does not need to be rerun before provisioning another matching client account.

---

# Part 2: Configure the Client VM

Run the client script on `DIR-VIRTUAL-CLI` while signed in with the normal Microsoft work account. Run PowerShell as Administrator.

The client script:

1. Creates or updates a matching local Windows account.
2. Sets the same password used on the server.
3. Adds the tester account to the local Administrators group so the tester can install and configure software in the disposable VM.
4. Tests TCP connectivity to `DIR-VIRTUAL-SER` on port `52525`.

## Run the Version 8 client script

```powershell
cd "$HOME\Downloads"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Unblock-File ".\Setup-SqlTestUser-Client-v8.ps1"
.\Setup-SqlTestUser-Client-v8.ps1
```

## Client prompts

The script asks for:

```text
Enter the tester username:
Enter the tester account password [SST-Test-2026!]:
Enter the SQL server computer name [DIR-VIRTUAL-SER]:
Enter the SQL instance name [SST]:
Enter the SQL TCP port [52525]:
```

Use the **same username and password entered on the server**.

Example:

```text
Tester username: FrankF
Password:        press Enter to use SST-Test-2026!
Server name:     press Enter to use DIR-VIRTUAL-SER
SQL instance:    press Enter to use SST
SQL TCP port:    press Enter to use 52525
```

---

# Part 3: Sign In Using the Local Tester Account

After the client script finishes:

1. Sign out of the Microsoft work account.
2. Select **Other user** at the Windows sign-in screen.
3. Make sure the password sign-in option is selected.
4. Sign in using the local account.

For a username such as `FrankF`, enter:

```text
.\FrankF
```

You may also use the full local-machine form:

```text
DIR-VIRTUAL-CLI\FrankF
```

Enter the password used in both scripts. With the default values:

```text
SST-Test-2026!
```

Windows creates the tester's profile the first time the account signs in.

## Verify the signed-in identity

Open PowerShell and run:

```powershell
whoami
```

Expected result for the example account:

```text
dir-virtual-cli\frankf
```

The software must be launched under this local tester account so that Windows Authentication uses this identity.

---

# Part 4: Connect to SQL Server

Use Windows Authentication with this SQL endpoint:

```text
tcp:DIR-VIRTUAL-SER,52525
```

A typical connection string is:

```text
Server=tcp:DIR-VIRTUAL-SER,52525;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;
```

Do not put a username or password in the application's SQL connection string. Windows Authentication uses the Windows identity under which the application process is running.

You can verify basic network access from the client with:

```powershell
Test-NetConnection DIR-VIRTUAL-SER -Port 52525
```

The expected result is:

```text
TcpTestSucceeded : True
```

---

# Windows Services

Signing in as the local tester account automatically affects desktop applications launched by that user. It does **not automatically change the identity of an installed Windows service**.

A Windows service uses the account configured on its **Log On** tab. If the software installs a service that must connect to SQL Server using Windows Authentication, configure that service to run as the local tester account, for example:

```text
.\FrankF
```

Use the same password configured by the scripts, and then restart the service.

If the service remains configured as `LocalSystem`, `LocalService`, or `NetworkService`, it will not use the signed-in tester's identity merely because the tester is logged in.

---

# Why This Works

In a domain, both machines trust the same directory and can validate the same domain identity. In this test environment there is no domain controller, so that shared trust does not exist.

The scripts instead create matching local credentials:

```text
DIR-VIRTUAL-SER\FrankF
DIR-VIRTUAL-CLI\FrankF
```

These are technically separate local accounts, but they use the same username and password. When the application runs under the client-side local account, Windows can use workgroup authentication to present those credentials to the server. The server validates them against its own matching local account, and SQL Server maps the validated server-local identity to the Windows login created by the server script.

This preserves the application's requirement to use Windows Authentication without requiring a domain controller or changing the application to SQL Authentication.

---

# Important Limitations

- Use this setup only for disposable or isolated test VMs.
- Version 8 grants the tester local administrator rights on the client.
- Version 8 grants the matching Windows login SQL Server `sysadmin` rights on the server.
- The default password is intentionally easy for provisioning and is not suitable for production.
- The username and password must match on the server and client.
- If the password is changed on one machine, rerun the corresponding script on both machines with the same new password.
- Windows services must be explicitly configured to run under the tester account when they need that account's Windows-authenticated SQL access.

## Version 8 script names

```text
Setup-SqlTestUser-Server-v8.ps1
Setup-SqlTestUser-Client-v8.ps1
```
