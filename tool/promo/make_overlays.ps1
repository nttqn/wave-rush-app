Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'gfx'
New-Item -ItemType Directory -Force $out | Out-Null
$icon = [System.Drawing.Image]::FromFile('C:\Users\Hi\.gemini\antigravity\scratch\wave-rush-app\assets\icon\icon.png')
$cyan = [System.Drawing.Color]::FromArgb(255, 63, 224, 255)
$family = New-Object System.Drawing.FontFamily 'Segoe UI Black'
$famReg = New-Object System.Drawing.FontFamily 'Segoe UI'

function New-Canvas($w, $h) {
  $b = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'AntiAliasGridFit'
  return @($b, $g)
}

# Glowing text: wide translucent strokes of the glow colour, then a white fill.
function Draw-Glow($g, $text, $fam, $style, $size, $rect, $glow, $fill) {
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddString($text, $fam, [int]$style, $size, $rect, $fmt)
  foreach ($w in @(34, 22, 12)) {
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(45, $glow.R, $glow.G, $glow.B)), $w
    $pen.LineJoin = 'Round'
    $g.DrawPath($pen, $path)
  }
  $edge = New-Object System.Drawing.Pen $glow, 4
  $edge.LineJoin = 'Round'
  $g.DrawPath($edge, $path)
  $g.FillPath((New-Object System.Drawing.SolidBrush $fill), $path)
}

function Draw-Background($g, $w, $h) {
  $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
  $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 5, 10, 31))), $rect)
  $ell = New-Object System.Drawing.Drawing2D.GraphicsPath
  $ell.AddEllipse([int](-$w * 0.3), [int](-$h * 0.45), [int]($w * 1.6), [int]($h * 1.1))
  $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $ell
  $pgb.CenterColor = [System.Drawing.Color]::FromArgb(255, 14, 42, 107)
  $pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 5, 10, 31))
  $g.FillRectangle($pgb, $rect)
  $grid = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(22, 63, 169, 255)), 2
  $step = [int]($h / 9)
  for ($x = 0; $x -le $w; $x += $step) { $g.DrawLine($grid, $x, 0, $x, $h) }
  for ($y = 0; $y -le $h; $y += $step) { $g.DrawLine($grid, 0, $y, $w, $y) }
}

function Draw-Icon($g, $cx, $cy, $size) {
  foreach ($r in @(60, 40, 22)) {
    $glowB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(18, 63, 224, 255))
    $g.FillEllipse($glowB, [int]($cx - $size / 2 - $r), [int]($cy - $size / 2 - $r), [int]($size + 2 * $r), [int]($size + 2 * $r))
  }
  $g.DrawImage($icon, [int]($cx - $size / 2), [int]($cy - $size / 2), [int]$size, [int]$size)
}

function Draw-Pill($g, $rect, $color, $filled) {
  $r = $rect.Height / 2
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddArc($rect.X, $rect.Y, $rect.Height, $rect.Height, 90, 180)
  $p.AddArc($rect.Right - $rect.Height, $rect.Y, $rect.Height, $rect.Height, 270, 180)
  $p.CloseFigure()
  if ($filled) { $g.FillPath((New-Object System.Drawing.SolidBrush $color), $p) }
  else {
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 5, 10, 31))), $p)
    $g.DrawPath((New-Object System.Drawing.Pen $color, 5), $p)
  }
}

