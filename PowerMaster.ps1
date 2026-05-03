# PowerMaster Utility v3 - Windows 11 Modern Standby Edition
$ErrorActionPreference = "SilentlyContinue"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProfilePath = Join-Path $ScriptRoot "powermaster.profiles.json"
$LogPath = Join-Path $ScriptRoot "powermaster.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$timestamp [$Level] $Message"
}

function Write-Panel {
    param(
        [string]$Title,
        [string[]]$Lines
    )
    Write-Host "=" * 64 -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "-" * 64 -ForegroundColor DarkCyan
    foreach ($line in $Lines) {
        Write-Host $line
    }
    Write-Host "=" * 64 -ForegroundColor DarkCyan
}

function Read-ContinuePrompt {
    Read-Host "`nPress Enter to continue" | Out-Null
}

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsEdition {
    try {
        $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        return $cv.EditionID
    } catch {
        return "Unknown"
    }
}

function Initialize-ProfileFile {
    if (-not (Test-Path $ProfilePath)) {
        $defaultProfiles = @{
            Profiles = @{
                Battery = @{
                    PowerPlan = "Power saver"
                    StopServices = @("WSearch")
                    KillProcesses = @("Telegram", "WhatsApp", "AndroidEmulatorEn", "aow_exe", "VLC")
                    ApplyEnergyRecommendations = $true
                }
                AC = @{
                    PowerPlan = "Balanced"
                    StartServices = @("WSearch")
                    ApplyEnergyRecommendations = $false
                }
                Custom = @{}
            }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $ProfilePath -Value $defaultProfiles -Encoding UTF8
    }
}

function Get-Profiles {
    Initialize-ProfileFile
    return (Get-Content -Path $ProfilePath -Raw | ConvertFrom-Json)
}

function Get-PowerSchemeGuidByName {
    param([string]$Name)
    $lines = powercfg /list 2>$null
    foreach ($line in $lines) {
        if ($line -match "Power Scheme GUID:\s+([a-f0-9-]+)\s+\((.+)\)") {
            $guid = $matches[1]
            $schemeName = $matches[2]
            if ($schemeName -ieq $Name) {
                return $guid
            }
        }
    }
    return $null
}

function Set-PowerPlan {
    param([string]$NameOrGuid)
    $guid = $null
    if ($NameOrGuid -match "^[a-f0-9-]{36}$") {
        $guid = $NameOrGuid
    } else {
        $guid = Get-PowerSchemeGuidByName -Name $NameOrGuid
    }

    if (-not $guid) {
        Write-Host "Power plan not found: $NameOrGuid" -ForegroundColor Yellow
        Write-Log "Power plan not found: $NameOrGuid" "WARN"
        return
    }

    powercfg /setactive $guid | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to set power plan ($NameOrGuid)." -ForegroundColor Yellow
        Write-Log "Failed to set power plan: $NameOrGuid" "WARN"
    } else {
        Write-Host "Power plan set: $NameOrGuid" -ForegroundColor Green
        Write-Log "Power plan set: $NameOrGuid"
    }
}

function Set-EnergyRecommendations {
    Write-Host "Applying Energy Recommendations..." -ForegroundColor Gray
    powercfg /change monitor-timeout-dc 3 | Out-Null
    powercfg /change monitor-timeout-ac 10 | Out-Null
    powercfg /change standby-timeout-dc 10 | Out-Null
    powercfg /change standby-timeout-ac 30 | Out-Null
    powercfg /change hibernate-timeout-dc 20 | Out-Null
    powercfg /change hibernate-timeout-ac 60 | Out-Null

    $personalizePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (-not (Test-Path $personalizePath)) {
        New-Item -Path $personalizePath -Force | Out-Null
    }
    Set-ItemProperty -Path $personalizePath -Name "EnableTransparency" -Value 0 -Type DWord

    Write-Host "Energy recommendations applied." -ForegroundColor Green
    Write-Log "Energy recommendations applied"
}

