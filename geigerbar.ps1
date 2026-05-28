# geigerbar.ps1 — a Windows system-tray toggle for claude-geiger (WSL2).
#
# The WSL2 counterpart to the macOS geigerbar.swift. WSLg renders Linux GUI
# apps as individual windows with no Linux notification area, so there is no
# Linux "menu bar" to dock into — the natural equivalent is the *Windows*
# system tray. This puts a radiation glyph there; click it to mute / unmute
# the geiger clicks.
#
# The choice is written to the WSL file ~/.config/claude-geiger/enabled (a
# file containing "1" or "0"), exactly as the Mac app does — geiger.sh reads
# it on every poll, so muting takes effect live, with no Claude Code restart.
# Windows reaches that file over the \\wsl.localhost\<distro>\... 9p share.
#
# The UNC path to the file is read from statefile.txt next to this script;
# traybar.sh (the WSL-side manager) generates both that and the launch.vbs
# that starts this hidden. Left-click toggles; right-click opens the menu.

$ErrorActionPreference = 'Stop'

# --- single instance: a second launch should be a no-op, not a 2nd icon. ---
$script:mutex = New-Object System.Threading.Mutex($false, 'Global\claude-geiger-tray')
if (-not $script:mutex.WaitOne(0)) { return }   # already running

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# GetHicon() leaks the icon handle; DestroyIcon frees the previous one.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GeigerNative {
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);
}
"@

# --- where the live mute file lives (a \\wsl.localhost\... UNC path). -------
$stateRef = Join-Path $PSScriptRoot 'statefile.txt'
if (-not (Test-Path -LiteralPath $stateRef)) {
    [System.Windows.Forms.MessageBox]::Show(
        "statefile.txt is missing next to geigerbar.ps1.`nRe-run ./traybar.sh from your claude-geiger clone.",
        'claude-geiger') | Out-Null
    return
}
$script:target = (Get-Content -LiteralPath $stateRef -Raw).Trim()

# Pull the distro name out of the UNC path so we can tell, cheaply, whether
# WSL is even running — we don't want to boot the whole VM just to read a byte
# at Windows login.
$script:distro = ''
$parts = $script:target -split '\\' | Where-Object { $_ -ne '' }
for ($i = 0; $i -lt $parts.Count - 1; $i++) {
    if ($parts[$i] -eq 'wsl.localhost' -or $parts[$i] -eq 'wsl$') { $script:distro = $parts[$i + 1]; break }
}

function Test-WslRunning {
    if (-not $script:distro) { return $true }
    try {
        $out = (& wsl.exe --list --running) 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        # wsl.exe emits UTF-16; strip embedded NULs before matching.
        return (($out -join "`n") -replace "`0", '') -match [regex]::Escape($script:distro)
    } catch { return $false }
}

function Read-Enabled {
    # Don't touch the share (which would auto-start WSL) unless it's up.
    if (-not (Test-WslRunning)) { return $true }   # default on, matching geiger.sh
    try {
        if (Test-Path -LiteralPath $script:target) {
            return ((Get-Content -LiteralPath $script:target -Raw).Trim() -ne '0')
        }
    } catch {}
    return $true
}

function Write-Enabled([bool]$on) {
    $dir = Split-Path -Parent $script:target
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # No trailing newline / no BOM: geiger.sh compares the bytes to "1"
        # exactly, and a stray CR would read as enabled-but-never-equal-to-1.
        [System.IO.File]::WriteAllText($script:target, $(if ($on) { '1' } else { '0' }),
            (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

# --- draw the tray icon (a radiation trefoil) at runtime, gold when on and
#     dim grey when muted, so it works on both light and dark taskbars. -----
$script:lastHicon = [IntPtr]::Zero
function New-GeigerIcon([bool]$on) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $color = if ($on) { [System.Drawing.Color]::FromArgb(255, 255, 205, 30) }
             else     { [System.Drawing.Color]::FromArgb(130, 150, 150, 150) }
    $brush = New-Object System.Drawing.SolidBrush $color
    # FillPie has no RectangleF overload — use the all-floats one (x,y,w,h,start,sweep).
    foreach ($a in 0, 120, 240) {
        $g.FillPie($brush, [single]2, [single]2, [single]28, [single]28, [single]$a, [single]60)  # three 60° blades
    }
    $g.FillEllipse($brush, [single]12.5, [single]12.5, [single]7, [single]7)                       # central hub
    $brush.Dispose(); $g.Dispose()
    $h = $bmp.GetHicon(); $bmp.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    if ($script:lastHicon -ne [IntPtr]::Zero) { [GeigerNative]::DestroyIcon($script:lastHicon) | Out-Null }
    $script:lastHicon = $h
    return $icon
}

# --- tray icon + menu ------------------------------------------------------
$script:enabled = Read-Enabled

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem('Quit Geiger Tray')

function Update-Ui {
    $notify.Icon = New-GeigerIcon $script:enabled
    $notify.Text = if ($script:enabled) { 'claude-geiger: clicking' } else { 'claude-geiger: muted' }
    $toggleItem.Text = if ($script:enabled) { 'Mute geiger clicks' } else { 'Unmute geiger clicks' }
}

$toggleItem.add_Click({
    $script:enabled = -not $script:enabled
    $ok = Write-Enabled $script:enabled
    Update-Ui
    if (-not $ok) {
        $notify.BalloonTipTitle = 'claude-geiger'
        $notify.BalloonTipText = 'Could not reach the WSL config file — is WSL running?'
        $notify.ShowBalloonTip(3000)
    }
})

$quitItem.add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    if ($script:lastHicon -ne [IntPtr]::Zero) { [GeigerNative]::DestroyIcon($script:lastHicon) | Out-Null }
    [System.Windows.Forms.Application]::Exit()
})

# Left-click is a quick mute toggle; right-click opens the menu.
$notify.add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $toggleItem.PerformClick() }
})

$menu.Items.Add($toggleItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add($quitItem) | Out-Null
$notify.ContextMenuStrip = $menu

Update-Ui
[System.Windows.Forms.Application]::Run()   # pump messages until Quit
