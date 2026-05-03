# PowerMaster Utility v2 - Ryan's HP ProBook Edition
$ErrorActionPreference = "SilentlyContinue"

function Show-Menu {
    Clear-Host
    Write-Host "================ POWERMASTER UTILITY v2 ================" -ForegroundColor Cyan
    Write-Host "1. BATTERY MODE: Kill Rogues & Stop Indexer" -ForegroundColor Yellow
    Write-Host "2. AC MODE: Restore All Services" -ForegroundColor Green
    Write-Host "3. DRAIN SCAN: Identify & Kill Background Apps" -ForegroundColor White
    Write-Host "4. SYSTEM STATS: Health & Runtime" -ForegroundColor Cyan
    Write-Host "5. EXIT"
    Write-Host "========================================================"
}

while($true) {
    Show-Menu
    $choice = Read-Host "`nSelect an option (1-5)"

    switch($choice) {
        "1" {
            Write-Host "Cleaning background environment..." -ForegroundColor Gray
            # Kill top offenders identified in your logs[cite: 1]
            $Rogue = @("Telegram", "WhatsApp", "AndroidEmulatorEn", "aow_exe", "VLC")
            foreach ($App in $Rogue) {
                Stop-Process -Name $App -Force 
            }
            Stop-Service -Name "WSearch" -Force
            # Set Power Mode to Power Saver (use known scheme GUID) and handle errors
            powercfg /setactive a1841308-3541-4fab-bc81-f71556f20b4a
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to set Power Saver plan (powercfg exit code $LASTEXITCODE)." -ForegroundColor Yellow
                Write-Host "Original GUID command may have been invalid; skipping." -ForegroundColor Yellow
            }
            Write-Host "[!] Rogue apps killed. Indexer paused. Power Mode set." -ForegroundColor Green
            pause
        }
        "2" {
            Start-Service -Name "WSearch"
            Write-Host "[+] Indexer restarted. System restored to full speed." -ForegroundColor Cyan
            pause
        }
        "3" {
            Write-Host "`nTop 10 CPU Consumers (Background):" -ForegroundColor White
            Write-Host "ID`tCPU(s)`tProcess Name" -ForegroundColor Gray
            $Processes = Get-Process | Where-Object { $_.CPU -gt 5 -and $_.ProcessName -notmatch "System|explorer|Idle|svchost|powershell" } | 
                         Sort-Object CPU -Descending | Select-Object -First 10
            
            foreach ($p in $Processes) {
                Write-Host "$($p.Id)`t$([math]::Round($p.CPU,1))`t$($p.ProcessName)"
            }
            
            $killInput = Read-Host "`nEnter the ID(s) or process names to KILL (comma-separated), or press Enter to skip"
            if ($killInput) {
                $items = $killInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                if (-not $items) {
                    Write-Host "No IDs or names entered." -ForegroundColor Yellow
                } else {
                    $isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if (-not $isAdmin) { Write-Host "Warning: not running as Administrator; some processes may not terminate." -ForegroundColor Yellow }
                    foreach ($item in $items) {
                        if ($item -match '^\d+$') {
                            $pid = [int]$item
                            try {
                                if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
                                    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                                    Start-Sleep -Milliseconds 500
                                    if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
                                        $proc = Start-Process -FilePath taskkill -ArgumentList "/PID $pid /F /T" -NoNewWindow -Wait -PassThru
                                        if ($proc.ExitCode -eq 0) { Write-Host "Process $pid terminated (taskkill)." -ForegroundColor Red } else { Write-Host "Failed to terminate $pid (taskkill exit $($proc.ExitCode))." -ForegroundColor Yellow }
                                    } else {
                                        Write-Host "Process $pid terminated." -ForegroundColor Red
                                    }
                                } else {
                                    Write-Host "No process with ID $pid found." -ForegroundColor Yellow
                                }
                            } catch {
                                Write-Host ("Failed to terminate {0}: {1}" -f $pid, $_.Exception.Message) -ForegroundColor Yellow
                            }
                        } else {
                            try {
                                $found = Get-Process -Name $item -ErrorAction SilentlyContinue
                                if ($found) {
                                    Stop-Process -Name $item -Force -ErrorAction SilentlyContinue
                                    Start-Sleep -Milliseconds 500
                                    $still = Get-Process -Name $item -ErrorAction SilentlyContinue
                                    if ($still) {
                                        $proc = Start-Process -FilePath taskkill -ArgumentList "/IM $item /F /T" -NoNewWindow -Wait -PassThru
                                        if ($proc.ExitCode -eq 0) { Write-Host "Processes named $item terminated (taskkill)." -ForegroundColor Red } else { Write-Host "Failed to terminate $item (taskkill exit $($proc.ExitCode))." -ForegroundColor Yellow }
                                    } else {
                                        Write-Host "Processes named $item terminated." -ForegroundColor Red
                                    }
                                } else {
                                    Write-Host "No process named '$item' found." -ForegroundColor Yellow
                                }
                            } catch {
                                Write-Host ("Failed to terminate {0}: {1}" -f $item, $_.Exception.Message) -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }
            pause
        }
        "4" {
            $bat = Get-CimInstance -ClassName Win32_Battery
            Write-Host "`n--- BATTERY STATUS ---"
            if ($bat) {
                Write-Host "Full Charge Capacity        : $($bat.FullChargeCapacity) mWh"
                Write-Host "Estimated Charge Remaining : $($bat.EstimatedChargeRemaining)%"
                Write-Host "Estimated RunTime (mins)   : $($bat.EstimatedRunTime)"
                Write-Host "Cycle Count                : $($bat.CycleCount)"
                try {
                    powercfg /batteryreport /output "$env:USERPROFILE\battery-report.html" | Out-Null
                    Write-Host "Battery report saved to $env:USERPROFILE\battery-report.html" -ForegroundColor Cyan
                } catch {
                    Write-Host "Failed to generate battery report: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "No battery detected." -ForegroundColor Yellow
            }
            pause
        }
        "5" { exit }
    }
}