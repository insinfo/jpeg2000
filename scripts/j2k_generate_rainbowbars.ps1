Param(
    [string]$OutDir = "C:\\MyDartProjects\\pdfbox_dart\\resources\\j2k_tests\\synthetic\\rainbowbars",
    [string]$Magick = "magick",
    [string]$OpjCompress = "opj_compress",
    [string]$OpjDecompress = "opj_decompress"
)

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

Push-Location $OutDir

# Gera BMP com barras RGB (forçando BMP24/bmp3 para evitar canal alpha)
& $Magick -size 32x32 xc:black `
    -draw "fill red   rectangle 0,0 10,31" `
    -draw "fill green rectangle 11,0 21,31" `
    -draw "fill blue  rectangle 22,0 31,31" `
    bmp3:barras_rgb.bmp

# JP2 lossless
& $OpjCompress -i barras_rgb.bmp -o barras_rgb_lossless.jp2 -I

# JP2 lossy (taxa 8:1 como exemplo)
& $OpjCompress -i barras_rgb.bmp -o barras_rgb_lossy.jp2 -r 8

# Referências decodificadas
& $OpjDecompress -i barras_rgb_lossless.jp2 -o barras_rgb_lossless_reference.ppm
& $OpjDecompress -i barras_rgb_lossy.jp2     -o barras_rgb_lossy_reference.ppm

Pop-Location