function Invoke-ModernStandbyAudit {
    $reportDir = Join-Path $env:USERPROFILE "PowerMaster"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $sleepstudyPath = Join-Path $reportDir "sleepstudy-$timestamp.html"

    Write-Host "Collecting power requests..." -ForegroundColor Gray
    $requests = powercfg /requests
    Write-Panel "Power Requests" $requests
    Write-Log "Power requests collected"

    Write-Host "Generating sleepstudy report..." -ForegroundColor Gray
    powercfg /sleepstudy /output "$sleepstudyPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Sleepstudy failed or unsupported on this device." -ForegroundColor Yellow
        Write-Log "Sleepstudy failed or unsupported" "WARN"
    } else {
        Write-Host "Sleepstudy saved to: $sleepstudyPath" -ForegroundColor Green
        Write-Log "Sleepstudy saved: $sleepstudyPath"
    }
}

function Show-BatteryHealth {
    $bat = Get-CimInstance -ClassName Win32_Battery
    if (-not $bat) {
        Write-Host "No battery detected." -ForegroundColor Yellow
        return
    }

    $reportPath = Join-Path $env:USERPROFILE "battery-report.html"
    powercfg /batteryreport /output "$reportPath" | Out-Null
    Write-Panel "Battery Status" @(
        "Full Charge Capacity : $($bat.FullChargeCapacity) mWh",
        "Charge Remaining     : $($bat.EstimatedChargeRemaining)%",
        "Estimated RunTime    : $($bat.EstimatedRunTime) mins",
        "Cycle Count          : $($bat.CycleCount)",
        "Report Path          : $reportPath"
    )
    Write-Log "Battery report generated: $reportPath"
}

function Get-AppBackgroundPermissions {
    $apps = Get-AppxPackage | Sort-Object Name
    $results = @()
    foreach ($app in $apps) {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$($app.PackageFamilyName)"
        $disabled = 0
        $disabledByUser = 0
        if (Test-Path $keyPath) {
            $props = Get-ItemProperty -Path $keyPath
            $disabled = [int]($props.Disabled -as [int])
            $disabledByUser = [int]($props.DisabledByUser -as [int])
        }
        $mode = if ($disabled -eq 1 -or $disabledByUser -eq 1) { "Never" } else { "Always" }
        $results += [pscustomobject]@{
            Name = $app.Name
            PackageFamilyName = $app.PackageFamilyName
            Mode = $mode
        }
    }
    return $results
}

function Set-AppBackgroundPermission {
    param(
        [string]$PackageFamilyName,
        [ValidateSet("PowerOptimized", "Never")][string]$Mode
    )
    $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$PackageFamilyName"
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    if ($Mode -eq "Never") {
        Set-ItemProperty -Path $keyPath -Name "Disabled" -Value 1 -Type DWord
        Set-ItemProperty -Path $keyPath -Name "DisabledByUser" -Value 1 -Type DWord
    } else {
        Set-ItemProperty -Path $keyPath -Name "Disabled" -Value 0 -Type DWord
        Set-ItemProperty -Path $keyPath -Name "DisabledByUser" -Value 0 -Type DWord
    }

    Write-Log "Background permission set: $PackageFamilyName => $Mode"
}

function Invoke-AppBackgroundGovernance {
    $apps = Get-AppBackgroundPermissions
    $alwaysApps = $apps | Where-Object { $_.Mode -eq "Always" }
    Write-Panel "Background Apps: Always" ($alwaysApps | ForEach-Object { "{0} | {1}" -f $_.Name, $_.PackageFamilyName })

    $target = Read-Host "`nEnter a PackageFamilyName to set PowerOptimized, or press Enter to skip"
    if ($target) {
        Set-AppBackgroundPermission -PackageFamilyName $target -Mode "PowerOptimized"
        Write-Host "Set to PowerOptimized: $target" -ForegroundColor Green
    }
}

function Initialize-EfficiencyModeApi {
    if ($script:EcoApiLoaded) {
        return
    }

    $code = @"
using System;
using System.Runtime.InteropServices;
public static class PowerThrottlingApi {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetProcessInformation(IntPtr h, int infoClass, ref PROCESS_POWER_THROTTLING_STATE state, int size);

    public const int ProcessPowerThrottling = 4;
    public const uint PROCESS_SET_INFORMATION = 0x0200;
    public const uint PROCESS_QUERY_INFORMATION = 0x0400;
    public const uint PROCESS_POWER_THROTTLING_EXECUTION_SPEED = 0x1;
    public const uint PROCESS_POWER_THROTTLING_CURRENT_VERSION = 1;

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_POWER_THROTTLING_STATE {
        public uint Version;
        public uint ControlMask;
        public uint StateMask;
    }
}
"@

    Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue | Out-Null
    $script:EcoApiLoaded = $true
}

