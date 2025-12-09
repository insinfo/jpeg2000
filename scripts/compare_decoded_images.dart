// Script para comparar imagens PPM pixel a pixel
import 'dart:io';
import 'dart:typed_data';

class PPMData {
  final int width;
  final int height;
  final Uint8List pixels;

  PPMData(this.width, this.height, this.pixels);
}

PPMData parsePPM(Uint8List bytes) {
  var offset = 0;

  // Read P6 header
  while (bytes[offset] != 0x0A) offset++; // Skip to first newline
  offset++;

  // Skip comments
  while (bytes[offset] == 0x23) {
    // '#'
    while (bytes[offset] != 0x0A) offset++;
    offset++;
  }

  // Read width and height
  var widthStr = '';
  while (bytes[offset] != 0x20 && bytes[offset] != 0x0A) {
    widthStr += String.fromCharCode(bytes[offset++]);
  }
  offset++; // Skip space

  var heightStr = '';
  while (bytes[offset] != 0x20 && bytes[offset] != 0x0A) {
    heightStr += String.fromCharCode(bytes[offset++]);
  }
  offset++; // Skip newline or space

  // Read max value (should be 255)
  while (bytes[offset] != 0x0A) offset++;
  offset++;

  // Read pixel data
  final width = int.parse(widthStr);
  final height = int.parse(heightStr);
  final pixels = Uint8List.view(bytes.buffer, offset);

  return PPMData(width, height, pixels);
}

void main(List<String> args) {
  if (args.length != 2) {
    print('Uso: dart compare_decoded_images.dart <image1.ppm> <image2.ppm>');
    exit(1);
  }

  final file1 = File(args[0]);
  final file2 = File(args[1]);

  if (!file1.existsSync()) {
    print('Erro: Arquivo não encontrado: ${args[0]}');
    exit(1);
  }

  if (!file2.existsSync()) {
    print('Erro: Arquivo não encontrado: ${args[1]}');
    exit(1);
  }

  print('Comparando:');
  print('  Imagem 1: ${args[0]}');
  print('  Imagem 2: ${args[1]}');
  print('');

  final data1 = parsePPM(file1.readAsBytesSync());
  final data2 = parsePPM(file2.readAsBytesSync());

  print('Dimensões:');
  print('  Imagem 1: ${data1.width}x${data1.height}');
  print('  Imagem 2: ${data2.width}x${data2.height}');
  print('');

  if (data1.width != data2.width || data1.height != data2.height) {
    print('ERRO: Dimensões diferentes!');
    exit(1);
  }

  // Compare pixels
  var differences = 0;
  var maxDiff = 0;
  var totalDiff = 0;
  
  final sampleSize = 10; // Show first 10 pixels
  print('Primeiros $sampleSize pixels (RGB):');
  
  for (var i = 0; i < data1.pixels.length && i < data2.pixels.length; i++) {
    final diff = (data1.pixels[i] - data2.pixels[i]).abs();
    
    if (diff > 0) {
      differences++;
      totalDiff += diff;
    }
    
    if (diff > maxDiff) {
      maxDiff = diff;
    }
    
    // Print first few pixels
    if (i < sampleSize * 3) {
      if (i % 3 == 0) {
        final pixelNum = i ~/ 3;
        final r1 = data1.pixels[i];
        final g1 = data1.pixels[i + 1];
        final b1 = data1.pixels[i + 2];
        final r2 = data2.pixels[i];
        final g2 = data2.pixels[i + 1];
        final b2 = data2.pixels[i + 2];
        print('  Pixel $pixelNum: ($r1,$g1,$b1) vs ($r2,$g2,$b2)');
      }
    }
  }

  print('');
  print('Resultados:');
  print('  Total de bytes: ${data1.pixels.length}');
  print('  Diferenças: $differences bytes (${(differences / data1.pixels.length * 100).toStringAsFixed(2)}%)');
  print('  Diferença máxima: $maxDiff');
  print('  Diferença média: ${differences > 0 ? (totalDiff / differences).toStringAsFixed(2) : 0}');
  print('');

  if (differences == 0) {
    print('✓ As imagens são idênticas!');
  } else {
    print('✗ As imagens são diferentes.');
    
    // Show regions with differences
    print('');
    print('Primeiras diferenças encontradas:');
    var count = 0;
    for (var i = 0; i < data1.pixels.length && i < data2.pixels.length && count < 10; i++) {
      final diff = (data1.pixels[i] - data2.pixels[i]).abs();
      if (diff > 0) {
        final component = ['R', 'G', 'B'][i % 3];
        final pixelNum = i ~/ 3;
        final y = pixelNum ~/ data1.width;
        final x = pixelNum % data1.width;
        print('  Posição ($x,$y) componente $component: ${data1.pixels[i]} vs ${data2.pixels[i]} (diff: $diff)');
        count++;
      }
    }
  }
}
