# Splunk Universal Forwarder + Sysmon Deployment Script

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![Language](https://img.shields.io/badge/language-Batch-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

A Windows batch script for automated, idempotent deployment of
**Splunk Universal Forwarder** and **Sysmon** across a Windows
environment — typically distributed via **Active Directory Group Policy (GPO)**
or any endpoint management tool.

Designed to be safe to run repeatedly: it only changes what is
actually out of date.

- **Author:** Shahpasandi
- **Website:** https://shahpasandi.github.io/
- **License:** MIT

---

## Quick Start

1. Edit `DEPLOY_SHARE` and the file names at the top of the script.
2. Place the required files on the share.
3. Run the script as Administrator (or via a GPO Startup script).

---

## Features

- **Idempotent deployment** — running the script multiple times does not
  produce unnecessary changes or restarts.
- **Hash-based change detection** using SHA256 (`certutil`) for
  `inputs.conf`, `outputs.conf`, and the Sysmon configuration.
- **Automatic Splunk Universal Forwarder install/upgrade**
  - Detects installed version via `splunk.exe version`, with a
    registry fallback.
  - Upgrades only when the MSI version differs from the installed version.
  - Silently installs with `msiexec /quiet /norestart`.
- **Sysmon install & config refresh**
  - Installs Sysmon if the `Sysmon64` service is not present.
  - Updates the Sysmon configuration only when its hash changes.
- **Configuration file deployment**
  - Copies `inputs.conf` and `outputs.conf` from a central share
    to the correct Splunk paths.
  - Creates target directories when missing.
- **Smart service management**
  - Restarts the `SplunkForwarder` service only when needed.
  - Falls back to `taskkill` and `splunk.exe start` on failure.
- **Fail-fast validation** — checks network share and all required files
  before doing anything.
- **Logging** — MSI upgrade logs written to `%TEMP%`.

---

## Requirements

- Windows Server / Windows 10+ (64-bit)
- Administrator privileges (the script must run elevated)
- Network access to the deployment share
- PowerShell not required — pure `cmd.exe` batch

---

## Repository Layout

```text
.
├── splunk-sysmon-deploy.bat   # main deployment script
├── README.md
├── LICENSE
└── examples/
    ├── inputs.conf.example
    └── outputs.conf.example
```

The actual `inputs.conf` / `outputs.conf` used in production should
**not** be committed — they may contain indexer addresses or credentials.

---

## Configuration

Edit the block at the top of `splunk-sysmon-deploy.bat`:

```bat
set "DEPLOY_SHARE=\\YOUR-FILESERVER\YOUR-SHARE\Splunk_for_Servers"
set "SYSMON_EXE_NAME=Sysmon64.exe"
set "SYSMON_CONFIG_NAME=sysmonconfig-export.xml"
set "SPLUNK_MSI_NAME=splunkforwarder-<version>-windows-x64.msi"
set "INPUTS_CONFIG_NAME=inputs.conf"
set "OUTPUTS_CONFIG_NAME=outputs.conf"
```

Place the following files on the share:

| File | Purpose |
|---|---|
| `Sysmon64.exe` | Sysmon binary |
| `sysmonconfig-export.xml` | Sysmon configuration |
| `splunkforwarder-*.msi` | Splunk Universal Forwarder installer |
| `inputs.conf` | Splunk input configuration |
| `outputs.conf` | Splunk output (indexer) configuration |

---

## Usage

### Manual run (elevated Command Prompt)

```bat
splunk-sysmon-deploy.bat
```

### Via Group Policy

1. Copy the script to a share readable by computer accounts
   (e.g. `\\domain\NETLOGON\scripts\`).
2. In **Group Policy Management**, create/edit a GPO applied to the
   target OU.
3. Navigate to:
   `Computer Configuration → Policies → Windows Settings → Scripts → Startup`
4. Add the script as a **Startup** script.
5. Link the GPO and reboot a test machine.

---

## How Change Detection Works

| Artifact | Detection method | Stored at |
|---|---|---|
| Splunk version | `splunk.exe version` → registry fallback | `%ProgramData%\SplunkVersion.txt` |
| Sysmon config | SHA256 of `sysmonconfig-export.xml` | `%ProgramData%\SplunkSysmonConfig.sha256` |
| `inputs.conf` | SHA256 source vs destination | — |
| `outputs.conf` | SHA256 source vs destination | — |

---

## Exit Behavior

- If the network share or any required file is missing, the script
  aborts immediately.
- The Splunk service is restarted only if a version upgrade or
  configuration change occurred.
- A summary is printed at the end.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Cannot access network share` | Share unreachable or no permissions for the computer account | Verify `\\server\share` from the target machine with `dir` |
| `Version mismatch` every run | Installed version format differs from the MSI filename | Compare `splunk.exe version` output with the MSI file name |
| `Sysmon installation failed` | Not running elevated, or AV blocking | Run as Administrator and check the Event Log |
| Splunk service won't restart | Process locked by another component | Script auto-falls back to `taskkill` / `splunk.exe start` |
| MSI upgrade fails | MSI log written to `%TEMP%` | Inspect `splunk_upgrade_<version>.log` |
| Sysmon config not refreshed | Hash file missing or stale | Delete `%ProgramData%\SplunkSysmonConfig.sha256` and re-run |

---

## Security Notes

- Do **not** commit production `inputs.conf` / `outputs.conf` to a public
  repository. Use the `examples/*.example` files as templates.
- MSI upgrade logs are written to `%TEMP%` on the target machine.
- The script runs with `USE_LOCAL_SYSTEM=1` for the Splunk service.
- Always validate the script against your organization's security
  policies before deploying to production.

---

## Disclaimer

This script is provided **as-is**, without warranty of any kind.
Test it in a lab environment before rolling it out to production.
You are responsible for validating it against your organization's
security and compliance requirements.

---

## License

MIT
