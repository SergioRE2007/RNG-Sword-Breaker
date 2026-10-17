# Pone los rótulos de las miniaturas: lee <escena>.json (lo deja crear_miniaturas.py) y pinta cada texto sobre
# <escena>_base.png con letra gorda, degradado, borde negro y sombra. Deja <escena>.png (1920 x 1080).
#   powershell -File tools\blender\rotular_miniaturas.ps1 [escena...]
param([string[]] $Scenes)

Add-Type -AssemblyName System.Drawing
$dir = Join-Path $env:USERPROFILE "Documents\Roblox\miniaturas"
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$file = Join-Path $dir "fuentes\LuckiestGuy.ttf"
if (Test-Path $file) { $fonts.AddFontFile($file); $family = $fonts.Families[0] }
else { $family = New-Object System.Drawing.FontFamily "Impact" }
if (-not $Scenes) { $Scenes = Get-ChildItem $dir -Filter *.json | ForEach-Object { $_.BaseName } }

foreach ($scene in $Scenes) {
    $source = [System.Drawing.Image]::FromFile((Join-Path $dir "$scene`_base.png"))
    $bitmap = New-Object System.Drawing.Bitmap $source
    $source.Dispose()
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = "AntiAlias"
    $labels = Get-Content (Join-Path $dir "$scene.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($l in $labels) {
        $size = [single] $l.size
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $format = New-Object System.Drawing.StringFormat
        $path.AddString([string] $l.text, $family, 0, $size, (New-Object System.Drawing.PointF 0, 0), $format)
        $box = $path.GetBounds()
        # Que no se salga de la imagen: el centro se mete hacia dentro lo que haga falta.
        $half = $box.Width / 2 + $size * 0.2
        $x = [Math]::Min([Math]::Max([single] $l.x, $half), $bitmap.Width - $half)
        $y = [Math]::Min([Math]::Max([single] $l.y, $size * 0.7), $bitmap.Height - $size * 0.7)
        $m = New-Object System.Drawing.Drawing2D.Matrix
        $m.Translate($x, $y)
        $m.Rotate([single] $l.angle)
        $m.Shear(-0.12, 0)
        $m.Translate(-($box.X + $box.Width / 2), -($box.Y + $box.Height / 2))
        $path.Transform($m)
        $bounds = $path.GetBounds()

        $shadow = $path.Clone()
        $down = New-Object System.Drawing.Drawing2D.Matrix
        $down.Translate($size * 0.05, $size * 0.11)
        $shadow.Transform($down)
        $black = [System.Drawing.ColorTranslator]::FromHtml($l.outline)
        $pen = New-Object System.Drawing.Pen $black, ($size * 0.26)
        $pen.LineJoin = "Round"
        $g.DrawPath($pen, $shadow)
        $g.FillPath((New-Object System.Drawing.SolidBrush $black), $shadow)
        $g.DrawPath($pen, $path)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds,
            ([System.Drawing.ColorTranslator]::FromHtml($l.top)), ([System.Drawing.ColorTranslator]::FromHtml($l.bottom)), 90
        if ($l.rainbow) {
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds, ([System.Drawing.Color]::Red), ([System.Drawing.Color]::Violet), 0
            $blend = New-Object System.Drawing.Drawing2D.ColorBlend 6
            $blend.Colors = @("#FF3B30", "#FF9F1C", "#FFE83B", "#4CE04A", "#35B8FF", "#C86BFF") | ForEach-Object { [System.Drawing.ColorTranslator]::FromHtml($_) }
            $blend.Positions = [single[]] @(0, 0.2, 0.4, 0.6, 0.8, 1)
            $brush.InterpolationColors = $blend
        }
        $g.FillPath($brush, $path)
        # Brillo: la mitad de arriba un poco más clara.
        $clip = $g.Clip
        $g.SetClip($path)
        $shine = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 255, 255, 255))
        $g.FillEllipse($shine, $bounds.X - $bounds.Width * 0.1, $bounds.Y - $bounds.Height * 0.75, $bounds.Width * 1.2, $bounds.Height * 1.2)
        $g.Clip = $clip
    }
    $g.Dispose()
    $bitmap.Save((Join-Path $dir "$scene.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    "Rotulada $scene"
}
