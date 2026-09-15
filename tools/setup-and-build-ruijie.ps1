#Requires -Version 5.1
<#
.SYNOPSIS
  One-click: install WSL/Ubuntu if needed, then build the Ruijie EW1200G Pro sysupgrade .bin.
#>

param(
    [switch]$SkipWslInstall,
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root "EXTRACTED-OPENWRT-FASTFI-V2.5.1\rootfs\build-image.sh"))) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$Overlay = Join-Path $Root "EXTRACTED-OPENWRT-FASTFI-V2.5.1\rootfs"
$OutDir  = Join-Path $Root "KonekSik-fi Piso Wifi Production\01-RUIJIE-OPENWRT"
$LogDir  = Join-Path $Root "KonekSik-fi Piso Wifi Production\logs"
$LogPath = Join-Path $LogDir "ruijie-build.log"
$Marker  = Join-Path $env:TEMP "koneksik-wsl-reboot-needed.flag"

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==== $msg ====" -ForegroundColor Cyan
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminRelaunch {
    Write-Host "Administrator rights needed to install WSL." -ForegroundColor Yellow
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
    exit 0
}

function Invoke-WslQuiet {
    param(
        [Parameter(Mandatory = $true)][string[]]$Args,
        [switch]$Utf16List
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "wsl.exe"
        $psi.Arguments = ($Args | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join " "
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        # wsl -l is UTF-16; normal Linux commands are UTF-8
        if ($Utf16List) {
            $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
            $psi.StandardErrorEncoding = [System.Text.Encoding]::Unicode
        } else {
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        }
        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $text = (($stdout + "`n" + $stderr) -replace "\0", "").Trim()
        return @{ Code = $p.ExitCode; Text = $text }
    } catch {
        return @{ Code = 1; Text = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Test-WslPresent {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    $r = Invoke-WslQuiet -Args @("--status")
    if ($r.Text -match "is not installed|not installed") { return $false }
    return $true
}

function Get-WslDistros {
    $r = Invoke-WslQuiet -Args @("-l", "-q") -Utf16List
    if ($r.Text -match "is not installed|not installed") { return @() }
    if (-not $r.Text) { return @() }
    return @(
        $r.Text -split "[\r\n]+" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }
    )
}

function Test-UbuntuReady {
    # Direct probe - do not rely only on distro list parsing
    foreach ($name in @("Ubuntu", "Ubuntu-24.04", "Ubuntu-22.04", "Ubuntu-20.04")) {
        $r = Invoke-WslQuiet -Args @("-d", $name, "-u", "root", "--", "echo", "ok")
        if ($r.Code -eq 0 -and $r.Text -match "ok") {
            return $name
        }
    }
    $distros = Get-WslDistros
    foreach ($name in $distros) {
        if ($name -notmatch "Ubuntu") { continue }
        $r = Invoke-WslQuiet -Args @("-d", $name, "-u", "root", "--", "echo", "ok")
        if ($r.Code -eq 0 -and $r.Text -match "ok") {
            return $name
        }
    }
    return $null
}

function Install-WslUbuntu {
    Write-Step "Installing WSL + Ubuntu (one-time)"
    if (-not (Test-IsAdmin)) { Request-AdminRelaunch }

    Write-Host "Enabling WSL features and installing Ubuntu..."
    Write-Host "This can take several minutes. A reboot may be required."
    Write-Host ""

    & wsl.exe --install -d Ubuntu --no-launch
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Host "wsl --install returned $code - trying feature enable + store install..." -ForegroundColor Yellow
        & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
        & wsl.exe --install -d Ubuntu --no-launch
        $code = $LASTEXITCODE
    }

    "WSL install attempted $(Get-Date -Format o)" | Set-Content -Path $Marker -Encoding ASCII
    Write-Host ""
    Write-Host "WSL install step finished (exit $code)." -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT:" -ForegroundColor Yellow
    Write-Host "  1. REBOOT this PC if Windows asks (or reboot anyway if Ubuntu is not ready)."
    Write-Host "  2. After reboot, double-click BUILD-RUIJIE-BIN.bat again."
    Write-Host "     IMPORTANT: do NOT Run as administrator for the build step."
    Write-Host "  3. If Ubuntu opens a first-run window, create a username/password, close it, then re-run the bat."
    Write-Host ""
    pause
    exit 0
}

function Ensure-WslReady {
    if ($SkipWslInstall) { return }

    # Build must run as normal user (WSL distros are per-user).
    # Admin window often cannot see your Ubuntu.
    $readyName = Test-UbuntuReady
    if ($readyName) {
        $script:Distro = $readyName
        if (Test-Path $Marker) { Remove-Item $Marker -Force -ErrorAction SilentlyContinue }
        Write-Host "Ubuntu ready: $readyName"
        return
    }

    if (Test-IsAdmin) {
        Write-Step "Wrong window (Administrator)"
        Write-Host "Ubuntu is set up under your normal Windows user, but this window is Administrator." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Do this:"
        Write-Host "  1. Close THIS window"
        Write-Host "  2. Double-click BUILD-RUIJIE-BIN.bat normally (do NOT Run as administrator)"
        Write-Host ""
        pause
        exit 0
    }

    $wslOk = Test-WslPresent
    $distros = Get-WslDistros

    if (-not $wslOk -or $distros.Count -eq 0) {
        Install-WslUbuntu
    }

    Write-Step "Finishing Ubuntu setup"
    Write-Host "Trying to start Ubuntu..."
    $null = Invoke-WslQuiet -Args @("-d", "Ubuntu", "-u", "root", "--", "true")

    $readyName = Test-UbuntuReady
    if (-not $readyName) {
        Write-Host ""
        Write-Host "Ubuntu is installed but not ready yet." -ForegroundColor Yellow
        Write-Host "Do this once:"
        Write-Host "  - Open Start menu -> Ubuntu"
        Write-Host "  - Create a UNIX username and password when asked"
        Write-Host "  - Type exit and close the window"
        Write-Host "  - Double-click BUILD-RUIJIE-BIN.bat again (NOT as administrator)"
        Write-Host ""
        $ubuntuApp = Get-Command "ubuntu.exe" -ErrorAction SilentlyContinue
        if ($ubuntuApp) {
            Start-Process "ubuntu.exe"
        } else {
            Start-Process "wsl.exe" -ArgumentList "-d","Ubuntu"
        }
        pause
        exit 0
    }

    $script:Distro = $readyName
    if (Test-Path $Marker) { Remove-Item $Marker -Force -ErrorAction SilentlyContinue }
}

function Invoke-RuijieBuild {
    Write-Step "Building Ruijie OpenWrt sysupgrade .bin"
    Write-Host "Overlay : $Overlay"
    Write-Host "Log     : $LogPath"
    Write-Host "First build downloads OpenWrt ImageBuilder - can take 15-45+ minutes."
    Write-Host ""

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

    if (-not (Test-Path (Join-Path $Overlay "build-image.sh"))) {
        throw "Missing build-image.sh in $Overlay"
    }

    $distroName = $Distro
    if (-not $distroName) { $distroName = "Ubuntu" }
    $probe = Test-UbuntuReady
    if ($probe) { $distroName = $probe }

    $wp = Invoke-WslQuiet -Args @("-d", $distroName, "-u", "root", "--", "wslpath", "-a", $Overlay)
    $wslPath = ($wp.Text -split "[\r\n]+" | Where-Object { $_ -match "^/" } | Select-Object -First 1)
    if (-not $wslPath) { throw "wslpath failed for $Overlay" }

    $null = Invoke-WslQuiet -Args @("-d", $distroName, "-u", "root", "--", "bash", "-lc", "sed -i 's/\r`$//' '$wslPath/build-image.sh'")

    $cmd = "cd '$wslPath' && bash ./build-image.sh koneksik"
    Write-Host "[ruijie] Distro: $distroName"
    Write-Host "[ruijie] $cmd"
    Write-Host ""

    # Stream build output live
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & wsl.exe -d $distroName -u root -- bash -lc $cmd 2>&1 | Tee-Object -FilePath $LogPath
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) {
        throw "Build failed (exit $code). See $LogPath"
    }

    $bin = Get-ChildItem -Path $Overlay -Filter "fastfi-v6-*.bin" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $bin) {
        $bin = Get-ChildItem -Path $Overlay -Filter "*.bin" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "kernel" } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $bin) {
        throw ("No .bin produced in " + $Overlay + " - see " + $LogPath)
    }

    $dest = Join-Path $OutDir "KonekSik-fi-EW1200G-PRO-sysupgrade.bin"
    Copy-Item -Force $bin.FullName $dest
    $sha = "$($bin.FullName).sha256"
    if (Test-Path $sha) {
        Copy-Item -Force $sha "$dest.sha256"
    }

    ("OK - " + $bin.Name + " -> KonekSik-fi-EW1200G-PRO-sysupgrade.bin (" + (Get-Date) + ")") |
        Set-Content (Join-Path $OutDir "STATUS.txt") -Encoding ASCII

    Write-Step "DONE"
    Write-Host "Firmware ready:" -ForegroundColor Green
    Write-Host "  $dest"
    Write-Host ""
    Write-Host "Upload this file in Ruijie Admin -> OTA Update -> Upload Firmware"
    Write-Host "(or flash via your first-install / recovery method if still on stock Ruijie)."
    Write-Host ""
    explorer.exe $OutDir
}

Write-Host ""
Write-Host "KonekSik-fi - Ruijie .bin one-click builder" -ForegroundColor Green
Write-Host "Project: $Root"
Write-Host ""

Ensure-WslReady
Invoke-RuijieBuild

Write-Host "Press Enter to close..."
[void][Console]::ReadLine()
