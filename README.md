# PowerMaster

A diagnostic-first Windows 11 power optimization tool for Modern Standby (S0) systems. Identify what keeps your device awake and apply safe, targeted changes that improve battery life without breaking core Windows behavior.

## Key Features

| Category | What it does |
| --- | --- |
| Deep Sleep Diagnostics | Uses `powercfg /sleepstudy` and `powercfg /requests` to surface blockers that prevent efficient idle states. |
| Per-App Background Governance | Maps wake sources and background activity to specific processes so you can target the right offenders. |
| Automated Energy Recommendations | Generates actionable suggestions based on actual system traces, not guesses. |
| Process Efficiency (Eco Mode) | Applies Eco Mode where appropriate to reduce CPU wakeups and background churn. |
| Minimalist Telemetry Enforcement | Reduces unnecessary data collection without disabling core Windows services. |

## Installation

PowerMaster is a PowerShell script. You can run it as a signed script or allow unsigned execution.

### Option A: Run a signed script

If the script is signed, PowerShell will allow it when your policy requires signed code.

```powershell
# From the PowerMaster directory
.\PowerMaster.ps1
```

### Option B: Run an unsigned script

If the script is unsigned, you must allow local scripts.

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow local scripts for the current user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Run the tool
.\PowerMaster.ps1
```

## Usage

### Run diagnostics (non-destructive)

```powershell
.\PowerMaster.ps1 -Mode Diagnose
```

### Apply a power profile

```powershell
.\PowerMaster.ps1 -Mode Apply -Profile Balanced
```

## Safety and Design Philosophy

PowerMaster is non-destructive by design. It does not fight Windows power design or disable critical services. It prioritizes observation, attribution, and safe adjustments that align with how Modern Standby is intended to work.

Browser processes are treated with extra care. PowerMaster highlights background activity but avoids aggressive actions that would break tab restoration, sync, or security isolation.

## Advisory

PowerMaster includes a built-in Network Tethering Guide to help you prevent hotspot and tethering services from silently keeping the system awake.
