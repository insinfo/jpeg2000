# Generate small test images for visual comparison
# Images: 32x32 and 64x64 with colorful patterns

$ErrorActionPreference = "Stop"
$ImageMagickPath = "C:\magick\magick.exe"
$JavaJJ2KEncoder = "jj2000\target\jj2000-5.5-SNAPSHOT.jar"
$JavaJJ2KClass = "ucar.jpeg.jj2000.j2k.JJ2KEncoder"
$OpenJPEGEncoder = "openjpeg\build\bin\Release\opj_compress.exe"
$OpenJPEGDecoder = "openjpeg\build\bin\Release\opj_decompress.exe"

$OutputDir = "test_images\visual_tests"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "=== Generating Small Visual Test Images ===" -ForegroundColor Cyan

# Test configurations
$tests = @(
    @{
        name = "gradient_32"
        size = "32x32"
        command = "gradient:red-blue"
    },
    @{
        name = "gradient_64"
        size = "64x64"
        command = "gradient:yellow-purple"
    },
    @{
        name = "rainbow_32"
        size = "32x32"
        command = "gradient:""rgb(255,0,0)-rgb(255,255,0)-rgb(0,255,0)-rgb(0,255,255)-rgb(0,0,255)-rgb(255,0,255)"""
    },
    @{
        name = "rainbow_64"
        size = "64x64"
        command = "gradient:""rgb(255,0,0)-rgb(255,255,0)-rgb(0,255,0)-rgb(0,255,255)-rgb(0,0,255)-rgb(255,0,255)"""
    },
    @{
        name = "checkerboard_32"
        size = "32x32"
        command = "pattern:checkerboard"
    },
    @{
        name = "checkerboard_64"
        size = "64x64"
        command = "pattern:checkerboard"
    },
    @{
        name = "circles_32"
        size = "32x32"
        command = "xc:white"
        draw = "-fill red -draw ""circle 16,16 16,8"" -fill blue -draw ""circle 16,16 16,12"""
    },
    @{
        name = "circles_64"
        size = "64x64"
        command = "xc:white"
        draw = "-fill red -draw ""circle 32,32 32,16"" -fill green -draw ""circle 32,32 32,24"" -fill blue -draw ""circle 32,32 32,28"""
    },
    @{
        name = "text_32"
        size = "32x32"
        command = "xc:lightblue"
        draw = "-pointsize 20 -fill black -gravity center -annotate +0+0 ""OK"""
    },
    @{
        name = "text_64"
        size = "64x64"
        command = "xc:lightblue"
        draw = "-pointsize 30 -fill darkblue -gravity center -annotate +0+0 ""TEST"""
    },
    @{
        name = "stripes_32"
        size = "32x32"
        command = "xc:white"
        draw = "-fill red -draw ""rectangle 0,0 32,4"" -fill green -draw ""rectangle 0,8 32,12"" -fill blue -draw ""rectangle 0,16 32,20"" -fill yellow -draw ""rectangle 0,24 32,28"""
    },
    @{
        name = "stripes_64"
        size = "64x64"
        command = "xc:white"
        draw = "-fill red -draw ""rectangle 0,0 64,8"" -fill orange -draw ""rectangle 0,12 64,20"" -fill yellow -draw ""rectangle 0,24 64,32"" -fill green -draw ""rectangle 0,36 64,44"" -fill blue -draw ""rectangle 0,48 64,56"""
    }
)

