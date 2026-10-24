# REAL input for the app that drive.ps1 launched: keybd_event / mouse_event, which go to
# the FOREGROUND window and through the OS exactly as a person's would (the OS file
# windows, menus that close on focus loss, gestures that need a real pointer).
# Unlike `drive.ps1 act` (PostMessage), this takes the foreground window and the
# cursor: it cannot be used while someone is using the machine.
# Coordinates are the app's client coordinates (what `drive.ps1 shot` shows), physical
# pixels: the process is per-monitor DPI aware, as drive.ps1 is.
#   focus            bring the app to the foreground (ALT trick) and say whether it worked
#   key 40 40 38     press keys (VK codes) one after another
#   chord 17 90      hold the first keys, press the last, release in reverse (Ctrl+Z)
#   hold 40 N        press a key N times quickly (auto-repeat-like)
#   kdown 16 / kup 16                    hold / release keys (a modifier across clicks)
#   mclick X Y / mrclick X Y / mdbl X Y  left click / right click / double click
#   mdrag X1 Y1 X2 Y2                    press, move in 16 steps, release
#   mdown X Y / mmove X Y / mup          the three halves, for a drag that stops to look
#   mhover X Y                           move only (tooltips, submenus)
#   wheel X Y D                          wheel at X,Y, delta D (120 = one notch up)
param([string]$Cmd, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, int data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Of(uint pid) { IntPtr h = IntPtr.Zero; while ((h = FindWindowEx(IntPtr.Zero, h, "FLUTTER_RUNNER_WIN32_WINDOW", null)) != IntPtr.Zero) { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) return h; } return IntPtr.Zero; }
  // Arrows, Home/End/PgUp/PgDn, Insert/Delete are EXTENDED keys: without the flag
  // their scan code is the numpad's, and with NumLock on the app hears Numpad 2.
  public static uint Ext(byte vk) { return (vk >= 0x21 && vk <= 0x2E) || vk == 0x5B || vk == 0x5C ? 1u : 0u; }
  // PowerShell's $null is not C#'s null for a string parameter, so look the view up here.
  public static IntPtr View(IntPtr top) { return FindWindowEx(top, IntPtr.Zero, "FLUTTERVIEW", null); }
  public static void Down(byte vk) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), Ext(vk), UIntPtr.Zero); }
  public static void Up(byte vk) { keybd_event(vk, (byte)MapVirtualKey(vk, 0), 2 | Ext(vk), UIntPtr.Zero); }
}
"@
[K]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
# The same work folder as drive.ps1: the app it launched is named by its pid file there.
$S = if ($env:ANICEL_QA_DIR) { $env:ANICEL_QA_DIR } else { Join-Path $PSScriptRoot "work" }
$h = [K]::Of([uint32][int](Get-Content "$S\app.pid"))
function ScreenAt([string]$x, [string]$y) {
  $p = New-Object K+POINT; $p.X = [int]$x; $p.Y = [int]$y
  [K]::ClientToScreen([K]::View($h), [ref]$p) | Out-Null
  [K]::SetCursorPos($p.X, $p.Y) | Out-Null
  $p
}
function Press([uint32]$down, [uint32]$up) {
  [K]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
  [K]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
}
switch ($Cmd) {
  'focus' {
    # An ALT press lets a background process call SetForegroundWindow.
    [K]::Down(0x12); [K]::Up(0x12); [K]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300
    $fg = [K]::GetForegroundWindow(); "foreground=$($fg -eq $h) (fg=$fg app=$h)"
  }
  'key' { foreach ($vk in $Rest) { [K]::Down([byte][int]$vk); Start-Sleep -Milliseconds 30; [K]::Up([byte][int]$vk); Start-Sleep -Milliseconds 60 }; 'ok' }
  'hold' { $n = [int]$Rest[1]; for ($i = 0; $i -lt $n; $i++) { [K]::Down([byte][int]$Rest[0]); Start-Sleep -Milliseconds 20; [K]::Up([byte][int]$Rest[0]); Start-Sleep -Milliseconds 40 }; 'ok' }
  'chord' { $a = @($Rest | ForEach-Object { [byte][int]$_ }); foreach ($vk in $a) { [K]::Down($vk); Start-Sleep -Milliseconds 30 }; [array]::Reverse($a); foreach ($vk in $a) { [K]::Up($vk); Start-Sleep -Milliseconds 30 }; 'ok' }
  'kdown' { foreach ($vk in $Rest) { [K]::Down([byte][int]$vk); Start-Sleep -Milliseconds 30 }; 'ok' }
  'kup' { foreach ($vk in $Rest) { [K]::Up([byte][int]$vk); Start-Sleep -Milliseconds 30 }; 'ok' }
  'mclick' { ScreenAt $Rest[0] $Rest[1] | Out-Null; Start-Sleep -Milliseconds 60; Press 0x2 0x4; 'ok' }
  'mrclick' { ScreenAt $Rest[0] $Rest[1] | Out-Null; Start-Sleep -Milliseconds 60; Press 0x8 0x10; 'ok' }
  'mdbl' { ScreenAt $Rest[0] $Rest[1] | Out-Null; Start-Sleep -Milliseconds 60; Press 0x2 0x4; Start-Sleep -Milliseconds 120; Press 0x2 0x4; 'ok' }
  'mhover' { ScreenAt $Rest[0] $Rest[1] | Out-Null; 'ok' }
  'mmove' { ScreenAt $Rest[0] $Rest[1] | Out-Null; 'ok' }
  'mdown' { ScreenAt $Rest[0] $Rest[1] | Out-Null; Start-Sleep -Milliseconds 60; [K]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); 'ok' }
  'mup' { [K]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero); 'ok' }
  'mdrag' {
    $a = ScreenAt $Rest[0] $Rest[1]; Start-Sleep -Milliseconds 80
    $b = New-Object K+POINT; $b.X = [int]$Rest[2]; $b.Y = [int]$Rest[3]; [K]::ClientToScreen([K]::View($h), [ref]$b) | Out-Null
    [K]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120
    $n = 16; for ($i = 1; $i -le $n; $i++) { [K]::SetCursorPos([int]($a.X + ($b.X - $a.X) * $i / $n), [int]($a.Y + ($b.Y - $a.Y) * $i / $n)) | Out-Null; Start-Sleep -Milliseconds 25 }
    Start-Sleep -Milliseconds 120; [K]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero); 'ok'
  }
  'wheel' { ScreenAt $Rest[0] $Rest[1] | Out-Null; Start-Sleep -Milliseconds 50; [K]::mouse_event(0x800, 0, 0, [int]$Rest[2], [UIntPtr]::Zero); 'ok' }
  default { "unknown command '$Cmd'" }
}
