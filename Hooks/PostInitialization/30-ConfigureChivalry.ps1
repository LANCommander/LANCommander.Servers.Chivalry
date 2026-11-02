#Requires -Modules Logging

# Write the CMW_* settings into UDKGame/Config/PCServer-UDKGame.ini before the server starts.
#
# The Linux server reads its config from ~/.local/share/TornBanner/Chivalry, which cmw-server links
# to the merged server directory, so this is the ini the server really uses. Writing it through
# Merged/ puts the edited copy in Overlay/, where it persists and can be edited by hand. Only keys
# with a CMW_* setting are touched; the server itself rewrites the file while it runs.

$ini = Join-Path $Env:SERVER_ROOT 'UDKGame/Config/PCServer-UDKGame.ini'

if (-not (Test-Path -Path $ini)) {
    Write-Log -Level Error "$ini not found; skipping server configuration"
    return
}

$text    = [System.IO.File]::ReadAllText($ini)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split "\r?\n"))

function Get-SectionRange([string] $Section) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }

    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
    return @($start, $end)
}

function Add-Section([string] $Section) {
    if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
    $lines.Add("[$Section]")
    return @(($lines.Count - 1), $lines.Count)
}

# Index after the section's last non-blank line, where new keys go
function Get-InsertIndex([int] $Start, [int] $End) {
    $at = $End
    while ($at -gt $Start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
    return $at
}

# Set Key=Value in [Section], replacing the first existing Key= line or appending to the section
function Set-IniValue([string] $Section, [string] $Key, [string] $Value) {
    $range = Get-SectionRange $Section
    if (-not $range) { $range = Add-Section $Section }

    $start, $end = $range
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lines[$i] = "$Key=$Value"
            return
        }
    }

    $lines.Insert((Get-InsertIndex $start $end), "$Key=$Value")
}

# Replace every Key= line in [Section] with one line per value (for array keys such as Maplist)
function Set-IniList([string] $Section, [string] $Key, [string[]] $Values) {
    $range = Get-SectionRange $Section
    if (-not $range) { $range = Add-Section $Section }

    $start, $end = $range
    $at = -1
    for ($i = $end - 1; $i -gt $start; $i--) {
        if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lines.RemoveAt($i)
            $end--
            $at = $i
        }
    }
    if ($at -lt 0) { $at = Get-InsertIndex $start $end }

    for ($i = 0; $i -lt $Values.Count; $i++) {
        $lines.Insert($at + $i, "$Key=$($Values[$i])")
    }
}

$settings = @(
    @('Engine.GameReplicationInfo', 'ServerName',       $Env:CMW_SERVER_NAME),
    @('Engine.GameReplicationInfo', 'MessageOfTheDay',  $Env:CMW_MOTD),
    @('Engine.GameInfo',            'MaxPlayers',       $Env:CMW_MAX_PLAYERS)
)

foreach ($s in $settings) {
    if ($s[2]) { Set-IniValue $s[0] $s[1] $s[2] }
}

# Passwords are always written, so clearing the variable removes the password
Set-IniValue 'Engine.AccessControl' 'GamePassword'  "$Env:CMW_GAME_PASSWORD"
Set-IniValue 'Engine.AccessControl' 'AdminPassword' "$Env:CMW_ADMIN_PASSWORD"

# Map rotation
if ($Env:CMW_MAPS) {
    $maps = @($Env:CMW_MAPS -split '[,;\s]+' | Where-Object { $_ })

    # A map that doesn't exist in the rotation stops the server when the rotation reaches it
    $cooked = Join-Path $Env:SERVER_ROOT 'UDKGame/CookedPCServer'
    $available = @{}
    Get-ChildItem -Path $cooked -Filter '*.udk' -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { $available[$_.BaseName.ToLowerInvariant()] = $true }

    if ($available.Count) {
        $missing = @($maps | Where-Object { -not $available.ContainsKey($_.ToLowerInvariant()) })
        if ($missing) {
            Write-Log -Level Warning "Removed map(s) not found in UDKGame/CookedPCServer from CMW_MAPS: $($missing -join ', ')"
            $maps = @($maps | Where-Object { $available.ContainsKey($_.ToLowerInvariant()) })
        }
    }

    if ($maps.Count) {
        Set-IniList 'AOC.AOCGame' 'Maplist' $maps
        Set-IniValue 'AOC.AOCGame' 'MapListIndex' '0'
        Write-Log "Map rotation: $($maps -join ', ')"
    } else {
        Write-Log -Level Warning "CMW_MAPS has no valid maps; keeping the existing rotation"
    }
}

[System.IO.File]::WriteAllText($ini, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $ini

Write-Log "Applied CMW_* settings to $ini"

# The server's Steam game server interface only starts (and opens the query port) when
# steam_appid.txt next to the binary names the game's app id. The dedicated server depot doesn't
# ship one.
$appIdFile = Join-Path $Env:SERVER_ROOT 'Binaries/Linux/steam_appid.txt'
$appId     = if ($Env:CMW_STEAM_APPID) { $Env:CMW_STEAM_APPID } else { '219640' }
$current   = if (Test-Path -Path $appIdFile) { (Get-Content -Path $appIdFile -Raw).Trim() } else { '' }

if ($current -ne $appId) {
    Set-Content -Path $appIdFile -Value $appId -NoNewline
    chown "$($Env:UID):$($Env:GID)" $appIdFile
    Write-Log "Wrote steam_appid.txt ($appId)"
}
