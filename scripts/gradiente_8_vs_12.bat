@echo off
setlocal

set WIDTH=800
set BAR_HEIGHT=60
set QUANT_STEPS=40
set GAP=20
set BORDER_X=80
set BORDER_Y=60

rem Cria uma tabela de cores suave cobrindo todo o espectro desejado
magick -size 256x1 xc: ^
  -sparse-color Shepards "0,0 #ff0000 43,0 #ffff00 86,0 #00ff00 128,0 #00ffff 171,0 #0000ff 214,0 #ff00ff 255,0 #ff0000" ^
  -filter Catrom -resize 256x1! grad_clut.png

rem Gradiente horizontal em alta precisao (base 12-bit)
magick -size %WIDTH%x%BAR_HEIGHT% -define gradient:direction=east gradient: grad_gray.png
magick grad_gray.png grad_clut.png -clut grad_12bit.png

rem Reduz resolucao horizontal e reamplia com filtro point para criar passos visiveis (8-bit)
magick grad_12bit.png ^
  -filter point -resize %QUANT_STEPS%x%BAR_HEIGHT%! ^
  -filter point -resize %WIDTH%x%BAR_HEIGHT%! grad_8bit.png

rem Cria espaco em branco entre as barras
magick -size %WIDTH%x%GAP% xc:white grad_spacer.png

rem Empilha: 8-bit, espaco, 12-bit
magick grad_8bit.png grad_spacer.png grad_12bit.png -append grad_barras.png

rem Adiciona moldura e legendas
magick grad_barras.png ^
  -bordercolor white -border %BORDER_X%x%BORDER_Y% ^
  -gravity north -pointsize 42 -annotate +0+10 "8-bit vs 12-bit comparison" ^
  -gravity west  -pointsize 24 -annotate +15-40 "8-bit" ^
  -gravity west  -pointsize 24 -annotate +15+40 "12-bit" ^
  grad_final.png

del grad_clut.png grad_gray.png grad_spacer.png grad_8bit.png grad_12bit.png grad_barras.png >nul 2>&1

echo Gerado: grad_final.png
endlocal