function Enable-EfficiencyMode {
    param([int[]]$Pids)
    Initialize-EfficiencyModeApi

    foreach ($processId in $Pids) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction Stop
            $proc.PriorityClass = "Idle"

            $access = [PowerThrottlingApi]::PROCESS_SET_INFORMATION -bor [PowerThrottlingApi]::PROCESS_QUERY_INFORMATION
            $handle = [PowerThrottlingApi]::OpenProcess($access, $false, $processId)
            if ($handle -eq [IntPtr]::Zero) {
                Write-Host "Failed to open process: $processId" -ForegroundColor Yellow
                continue
            }

            $state = New-Object PowerThrottlingApi+PROCESS_POWER_THROTTLING_STATE
            $state.Version = [PowerThrottlingApi]::PROCESS_POWER_THROTTLING_CURRENT_VERSION
            $state.ControlMask = [PowerThrottlingApi]::PROCESS_POWER_THROTTLING_EXECUTION_SPEED
            $state.StateMask = [PowerThrottlingApi]::PROCESS_POWER_THROTTLING_EXECUTION_SPEED

            $ok = [PowerThrottlingApi]::SetProcessInformation($handle, [PowerThrottlingApi]::ProcessPowerThrottling, [ref]$state, [System.Runtime.InteropServices.Marshal]::SizeOf($state))
            [PowerThrottlingApi]::CloseHandle($handle) | Out-Null

            if ($ok) {
                Write-Host "Efficiency Mode applied to PID $processId." -ForegroundColor Green
                Write-Log "Efficiency Mode applied to PID $processId"
            } else {
                Write-Host "Efficiency Mode failed for PID $processId." -ForegroundColor Yellow
                Write-Log "Efficiency Mode failed for PID $processId" "WARN"
            }
        } catch {
            Write-Host ("Failed to apply Efficiency Mode to PID {0}: {1}" -f $processId, $_.Exception.Message) -ForegroundColor Yellow
            Write-Log ("Efficiency Mode error for PID {0}: {1}" -f $processId, $_.Exception.Message) "WARN"
        }
    }
}

function Invoke-EfficiencyMode {
    Write-Host "Top 10 CPU Consumers:" -ForegroundColor White
    Write-Host "ID`tCPU(s)`tProcess" -ForegroundColor Gray
    $procs = Get-Process | Where-Object { $_.CPU -gt 1 } | Sort-Object CPU -Descending | Select-Object -First 10
    foreach ($p in $procs) {
        Write-Host "$($p.Id)`t$([math]::Round($p.CPU,1))`t$($p.ProcessName)"
    }

    $pidInput = Read-Host "`nEnter PID(s) to apply Efficiency Mode (comma-separated)"
    if ($pidInput) {
        $pids = $pidInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
        if ($pids.Count -gt 0) {
            Enable-EfficiencyMode -Pids $pids
        }
    }
}

function Set-TelemetryMinimalist {
    if (-not (Test-Admin)) {
        Write-Host "Administrator privileges required for telemetry changes." -ForegroundColor Yellow
        return
    }

    $edition = Get-WindowsEdition
    $level = 1
    if ($edition -match "Enterprise|Education") {
        $level = 0
    }

    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "AllowTelemetry" -Value $level -Type DWord
    Set-ItemProperty -Path $path -Name "MaxTelemetryAllowed" -Value $level -Type DWord

    Write-Host "Telemetry set to level $level (Edition: $edition)." -ForegroundColor Green
    Write-Log "Telemetry set to level $level (Edition: $edition)"
}