foreach ($test in $tests) {
    $name = $test.name
    $ppmFile = "$OutputDir\${name}.ppm"
    
    Write-Host "`n--- Generating $name ---" -ForegroundColor Yellow
    
    # Generate base image
    $imagickCmd = "& `"$ImageMagickPath`" -size $($test.size) $($test.command)"
    if ($test.draw) {
        $imagickCmd += " $($test.draw)"
    }
    $imagickCmd += " -depth 8 `"$ppmFile`""
    
    Write-Host "Creating image: $ppmFile"
    Invoke-Expression $imagickCmd
    
    if (-not (Test-Path $ppmFile)) {
        Write-Host "Failed to create $ppmFile" -ForegroundColor Red
        continue
    }
    
    # Encode with OpenJPEG
    $jp2File = "$OutputDir\${name}_openjpeg.jp2"
    Write-Host "Encoding with OpenJPEG..."
    $opjEncodeCmd = "& `"$OpenJPEGEncoder`" -i `"$ppmFile`" -o `"$jp2File`" -r 1.0 2>&1"
    $opjEncOutput = Invoke-Expression $opjEncodeCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "OpenJPEG encode failed!" -ForegroundColor Red
    }
    
    # Decode with OpenJPEG
    if (Test-Path $jp2File) {
        $opjDecodedFile = "$OutputDir\${name}_openjpeg_decoded.ppm"
        Write-Host "Decoding with OpenJPEG..."
        $opjDecodeCmd = "& `"$OpenJPEGDecoder`" -i `"$jp2File`" -o `"$opjDecodedFile`" 2>&1"
        $opjDecOutput = Invoke-Expression $opjDecodeCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host "OpenJPEG decode failed!" -ForegroundColor Red
        }
    }
    
    # Decode with Dart
    if (Test-Path $jp2File) {
        $dartDecodedFile = "$OutputDir\${name}_dart_decoded.ppm"
        Write-Host "Decoding with Dart..."
        $dartDecodeCmd = "dart run scripts\decode.dart -i `"$jp2File`" -o `"$dartDecodedFile`" -u off 2>&1"
        $dartOutput = Invoke-Expression $dartDecodeCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Dart decode failed!" -ForegroundColor Red
            Write-Host $dartOutput
        } else {
            Write-Host "Successfully decoded with Dart" -ForegroundColor Green
        }
    }
    
    Write-Host "Completed: $name" -ForegroundColor Green
}

Write-Host "`n=== Converting PPM to PNG for easy viewing ===" -ForegroundColor Cyan

# Convert all PPM files to PNG for easier viewing
Get-ChildItem "$OutputDir\*.ppm" | ForEach-Object {
    $pngFile = $_.FullName -replace '\.ppm$', '.png'
    Write-Host "Converting $($_.Name) to PNG..."
    & "$ImageMagickPath" "$($_.FullName)" "$pngFile" 2>&1 | Out-Null
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Generated test images in: $OutputDir"
Write-Host "`nFor each test image you have:"
Write-Host "  - *_original.png       : Original image"
Write-Host "  - *_java_decoded.png   : Decoded by Java JJ2000"
Write-Host "  - *_dart_decoded.png   : Decoded by Dart"
Write-Host "  - *_openjpeg_decoded.png : Decoded by OpenJPEG"
Write-Host "`nCompare the decoded images visually to verify Dart decoder correctness."

# Generate comparison HTML
$htmlFile = "$OutputDir\comparison.html"
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>JPEG2000 Decoder Visual Comparison</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f0f0f0; }
        h1 { color: #333; }
        .test-group { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .test-name { font-size: 24px; font-weight: bold; margin-bottom: 15px; color: #0066cc; }
        .images { display: flex; gap: 20px; flex-wrap: wrap; }
        .image-box { text-align: center; }
        .image-box img { 
            border: 2px solid #ddd; 
            image-rendering: pixelated;
            width: 256px;
            height: 256px;
        }
        .label { font-weight: bold; margin-top: 10px; }
        .original { border-color: #4CAF50 !important; }
        .java { border-color: #2196F3 !important; }
        .dart { border-color: #FF9800 !important; }
        .openjpeg { border-color: #9C27B0 !important; }
    </style>
</head>
<body>
    <h1>JPEG2000 Decoder Visual Comparison</h1>
    <p>Compare visual quality of different decoders. All decoders should produce nearly identical results.</p>
"@

foreach ($test in $tests) {
    $name = $test.name
    $html += @"
    
    <div class="test-group">
        <div class="test-name">$name ($($test.size))</div>
        <div class="images">
            <div class="image-box">
                <img src="${name}.png" class="original">
                <div class="label" style="color: #4CAF50;">Original</div>
            </div>
            <div class="image-box">
                <img src="${name}_dart_decoded.png" class="dart">
                <div class="label" style="color: #FF9800;">Dart (Our Implementation)</div>
            </div>
            <div class="image-box">
                <img src="${name}_openjpeg_decoded.png" class="openjpeg">
                <div class="label" style="color: #9C27B0;">OpenJPEG</div>
            </div>
        </div>
    </div>
"@
}

$html += @"

</body>
</html>
"@

$html | Out-File -FilePath $htmlFile -Encoding UTF8
Write-Host "`nGenerated comparison HTML: $htmlFile" -ForegroundColor Green
Write-Host "Open this file in your browser to compare all images side-by-side." -ForegroundColor Green
