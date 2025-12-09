import 'dart:io';
import 'dart:typed_data';

void main() async {
  final tests = [
    {'name': 'solid_blue', 'dartFile': 'test_images/generated/solid_blue_dart.ppm', 'javaFile': 'test_images/generated/solid_blue_jj2000_decoded.ppm'},
    {'name': 'solid_red', 'dartFile': 'test_images/generated/solid_red_dart.ppm', 'javaFile': 'test_images/generated/solid_red_jj2000_decoded.ppm'},
  ];
  
  for (var test in tests) {
    print('\n=== ${test['name']} ===');
    final dartFile = File(test['dartFile']!);
    final javaFile = File(test['javaFile']!);
    
    if (!dartFile.existsSync()) {
      print('⚠ Dart file not found: ${test['dartFile']}');
      continue;
    }
    if (!javaFile.existsSync()) {
      print('⚠ Java file not found: ${test['javaFile']}');
      continue;
    }
    
    final dartPpm = await readPpm(test['dartFile']!);
    final javaPpm = await readPpm(test['javaFile']!);
    
    comparePixels(dartPpm, javaPpm);
  }
}

Future<Uint8List> readPpm(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  
  // Skip PPM header
  int offset = 0;
  int lineCount = 0;
  while (lineCount < 3 && offset < bytes.length) {
    if (bytes[offset] == 10) { // newline
      lineCount++;
    }
    offset++;
  }
  
  return Uint8List.sublistView(bytes, offset);
}

void comparePixels(Uint8List pixels1, Uint8List pixels2) {
  final minLen = pixels1.length < pixels2.length ? pixels1.length : pixels2.length;
  
  int totalPixels = minLen ~/ 3; // RGB
  int differences = 0;
  int maxDiff = 0;
  int sumDiff = 0;
  
  for (int i = 0; i < minLen; i += 3) {
    int r1 = pixels1[i];
    int g1 = pixels1[i + 1];
    int b1 = pixels1[i + 2];
    
    int r2 = pixels2[i];
    int g2 = pixels2[i + 1];
    int b2 = pixels2[i + 2];
    
    int diffR = (r1 - r2).abs();
    int diffG = (g1 - g2).abs();
    int diffB = (b1 - b2).abs();
    
    int maxChannelDiff = [diffR, diffG, diffB].reduce((a, b) => a > b ? a : b);
    
    if (maxChannelDiff > 0) {
      differences++;
      if (maxChannelDiff > maxDiff) maxDiff = maxChannelDiff;
      sumDiff += maxChannelDiff;
    }
  }
  
  double diffPercent = (differences * 100.0) / totalPixels;
  double avgDiff = differences > 0 ? sumDiff / differences : 0;
  
  print('Total pixels: $totalPixels');
  print('Differences: $differences (${diffPercent.toStringAsFixed(2)}%)');
  print('Max pixel difference: $maxDiff');
  print('Avg difference: ${avgDiff.toStringAsFixed(2)}');
  
  if (diffPercent <= 1.0 && maxDiff <= 2) {
    print('✓ PASS: Differences within acceptable range');
  } else {
    print('✗ FAIL: Too many or too large differences');
  }
}
