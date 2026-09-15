# Runs OpenWrt ImageBuilder from Windows via WSL.
# Usage: powershell -ExecutionPolicy Bypass -File tools\build-ruijie-wsl.ps1 -OverlayPath "...\rootfs" -LogPath "...\ruijie-build.log"

param(
    [Parameter(Mandatory = $true)][string]$OverlayPath,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$Suffix = "koneksik"
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw "WSL not installed. Run: wsl --install -d Ubuntu"
}
if (-not (Test-Path (Join-Path $OverlayPath "build-image.sh"))) {
    throw "build-image.sh not found in $OverlayPath"
}

$wslPath = (& wsl wslpath -a $OverlayPath).Trim()
if (-not $wslPath) { throw "wslpath failed for $OverlayPath" }

$cmd = "cd '$wslPath' && bash ./build-image.sh $Suffix"
Write-Host "[ruijie] WSL path: $wslPath"
Write-Host "[ruijie] $cmd"
# Run via cmd.exe so native WSL stderr warnings cannot become terminating
# PowerShell NativeCommandError records under $ErrorActionPreference=Stop.
$logEsc = $LogPath.Replace('"', '""')
$cmdEsc = $cmd.Replace('"', '""')
cmd.exe /c "wsl bash -lc `"$cmdEsc`" > `"$logEsc`" 2>&1"
$buildExit = $LASTEXITCODE
Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }
if ($buildExit -ne 0) {
    throw "OpenWrt build failed (exit $buildExit). See $LogPath"
}

$bins = Get-ChildItem -Path $OverlayPath -Filter "*.bin" -File |
    Where-Object { $_.Name -notmatch "kernel" } |
    Sort-Object LastWriteTime -Descending
if (-not $bins) {
    throw "No .bin produced in $OverlayPath"
}

$built = $bins[0].FullName
Write-Host "[ruijie] Built: $built"

# Symlink regression gate (must not ship Windows 'SYMLINK ->' placeholders)
$repoRoot = Split-Path (Split-Path $OverlayPath -Parent) -Parent
if (-not (Test-Path (Join-Path $repoRoot "tools\validate-firmware-symlinks.py"))) {
    $repoRoot = Split-Path $PSScriptRoot -Parent
}
$validator = Join-Path $repoRoot "tools\validate-firmware-symlinks.py"
$fastfi = Join-Path $repoRoot "FASTFI-RUIJIE-EW1200G-PRO-V2.5.1.bin"
if (Test-Path $validator) {
    Write-Host "[ruijie] Validating SquashFS symlinks..."
    $valArgs = @($validator, $built)
    if (Test-Path $fastfi) {
        $valArgs = @($validator, "--compare-fastfi", $fastfi, $built)
    }
    & python @valArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Symlink validation FAILED for $built (exit $LASTEXITCODE). Do not flash this image."
    }
} else {
    Write-Warning "validate-firmware-symlinks.py not found - skipping symlink gate"
}

Write-Output $built