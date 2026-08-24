param(
    [string]$Source = (Join-Path $PSScriptRoot "..\DesignReferences\activity-icon-reference.png"),
    [string]$AssetCatalog = (Join-Path $PSScriptRoot "..\IOS Frontend\IOS Frontend\Assets.xcassets")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing.Common

# Crops are taken from the user-approved sports pictogram sheet. The same
# source glyph can intentionally serve two semantic roles (for example the
# cycling mark for both a ride and bike gear) while retaining separate asset
# names so either role can evolve without changing call sites.
$icons = @(
    @{ Name = "ActivityLifting";       X = 155; Y = 106; W = 46; H = 46 },
    @{ Name = "ActivityRunning";       X = 397; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivityBiking";        X = 155; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivitySwimming";      X = 204; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivityTreadmill";     X = 397; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivityStationaryBike";X = 106; Y = 55;  W = 46; H = 46 },
    @{ Name = "ActivityStairMaster";   X = 106; Y = 157; W = 46; H = 46 },
    @{ Name = "ActivityElliptical";    X = 253; Y = 157; W = 46; H = 46 },
    @{ Name = "ActivityRower";         X = 348; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivityAssaultBike";   X = 106; Y = 106; W = 46; H = 46 },
    @{ Name = "ActivitySkiErg";        X = 106; Y = 157; W = 46; H = 46 },
    @{ Name = "ActivityOtherCardio";   X = 106; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivityCardio";        X = 106; Y = 3;   W = 46; H = 46 },
    @{ Name = "ActivityBikeGear";      X = 155; Y = 3;   W = 46; H = 46 }
)

function New-TemplateIcon {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [hashtable]$Spec,
        [string]$OutputPath
    )

    $size = 256
    $padding = 24
    $output = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $output.SetResolution(144, 144)
        $sourceRect = [System.Drawing.Rectangle]::new($Spec.X, $Spec.Y, $Spec.W, $Spec.H)
        $crop = $Bitmap.Clone($sourceRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            # Convert the dark-on-white reference into a tintable alpha mask.
            for ($x = 0; $x -lt $crop.Width; $x++) {
                for ($y = 0; $y -lt $crop.Height; $y++) {
                    $pixel = $crop.GetPixel($x, $y)
                    $luma = [int](0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B)
                    $alpha = [Math]::Max(0, [Math]::Min(255, (245 - $luma) * 3))
                    $crop.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
                }
            }

            $graphics = [System.Drawing.Graphics]::FromImage($output)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

                $available = $size - (2 * $padding)
                $scale = [Math]::Min($available / $crop.Width, $available / $crop.Height)
                $width = [int]($crop.Width * $scale)
                $height = [int]($crop.Height * $scale)
                $left = [int](($size - $width) / 2)
                $top = [int](($size - $height) / 2)
                $destination = [System.Drawing.Rectangle]::new($left, $top, $width, $height)
                $graphics.DrawImage($crop, $destination)
            } finally {
                $graphics.Dispose()
            }
        } finally {
            $crop.Dispose()
        }

        $output.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $output.Dispose()
    }
}

$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
$sourceBitmap = [System.Drawing.Bitmap]::new($resolvedSource)
try {
    foreach ($icon in $icons) {
        $imageset = Join-Path $AssetCatalog "$($icon.Name).imageset"
        New-Item -ItemType Directory -Force -Path $imageset | Out-Null
        $filename = "$($icon.Name).png"
        New-TemplateIcon -Bitmap $sourceBitmap -Spec $icon -OutputPath (Join-Path $imageset $filename)

        $contents = @{
            images = @(
                @{ filename = $filename; idiom = "universal"; scale = "1x" },
                @{ idiom = "universal"; scale = "2x" },
                @{ idiom = "universal"; scale = "3x" }
            )
            info = @{ author = "xcode"; version = 1 }
            properties = @{ "template-rendering-intent" = "template" }
        } | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath (Join-Path $imageset "Contents.json") -Value $contents -Encoding utf8
    }
} finally {
    $sourceBitmap.Dispose()
}

Write-Output "Generated $($icons.Count) activity icon assets from $Source"
