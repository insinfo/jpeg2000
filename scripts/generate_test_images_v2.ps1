# Script para gerar e testar imagens JPEG2000
# Usa ImageMagick, Java JJ2000 e OpenJPEG

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Gerador de Imagens de Teste JPEG2000" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar ImageMagick
$magick = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magick) {
    Write-Host "[ERRO] ImageMagick nao encontrado. Instale de https://imagemagick.org" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] ImageMagick encontrado: $($magick.Source)" -ForegroundColor Green

# Configurar diretorios
$projectDir = "C:\MyDartProjects\pdfbox_dart"
$testImagesDir = "$projectDir\test_images\generated"
$jj2000Dir = "$projectDir\jj2000"
$openjpegBinDir = "$projectDir\openjpeg\build\bin\Release"

# Criar diretorio de testes
if (Test-Path $testImagesDir) {
    Remove-Item -Path $testImagesDir -Recurse -Force
}
New-Item -ItemType Directory -Path $testImagesDir -Force | Out-Null
Write-Host "[OK] Diretorio criado: $testImagesDir" -ForegroundColor Green

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Gerando Imagens de Teste" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Definir imagens de teste com 8-bit depth
$testImages = @(
    @{ Name = "gradient_horizontal"; Command = "magick -size 256x256 -depth 8 gradient:blue-red" },
    @{ Name = "gradient_vertical"; Command = "magick -size 256x256 -depth 8 gradient:blue-red -rotate 90" },
    @{ Name = "checkerboard"; Command = "magick -size 256x256 -depth 8 pattern:checkerboard" },
    @{ Name = "solid_red"; Command = "magick -size 256x256 -depth 8 xc:red" },
    @{ Name = "solid_green"; Command = "magick -size 256x256 -depth 8 xc:green" },
    @{ Name = "solid_blue"; Command = "magick -size 256x256 -depth 8 xc:blue" },
    @{ Name = "rainbow_stripes"; Command = "magick -size 256x256 -depth 8 gradient:" },
    @{ Name = "noise_pattern"; Command = "magick -size 256x256 -depth 8 xc: +noise Random" },
    @{ Name = "text_sample"; Command = "magick -size 256x256 -depth 8 xc:white -gravity center -pointsize 32 -annotate +0+0 JPEG2000" },
    @{ Name = "circles"; Command = "magick -size 256x256 -depth 8 xc:white -fill blue -draw 'circle 128,128 200,200'" }
)

# Gerar imagens PPM
foreach ($img in $testImages) {
    $ppmPath = "$testImagesDir\$($img.Name).ppm"
    Write-Host "  -> Gerando $($img.Name)..." -ForegroundColor Gray
    
    $cmd = "$($img.Command) $ppmPath"
    Invoke-Expression $cmd 2>&1 | Out-Null
    
    if (Test-Path $ppmPath) {
        $sizeKB = [math]::Round((Get-Item $ppmPath).Length / 1KB, 2)
        Write-Host "    [OK] Gerado: $ppmPath ($sizeKB KB)" -ForegroundColor Green
    } else {
        Write-Host "    [ERRO] Falha ao gerar $ppmPath" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Codificando com Java JJ2000" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Verificar JAR do JJ2000
$jj2000Jar = "$jj2000Dir\target\jj2000-5.5-SNAPSHOT.jar"
if (-not (Test-Path $jj2000Jar)) {
    Write-Host "Compilando JJ2000..." -ForegroundColor Yellow
    Push-Location $jj2000Dir
    mvn clean package -DskipTests 2>&1 | Out-Null
    Pop-Location
}

if (Test-Path $jj2000Jar) {
    Write-Host "[OK] JJ2000 JAR encontrado" -ForegroundColor Green
    
    foreach ($img in $testImages) {
        $ppmPath = "$testImagesDir\$($img.Name).ppm"
        $j2kPath = "$testImagesDir\$($img.Name)_jj2000.j2k"
        
        if (Test-Path $ppmPath) {
            Write-Host "  -> Codificando $($img.Name)..." -ForegroundColor Gray
            
            java -cp $jj2000Jar ucar.jpeg.JJ2KEncoder -i $ppmPath -o $j2kPath -verbose off 2>&1 | Out-Null
            
            if (Test-Path $j2kPath) {
                $sizeKB = [math]::Round((Get-Item $j2kPath).Length / 1KB, 2)
                Write-Host "    [OK] Codificado: $sizeKB KB" -ForegroundColor Green
            } else {
                Write-Host "    [ERRO] Falha ao codificar" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "[AVISO] JJ2000 JAR nao encontrado. Pulando." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Codificando com OpenJPEG" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$openjpegEnc = "$openjpegBinDir\opj_compress.exe"
if (Test-Path $openjpegEnc) {
    Write-Host "[OK] OpenJPEG encoder encontrado" -ForegroundColor Green
    
    foreach ($img in $testImages) {
        $ppmPath = "$testImagesDir\$($img.Name).ppm"
        $jp2Path = "$testImagesDir\$($img.Name)_openjpeg.jp2"
        
        if (Test-Path $ppmPath) {
            Write-Host "  -> Codificando $($img.Name)..." -ForegroundColor Gray
            
            & $openjpegEnc -i $ppmPath -o $jp2Path 2>&1 | Out-Null
            
            if (Test-Path $jp2Path) {
                $sizeKB = [math]::Round((Get-Item $jp2Path).Length / 1KB, 2)
                Write-Host "    [OK] Codificado: $sizeKB KB" -ForegroundColor Green
            } else {
                Write-Host "    [ERRO] Falha ao codificar" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "[AVISO] OpenJPEG nao encontrado em $openjpegBinDir" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Decodificando com Java JJ2000" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $jj2000Jar) {
    foreach ($img in $testImages) {
        $j2kPath = "$testImagesDir\$($img.Name)_jj2000.j2k"
        $decodedPath = "$testImagesDir\$($img.Name)_jj2000_decoded.ppm"
        
        if (Test-Path $j2kPath) {
            Write-Host "  -> Decodificando $($img.Name)..." -ForegroundColor Gray
            
            java -cp $jj2000Jar ucar.jpeg.jj2000.j2k.decoder.CmdLnDecoder -i $j2kPath -o $decodedPath -verbose off 2>&1 | Out-Null
            
            if (Test-Path $decodedPath) {
                Write-Host "    [OK] Decodificado com sucesso" -ForegroundColor Green
            } else {
                Write-Host "    [ERRO] Falha ao decodificar" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Decodificando com OpenJPEG" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$openjpegDec = "$openjpegBinDir\opj_decompress.exe"
if (Test-Path $openjpegDec) {
    foreach ($img in $testImages) {
        $jp2Path = "$testImagesDir\$($img.Name)_openjpeg.jp2"
        $decodedPath = "$testImagesDir\$($img.Name)_openjpeg_decoded.ppm"
        
        if (Test-Path $jp2Path) {
            Write-Host "  -> Decodificando $($img.Name)..." -ForegroundColor Gray
            
            & $openjpegDec -i $jp2Path -o $decodedPath 2>&1 | Out-Null
            
            if (Test-Path $decodedPath) {
                Write-Host "    [OK] Decodificado com sucesso" -ForegroundColor Green
            } else {
                Write-Host "    [ERRO] Falha ao decodificar" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Executando Testes Dart" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

Push-Location $projectDir
dart test test/jj2000/decoder_reference_comparison_test.dart
Pop-Location

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "Concluido!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Imagens de teste criadas em: $testImagesDir" -ForegroundColor Cyan
