# QA driver that never takes focus: input goes to the app's view window by
# PostMessage, the picture comes from PrintWindow. Coordinates are client
# coordinates of the app window (what `shot` shows).
# launch | act <steps...> | shot <file> [x0 y0 x1 y1] | close | kill
# Steps (slash-separated): click:X/Y rclick:X/Y dbl:X/Y drag:X1/Y1/X2/Y2 move:X/Y
#   key:VK/VK.. (modifiers first: 16 shift 17 ctrl 18 alt) type:text wait:ms wheel:X/Y/delta
param([string]$Cmd, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args2)
# Work folder (pid file, sandbox APPDATA, shots): $env:ANICEL_QA_DIR, else a folder beside this script.
$S = if ($env:ANICEL_QA_DIR) { $env:ANICEL_QA_DIR } else { Join-Path $PSScriptRoot "work" }
New-Item -ItemType Directory -Force $S | Out-Null
# The app to drive: $env:ANICEL_QA_EXE (a release build from a lane, never the installed one).
$exe = $env:ANICEL_QA_EXE
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static IntPtr Of(uint pid) { IntPtr h = IntPtr.Zero; while ((h = FindWindowEx(IntPtr.Zero, h, "FLUTTER_RUNNER_WIN32_WINDOW", null)) != IntPtr.Zero) { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) return h; } return IntPtr.Zero; }
  public static IntPtr View(IntPtr top) { return FindWindowEx(top, IntPtr.Zero, "FLUTTERVIEW", null); }
  public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
  public static IntPtr KeyLP(uint vk, bool up) { uint sc = MapVirtualKey(vk, 0); long l = 1 | (sc << 16); if (up) l |= 0xC0000000; return (IntPtr)l; }
}
"@
$pidFile = "$S\app.pid"
function Top { $p = Get-Process -Id (Get-Content $pidFile) -ErrorAction Stop; [W]::Of([uint32]$p.Id) }
function Post($h, $m, $w, $l) { [W]::PostMessage($h, [uint32]$m, [IntPtr]$w, $l) | Out-Null }
function MMove($v, $x, $y, $btn) { Post $v 0x200 $btn ([W]::LP([int]$x, [int]$y)); Start-Sleep -Milliseconds 30 }
function Down($v, $x, $y) { Post $v 0x201 1 ([W]::LP([int]$x, [int]$y)) }
function Up($v, $x, $y) { Post $v 0x202 0 ([W]::LP([int]$x, [int]$y)) }
function Key($v, $vk, $up) { if ($up) { Post $v 0x101 ([int]$vk) ([W]::KeyLP([uint32]$vk, $true)) } else { Post $v 0x100 ([int]$vk) ([W]::KeyLP([uint32]$vk, $false)) } }
switch ($Cmd) {
  'launch' {
    $env:APPDATA = "$S\appdata"; New-Item -ItemType Directory -Force "$S\appdata" | Out-Null
    $p = Start-Process -FilePath $exe -PassThru; Set-Content $pidFile $p.Id
    $h = [IntPtr]::Zero
    for ($i = 0; $i -lt 160 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = [W]::Of([uint32]$p.Id) }
    Start-Sleep -Seconds 4
    # SWP_NOACTIVATE | SWP_NOZORDER
    [W]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, 1600, 1000, 0x14) | Out-Null
    Start-Sleep -Seconds 1
    "launched pid=$($p.Id) hwnd=$h view=$([W]::View($h))"
  }
  'act' {
    $v = [W]::View((Top))
    foreach ($s in $Args2) {
      $k, $val = $s.Split(':', 2); $a = @(); if ($val) { $a = $val.Split("/") }
      switch ($k) {
        'move'  { MMove $v $a[0] $a[1] 0 }
        'click' { MMove $v $a[0] $a[1] 0; Down $v $a[0] $a[1]; Start-Sleep -Milliseconds 60; Up $v $a[0] $a[1] }
        'rclick'{ MMove $v $a[0] $a[1] 0; Post $v 0x204 2 ([W]::LP([int]$a[0], [int]$a[1])); Start-Sleep -Milliseconds 60; Post $v 0x205 0 ([W]::LP([int]$a[0], [int]$a[1])) }
        'dbl'   { MMove $v $a[0] $a[1] 0; Down $v $a[0] $a[1]; Up $v $a[0] $a[1]; Start-Sleep -Milliseconds 80; Post $v 0x203 1 ([W]::LP([int]$a[0], [int]$a[1])); Up $v $a[0] $a[1] }
        'drag'  { MMove $v $a[0] $a[1] 0; Down $v $a[0] $a[1]; Start-Sleep -Milliseconds 150
                  $n = 12; for ($i = 1; $i -le $n; $i++) { $x = [int]($a[0] + ([int]$a[2] - [int]$a[0]) * $i / $n); $y = [int]($a[1] + ([int]$a[3] - [int]$a[1]) * $i / $n); MMove $v $x $y 1; Start-Sleep -Milliseconds 25 }
                  Start-Sleep -Milliseconds 150; Up $v $a[2] $a[3] }
        'wheel' { $pt = New-Object W+POINT; $pt.X = [int]$a[0]; $pt.Y = [int]$a[1]; [W]::ClientToScreen($v, [ref]$pt) | Out-Null
                  Post $v 0x20A ([int]$a[2] -shl 16) ([W]::LP($pt.X, $pt.Y)) }
        'key'   { foreach ($vk in $a) { Key $v ([int]$vk) $false }; Start-Sleep -Milliseconds 50; [array]::Reverse($a); foreach ($vk in $a) { Key $v ([int]$vk) $true } }
        'type'  { foreach ($ch in $val.ToCharArray()) { $vk = [int][char]::ToUpper($ch); Key $v $vk $false; Key $v $vk $true; Start-Sleep -Milliseconds 30 } }
        'typeu' { foreach ($hx in $a) { $cp = [int]("0x" + $hx); Post $v 0x102 $cp ([W]::KeyLP(0xE5, $false)); Start-Sleep -Milliseconds 30 } }
        'wheelt' { $t = Top; $pt = New-Object W+POINT; $pt.X = [int]$a[0]; $pt.Y = [int]$a[1]; [W]::ClientToScreen($v, [ref]$pt) | Out-Null; Post $t 0x20A ([int]$a[2] -shl 16) ([W]::LP($pt.X, $pt.Y)) }
        'wait'  { Start-Sleep -Milliseconds ([int]$val) }
      }
      Start-Sleep -Milliseconds 120
    }
    "ok"
  }
  'shot' {
    $h = Top; Start-Sleep -Milliseconds 300
    $r = New-Object W+RECT; [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    $full = New-Object System.Drawing.Bitmap $w, $ht
    $g = [System.Drawing.Graphics]::FromImage($full); $dc = $g.GetHdc()
    [W]::PrintWindow($h, $dc, 2) | Out-Null   # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($dc); $g.Dispose()
    # client origin inside the window picture
    $pt = New-Object W+POINT; [W]::ClientToScreen($h, [ref]$pt) | Out-Null
    $cx = $pt.X - $r.L; $cy = $pt.Y - $r.T
    $cr = New-Object W+RECT; [W]::GetClientRect($h, [ref]$cr) | Out-Null
    $x0 = 0; $y0 = 0; $x1 = $cr.R; $y1 = $cr.B
    if ($Args2.Count -ge 5) { $x0 = [int]$Args2[1]; $y0 = [int]$Args2[2]; $x1 = [int]$Args2[3]; $y1 = [int]$Args2[4] }
    $sc = 1.0; if ($Args2.Count -ge 6) { $sc = [double]$Args2[5] }; $ow = [int](($x1 - $x0) * $sc); $oh = [int](($y1 - $y0) * $sc)
    $out = New-Object System.Drawing.Bitmap $ow, $oh; $go = [System.Drawing.Graphics]::FromImage($out); $go.DrawImage($full, (New-Object System.Drawing.Rectangle 0, 0, $ow, $oh), (New-Object System.Drawing.Rectangle ($cx + $x0), ($cy + $y0), ($x1 - $x0), ($y1 - $y0)), [System.Drawing.GraphicsUnit]::Pixel); $go.Dispose()
    $out.Save("$S\$($Args2[0])", [System.Drawing.Imaging.ImageFormat]::Png); $out.Dispose(); $full.Dispose()
    "saved $($Args2[0]) ($($x1-$x0)x$($y1-$y0)) client=$($cr.R)x$($cr.B)"
  }
  'close' {
    $h = Top; [W]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    $p = Get-Process -Id (Get-Content $pidFile) -ErrorAction SilentlyContinue
    if ($p -and -not $p.WaitForExit(8000)) { "still open (dialog?)" } else { "closed" }
  }
  'size' { $h = Top; [W]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, [int]$Args2[0], [int]$Args2[1], 0x14) | Out-Null; 'sized' }
  # Keys and the wheel do not reach an unfocused window (measured 10-22); on a machine
  # nobody is using, `focus` first, then send them.
  'focus' { [W]::SetForegroundWindow((Top)) | Out-Null; 'focused' }
  'kill' { Stop-Process -Id (Get-Content $pidFile) -Force -ErrorAction SilentlyContinue; "killed" }
}


