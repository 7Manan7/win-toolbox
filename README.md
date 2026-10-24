# Windows Toolbox (`win-toolbox`)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)](https://microsoft.com/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6.svg)](https://www.microsoft.com/windows)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An all-in-one, standalone PowerShell suite for Windows maintenance, developer workflows, gaming performance, network troubleshooting, and security auditing.

Everything is completely self-contained: **clone and run**. No manual installation, system registry tweaks, or copying scripts to external directories needed. Run directly via `Script-Launcher.bat` or `launch.bat`.

---

## ⚡ Quick Start

### 1. Clone the repository
```powershell
git clone https://github.com/7Manan7/win-toolbox.git
cd win-toolbox
```

### 2. Launch the Interactive Menu
Double-click `launch.bat` (or `Script-Launcher.bat`), or run from your terminal:
```powershell
.\launch.bat
```
*Or directly via PowerShell:*
```powershell
.\launch.ps1
```

> [!NOTE]
> The launcher will automatically prompt for Administrator privileges (UAC) if not already elevated, then display a categorized menu of all available tools.

---

## 🧭 Repository Structure

```
win-toolbox/
├── launch.bat                  # Instant double-click launcher
├── launch.ps1                  # PowerShell CLI launcher shortcut
├── Script-Launcher.bat         # Direct batch launcher wrapper
├── Script-Launcher.ps1         # Self-elevating, interactive categorized menu
├── Scripts/
│   ├── Backup/                 # Backup, file organization, duplicate detection
│   ├── Dev/                    # Ports, JDK switching, build caches, services, Git
│   ├── Gaming/                 # Power profiles, game mode, hardware logging, shaders
│   ├── Maintenance/            # Health checks, disk usage, temp cleanup, updates
│   ├── Network/                # Hosts editor, speed/latency diagnostics, stack reset
│   ├── Security/               # Open ports audit, Defender scans, privacy/history cleanup
│   └── Utilities/              # Winget installer/updater, environment backups
├── .gitignore
├── .gitattributes
├── LICENSE
└── README.md
```

---

## 🚀 Running Scripts Directly (Standalone CLI)

Every script can also be executed independently from any PowerShell console without launching the interactive menu.

```powershell
# Find and kill a stuck process holding port 8080 or 3306
.\Scripts\Dev\Kill-Port.ps1 -Ports 8080, 3306

# Preview downloads folder organization without moving files
.\Scripts\Backup\Organize-Downloads.ps1 -WhatIf

# Clean temp files and system caches, leaving browser caches intact
.\Scripts\Maintenance\Clean-TempCache.ps1 -SkipBrowsers

# Switch system JDK interactively
.\Scripts\Dev\Switch-JDK.ps1

# Run a quick network ping & speed test
.\Scripts\Network\Network-Check.ps1
```

---

## 📚 Script Catalog