function Save($b, $g, $name) { $g.Dispose(); $b.Save((Join-Path $out $name), [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose() }

$bi = [System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic

# ---------------------------------------------------------------- landscape
foreach ($kind in 'intro', 'outro') {
  $b, $g = New-Canvas 1920 1080
  Draw-Background $g 1920 1080
  $iconY = if ($kind -eq 'intro') { 380 } else { 330 }
  Draw-Icon $g 960 $iconY 330
  Draw-Glow $g 'WAVE RUSH' $family $bi 150 (New-Object System.Drawing.RectangleF 0, ($iconY + 170), 1920, 190) $cyan ([System.Drawing.Color]::White)
  if ($kind -eq 'intro') {
    Draw-Glow $g ("HOLD TO RISE  " + [char]0xB7 + "  RELEASE TO FALL") $famReg ([System.Drawing.FontStyle]::Bold) 52 (New-Object System.Drawing.RectangleF 0, 910, 1920, 80) ([System.Drawing.Color]::FromArgb(255, 30, 60, 120)) ([System.Drawing.Color]::FromArgb(255, 200, 225, 255))
  } else {
    $pill = New-Object System.Drawing.Rectangle 610, 830, 700, 130
    Draw-Pill $g $pill $cyan $true
    $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $g.DrawString('PLAY FREE NOW', (New-Object System.Drawing.Font $family, 64, $bi, 'Pixel'), (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 5, 10, 31))), (New-Object System.Drawing.RectangleF $pill.X, $pill.Y, $pill.Width, $pill.Height), $fmt)
    Draw-Glow $g ("Android  " + [char]0xB7 + "  iOS") $famReg ([System.Drawing.FontStyle]::Bold) 44 (New-Object System.Drawing.RectangleF 0, 985, 1920, 70) ([System.Drawing.Color]::FromArgb(255, 30, 60, 120)) ([System.Drawing.Color]::FromArgb(255, 200, 225, 255))
  }
  Save $b $g "$kind.png"
}

$captions = @(
  'ONE TOUCH TO PLAY',
  'DODGE SPIKES & SAWS',
  'SPEED & MINI PORTALS',
  '12 LEVELS: EASY TO INSANE',
  'BUILD & SHARE YOUR LEVELS',
  'ENDLESS MODE & SKINS'
)
for ($i = 0; $i -lt $captions.Count; $i++) {
  $b, $g = New-Canvas 1920 1080
  $text = $captions[$i]
  $font = New-Object System.Drawing.Font $family, 80, $bi, 'Pixel'
  $tw = $g.MeasureString($text, $font).Width
  $pill = New-Object System.Drawing.Rectangle ([int](960 - $tw / 2 - 70)), 880, ([int]($tw + 140)), 140
  Draw-Pill $g $pill $cyan $false
  Draw-Glow $g $text $family $bi 80 (New-Object System.Drawing.RectangleF 0, 880, 1920, 140) $cyan ([System.Drawing.Color]::White)
  Save $b $g ("cap{0}.png" -f ($i + 1))
}

# ----------------------------------------------------------------- vertical
foreach ($kind in 'intro', 'outro') {
  $b, $g = New-Canvas 1080 1920
  Draw-Background $g 1080 1920
  Draw-Icon $g 540 700 460
  Draw-Glow $g 'WAVE RUSH' $family $bi 150 (New-Object System.Drawing.RectangleF 0, 960, 1080, 200) $cyan ([System.Drawing.Color]::White)
  if ($kind -eq 'intro') {
    Draw-Glow $g "HOLD TO RISE`nRELEASE TO FALL" $famReg ([System.Drawing.FontStyle]::Bold) 64 (New-Object System.Drawing.RectangleF 0, 1200, 1080, 220) ([System.Drawing.Color]::FromArgb(255, 30, 60, 120)) ([System.Drawing.Color]::FromArgb(255, 200, 225, 255))
  } else {
    $pill = New-Object System.Drawing.Rectangle 170, 1250, 740, 150
    Draw-Pill $g $pill $cyan $true
    $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $g.DrawString('PLAY FREE NOW', (New-Object System.Drawing.Font $family, 72, $bi, 'Pixel'), (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 5, 10, 31))), (New-Object System.Drawing.RectangleF $pill.X, $pill.Y, $pill.Width, $pill.Height), $fmt)
    Draw-Glow $g ("Android  " + [char]0xB7 + "  iOS") $famReg ([System.Drawing.FontStyle]::Bold) 56 (New-Object System.Drawing.RectangleF 0, 1440, 1080, 90) ([System.Drawing.Color]::FromArgb(255, 30, 60, 120)) ([System.Drawing.Color]::FromArgb(255, 200, 225, 255))
  }
  Save $b $g "v_$kind.png"
}

# Vertical frame around gameplay: background with the caption on top and a
# small logo strip at the bottom; the 1080x1080 gameplay square goes in the
# middle (y 420..1500).
$vcaps = @(
  "ONE TOUCH`nTO PLAY",
  "DODGE SPIKES`n& SAWS",
  "SPEED & MINI`nPORTALS",
  "12 LEVELS`nEASY TO INSANE",
  "BUILD & SHARE`nYOUR LEVELS",
  "ENDLESS MODE`n& SKINS"
)
for ($i = 0; $i -lt $vcaps.Count; $i++) {
  $b, $g = New-Canvas 1080 1920
  Draw-Background $g 1080 1920
  $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Black)), 0, 420, 1080, 1080)
  $g.DrawRectangle((New-Object System.Drawing.Pen $cyan, 6), 0, 420, 1079, 1080)
  Draw-Glow $g $vcaps[$i] $family $bi 104 (New-Object System.Drawing.RectangleF 0, 70, 1080, 320) $cyan ([System.Drawing.Color]::White)
  Draw-Icon $g 300 1705 150
  Draw-Glow $g 'WAVE RUSH' $family $bi 86 (New-Object System.Drawing.RectangleF 380, 1640, 680, 130) $cyan ([System.Drawing.Color]::White)
  Save $b $g ("v_frame{0}.png" -f ($i + 1))
}
$icon.Dispose()
Get-ChildItem $out | Select-Object Name, Length