function Show-TetheringAdvisor {
    Write-Panel "Tethering Advisor" @(
        "USB Tethering: Lowest phone drain, high throughput, charges phone on many laptops.",
        "Wi-Fi Hotspot: Highest phone drain, strong throughput, supports multiple devices.",
        "Bluetooth: Lowest throughput, moderate phone drain, best for light tasks only.",
        "Recommendation: USB for single-device reliability; Wi-Fi only when you need multi-device access."
    )
}

function Start-ElevatedSession {
    if (Test-Admin) {
        Write-Host "Already running as Administrator." -ForegroundColor Green
        return
    }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        Write-Host "Unable to determine script path for relaunch." -ForegroundColor Yellow
        return
    }

    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs | Out-Null
    Write-Log "Relaunch requested as Administrator"
    exit
}

function Invoke-Profile {
    param([string]$ProfileName)
    $profiles = Get-Profiles
    $selectedProfile = $profiles.Profiles.$ProfileName
    if (-not $selectedProfile) {
        Write-Host "Profile not found: $ProfileName" -ForegroundColor Yellow
        return
    }

    Write-Host "Applying profile: $ProfileName" -ForegroundColor Cyan

    if ($selectedProfile.PowerPlan) {
        Set-PowerPlan -NameOrGuid $selectedProfile.PowerPlan
    }

    if ($selectedProfile.StopServices) {
        foreach ($svc in $selectedProfile.StopServices) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "Service stopped: $svc"
        }
    }

    if ($selectedProfile.StartServices) {
        foreach ($svc in $selectedProfile.StartServices) {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
            Write-Log "Service started: $svc"
        }
    }

    if ($selectedProfile.KillProcesses) {
        foreach ($proc in $selectedProfile.KillProcesses) {
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
            Write-Log "Process stopped: $proc"
        }
    }

    if ($selectedProfile.ApplyEnergyRecommendations) {
        Set-EnergyRecommendations
    }

    Write-Host "Profile applied: $ProfileName" -ForegroundColor Green
    Write-Log "Profile applied: $ProfileName"
}

function Show-Menu {
    Clear-Host
    Write-Host "================ POWERMASTER UTILITY v3 ================" -ForegroundColor Cyan
    Write-Host "1. APPLY PROFILE" -ForegroundColor Yellow
    Write-Host "2. MODERN STANDBY AUDIT" -ForegroundColor White
    Write-Host "3. BATTERY HEALTH CHECK" -ForegroundColor White
    Write-Host "4. APP BACKGROUND GOVERNANCE" -ForegroundColor White
    Write-Host "5. EFFICIENCY MODE" -ForegroundColor White
    Write-Host "6. ENERGY RECOMMENDATIONS" -ForegroundColor White
    Write-Host "7. TELEMETRY MINIMALIST" -ForegroundColor White
    Write-Host "8. TETHERING ADVISOR" -ForegroundColor White
    Write-Host "9. RELAUNCH AS ADMIN" -ForegroundColor White
    Write-Host "10. EXIT" -ForegroundColor White
    Write-Host "========================================================"
}

Initialize-ProfileFile

while ($true) {
    Show-Menu
    $choice = Read-Host "`nSelect an option (1-10)"

    switch ($choice) {
        "1" {
            $profiles = Get-Profiles
            $profileNames = $profiles.Profiles.PSObject.Properties.Name
            Write-Panel "Available Profiles" ($profileNames | ForEach-Object { $_ })
            $target = Read-Host "Enter profile name"
            if ($target) {
                Invoke-Profile -ProfileName $target
            }
            Read-ContinuePrompt
        }
        "2" {
            Invoke-ModernStandbyAudit
            Read-ContinuePrompt
        }
        "3" {
            Show-BatteryHealth
            Read-ContinuePrompt
        }
        "4" {
            Invoke-AppBackgroundGovernance
            Read-ContinuePrompt
        }
        "5" {
            Invoke-EfficiencyMode
            Read-ContinuePrompt
        }
        "6" {
            Set-EnergyRecommendations
            Read-ContinuePrompt
        }
        "7" {
            Set-TelemetryMinimalist
            Read-ContinuePrompt
        }
        "8" {
            Show-TetheringAdvisor
            Read-ContinuePrompt
        }
        "9" {
            Start-ElevatedSession
            Read-ContinuePrompt
        }
        "10" { exit }
    }
}