### 🛠️ Developer Tools (`Scripts/Dev/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Kill-Port.ps1`](file:///Scripts/Dev/Kill-Port.ps1) | Finds what process holds one or more TCP ports (e.g. stuck Spring Boot / Node servers) and kills it with its children. | `.\Kill-Port.ps1 -Ports 8080,3000` |
| [`Switch-JDK.ps1`](file:///Scripts/Dev/Switch-JDK.ps1) | Auto-detects installed JDKs across standard vendors (Adoptium, Corretto, Zulu, Oracle, etc.) and switches `JAVA_HOME` & `PATH`. | `.\Switch-JDK.ps1` |
| [`Clean-BuildCaches.ps1`](file:///Scripts/Dev/Clean-BuildCaches.ps1) | Cleans Maven (`.m2`) SNAPSHOTs, failed download markers, and Gradle daemon caches to reclaim space and fix corrupt dependencies. | `.\Clean-BuildCaches.ps1 -Mode 5` |
| [`Dev-Services.ps1`](file:///Scripts/Dev/Dev-Services.ps1) | Starts, stops, or checks status of local development databases (MySQL, PostgreSQL, Redis, MongoDB) and Docker containers. | `.\Dev-Services.ps1 -Action start` |
| [`Git-BulkUpdate.ps1`](file:///Scripts/Dev/Git-BulkUpdate.ps1) | Recursively scans for git repositories under a folder and runs status, fetch, or fast-forward pull (`--ff-only`). | `.\Git-BulkUpdate.ps1 -Action pull` |

### 🧹 System Maintenance (`Scripts/Maintenance/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Clean-TempCache.ps1`](file:///Scripts/Maintenance/Clean-TempCache.ps1) | Cleans temp files, Windows Update download cache, crash dumps, WER reports, browser caches, and Recycle Bin; reports freed space. | `.\Clean-TempCache.ps1 -WhatIf` |
| [`Disk-SpaceReport.ps1`](file:///Scripts/Maintenance/Disk-SpaceReport.ps1) | Scans drive usage and pinpoints the largest directories and files under any specified path. | `.\Disk-SpaceReport.ps1 -Path C:\Users -Top 20` |
| [`System-HealthCheck.ps1`](file:///Scripts/Maintenance/System-HealthCheck.ps1) | Full automated Windows diagnostic: disk SMART health, DISM component repair, SFC integrity scan, and CHKDSK read check. | `.\System-HealthCheck.ps1` |
| [`Windows-Update.ps1`](file:///Scripts/Maintenance/Windows-Update.ps1) | Checks and installs available Windows updates via `PSWindowsUpdate` with auto-reboot support. | `.\Windows-Update.ps1 -ListOnly` |
| [`New-RestorePoint.ps1`](file:///Scripts/Maintenance/New-RestorePoint.ps1) | Creates a System Restore point immediately (bypasses Windows' 24-hour frequency restriction). | `.\New-RestorePoint.ps1` |

### 🎮 Gaming & Performance (`Scripts/Gaming/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Game-Mode.ps1`](file:///Scripts/Gaming/Game-Mode.ps1) | Toggles High Performance power plan, enables Game Mode, suspends background telemetry/indexing services, and closes chosen apps. | `.\Game-Mode.ps1 -Mode On` |
| [`Hardware-Logger.ps1`](file:///Scripts/Gaming/Hardware-Logger.ps1) | Logs CPU, RAM, and GPU stats (via `nvidia-smi`) to CSV while playing; outputs peak temps and thermal throttling summary upon exit. | `.\Hardware-Logger.ps1 -IntervalSeconds 2` |
| [`Clear-ShaderCache.ps1`](file:///Scripts/Gaming/Clear-ShaderCache.ps1) | Clears NVIDIA, AMD, and DirectX D3D shader caches to resolve shader compilation stuttering after driver updates. | `.\Clear-ShaderCache.ps1` |
| [`Startup-Manager.ps1`](file:///Scripts/Gaming/Startup-Manager.ps1) | Lists and toggles registry and folder startup entries with full reversibility (mirroring Windows Task Manager). | `.\Startup-Manager.ps1` |

### 🌐 Network & Diagnostics (`Scripts/Network/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Hosts-Manager.ps1`](file:///Scripts/Network/Hosts-Manager.ps1) | Interactive hosts file manager: view, add, disable, or delete entries with timestamped automatic backups. | `.\Hosts-Manager.ps1` |
| [`Network-Check.ps1`](file:///Scripts/Network/Network-Check.ps1) | Tests ping, jitter, packet loss to gateway and public DNS, DNS lookup duration, and download speed; logs to CSV. | `.\Network-Check.ps1` |
| [`Network-Reset.ps1`](file:///Scripts/Network/Network-Reset.ps1) | Flushes DNS cache, clears ARP/NetBIOS tables, and renews DHCP IP lease. `-Full` resets Winsock and TCP/IP stack. | `.\Network-Reset.ps1 -Full` |
| [`Set-Dns.ps1`](file:///Scripts/Network/Set-Dns.ps1) | Configures fast, secure, or ad-blocking DNS providers (Cloudflare, Google, Quad9, AdGuard, Mullvad, WARP) with optional DNS-over-HTTPS (DoH). | `.\Set-Dns.ps1 -Provider AdGuard -EnableDoH` |

### 🛡️ Security & Privacy (`Scripts/Security/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Open-Ports-Report.ps1`](file:///Scripts/Security/Open-Ports-Report.ps1) | Scans all listening TCP/UDP ports, maps owning process & Windows services, flags WAN vs localhost exposure, and checks firewall state. | `.\Open-Ports-Report.ps1` |
| [`Defender-Scan.ps1`](file:///Scripts/Security/Defender-Scan.ps1) | Refreshes Defender antivirus definitions, runs a Quick or Full scan, and summarizes threat detections. | `.\Defender-Scan.ps1 -Type Quick` |
| [`Clear-WindowsHistory.ps1`](file:///Scripts/Security/Clear-WindowsHistory.ps1) | Clears file history, recent documents, Explorer address bar history, thumbnail caches, and optional search indexing database. | `.\Clear-WindowsHistory.ps1 -ClearThumbnails` |

### 💾 Backup & File Management (`Scripts/Backup/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Backup-Folders.ps1`](file:///Scripts/Backup/Backup-Folders.ps1) | Robust multi-threaded Robocopy backup with timestamped logs, auto-detecting backup drives and skipping build artifacts (`node_modules`, `target`, etc.). | `.\Backup-Folders.ps1` |
| [`Find-Duplicates.ps1`](file:///Scripts/Backup/Find-Duplicates.ps1) | Fast duplicate detection using file size grouping followed by SHA-256 hash validation; generates CSV and offers Recycle Bin cleanup. | `.\Find-Duplicates.ps1 -Path C:\Data` |
| [`Organize-Downloads.ps1`](file:///Scripts/Backup/Organize-Downloads.ps1) | Automatically categorizes messy folders (Downloads) into subfolders (`Images`, `Documents`, `Installers`, etc.) and archives old files. | `.\Organize-Downloads.ps1 -WhatIf` |

### 📦 Utilities (`Scripts/Utilities/`)
| Script | Description | Example Usage |
|---|---|---|
| [`Install-Apps.ps1`](file:///Scripts/Utilities/Install-Apps.ps1) | Batch-installs essential developer and workstation software via `winget` with interactive numbered selection. | `.\Install-Apps.ps1` |
| [`Update-Apps.ps1`](file:///Scripts/Utilities/Update-Apps.ps1) | Audits installed packages and bulk-upgrades outdated software through `winget`. | `.\Update-Apps.ps1` |
| [`Export-Environment.ps1`](file:///Scripts/Utilities/Export-Environment.ps1) | Creates a backup of user and system environment variables, PATH entries, installed programs, and an importable `winget` package manifest. | `.\Export-Environment.ps1` |

---

## ⚙️ Configuration & Customization

All scripts are pre-configured with auto-detecting defaults, but can be tailored:
- **Backup destinations**: [`Backup-Folders.ps1`](file:///Scripts/Backup/Backup-Folders.ps1) automatically detects secondary hard drives or defaults to your system drive's `\Backups` folder. You can override this with the `-Destination` parameter.
- **Git project root**: [`Git-BulkUpdate.ps1`](file:///Scripts/Dev/Git-BulkUpdate.ps1) automatically searches for your projects directory or prompts with your current location.
- **App install list**: Edit the `$Apps` dictionary in [`Install-Apps.ps1`](file:///Scripts/Utilities/Install-Apps.ps1) to add your favorite tools.

---

## 📋 Requirements
- **OS**: Windows 10 or Windows 11 (64-bit recommended)
- **Shell**: PowerShell 5.1 (built-in Windows PowerShell) or PowerShell 7+
- **Privileges**: Administrator rights for system management scripts (the launcher auto-requests elevation)
- **Package Manager**: [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (comes standard on Windows 10/11)

---

## 📄 License
This project is open-source under the [MIT License](LICENSE).
