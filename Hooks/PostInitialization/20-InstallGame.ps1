#Requires -Modules Hooks
#Requires -Modules Logging
#Requires -Modules OverlayFS
#Requires -Modules SteamCMD

# Replaces the SteamCMD image's install hook to add what it doesn't do:
#   - honor STEAM_APP_UPDATE
#   - retry, and check that the server binary is really there
#   - chown Server/ and remount the overlay afterwards. The overlay is mounted before SteamCMD fills
#     Server/, and overlayfs doesn't reliably show lower-dir changes made while it is mounted, so
#     without the remount the first start can't find the server in Merged/.

if ($Env:STEAM_APP_UPDATE -notin @("true", "1")) {
    Write-Log "STEAM_APP_UPDATE is disabled. Skipping game installation."
    return
}

Write-Log "Updating SteamCMD"

Update-SteamCmd

Start-Sleep -Seconds 2

Write-Log "Starting game installation via SteamCMD (app $Env:STEAM_APP_ID)"

Invoke-Hook "PreSteamInstallGame"

New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null

$steamCmdArgs = @(
    "+@ShutdownOnFailedCommand", "1",
    "+@NoPromptForPassword", "1",
    "+@sSteamCmdForcePlatformType", "linux",
    "+force_install_dir", $Env:SERVER_DIR,
    "+login", $Env:STEAM_USERNAME
)

if ($Env:STEAM_USERNAME -ne "anonymous" -and $Env:STEAM_PASSWORD) {
    $steamCmdArgs += $Env:STEAM_PASSWORD
}

$steamCmdArgs += "+app_update", $Env:STEAM_APP_ID

if ($Env:STEAM_BRANCH) {
    $steamCmdArgs += "-beta", $Env:STEAM_BRANCH
    if ($Env:STEAM_BRANCH_PASSWORD) {
        $steamCmdArgs += "-betapassword", $Env:STEAM_BRANCH_PASSWORD
    }
}

$validate = $Env:STEAM_VALIDATE -in @("true", "1")

$attempts = 1
if ($Env:STEAM_INSTALL_ATTEMPTS -match '^\d+$') { $attempts = [Math]::Max(1, [int]$Env:STEAM_INSTALL_ATTEMPTS) }

$serverExe = Join-Path $Env:SERVER_DIR "Binaries/Linux/UDKGameServer-Linux"
$installed = $false

for ($attempt = 1; $attempt -le $attempts; $attempt++) {
    Write-Log "SteamCMD attempt $attempt of $attempts"

    $attemptArgs = $steamCmdArgs
    if ($validate -or $attempt -gt 1) { $attemptArgs += "validate" }

    Invoke-SteamCmd -Arguments ($attemptArgs + "+quit")
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0 -and (Test-Path -Path $serverExe)) {
        Write-Log "SteamCMD install completed"
        $installed = $true
        break
    }

    Write-Log -Level Warning "SteamCMD attempt $attempt failed (exit code $exitCode)"
}

if (-not $installed -and -not (Test-Path -Path $serverExe)) {
    Write-Log -Level Error "Binaries/Linux/UDKGameServer-Linux not found in $Env:SERVER_DIR after $attempts SteamCMD attempt(s)"
}

# Runs before the chown and remount so hooks can add files to Server/
Invoke-Hook "PostSteamInstallGame"

if ((id -u) -eq "0") {
    # SteamCMD ran as root. Chown Server/ directly, never through Merged/: a chown through the overlay
    # copies every file up into Overlay/.
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    mountpoint -q $Env:SERVER_ROOT

    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue

        try {
            Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
            Write-Log "OverlayFS remounted"
        } catch {
            Write-Log -Level Error "Failed to remount OverlayFS: $($_.Exception.Message)"
        }
    }
}

Set-Location $Env:SERVER_ROOT
