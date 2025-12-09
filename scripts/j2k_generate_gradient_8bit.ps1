Param(
    [string]$OutDir = "C:\\MyDartProjects\\pdfbox_dart\\resources\\j2k_tests\\synthetic\\gradient_8bit",
    [string]$Magick = "magick",
    [string]$OpjCompress = "opj_compress",
    [string]$OpjDecompress = "opj_decompress"
)

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

Push-Location $OutDir

# Gradiente horizontal de 0..255 (força 8 bits reais)
& $Magick -size 64x64 gradient: -colorspace Gray gradient_8bit.pgm
& $Magick gradient_8bit.pgm -depth 8 "pgm:gradient_8bit.pgm"

# JP2 lossless
& $OpjCompress -i gradient_8bit.pgm -o gradient_8bit_lossless.jp2 -I

# JP2 lossy
& $OpjCompress -i gradient_8bit.pgm -o gradient_8bit_lossy.jp2 -r 8

# Referências decodificadas
& $OpjDecompress -i gradient_8bit_lossless.jp2 -o gradient_8bit_lossless_reference.pgm
& $OpjDecompress -i gradient_8bit_lossy.jp2     -o gradient_8bit_lossy_reference.pgm

# Normaliza referências para 8 bits caso a tool emita 16 bits
& $Magick gradient_8bit_lossless_reference.pgm -depth 8 "pgm:gradient_8bit_lossless_reference.pgm"
& $Magick gradient_8bit_lossy_reference.pgm     -depth 8 "pgm:gradient_8bit_lossy_reference.pgm"

Pop-Location
