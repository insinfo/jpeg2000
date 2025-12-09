import 'dart:io';
import 'dart:typed_data';

void main() async {
  final dartFile = 'test_images/generated/solid_blue_dart.ppm';
  final javaFile = 'test_images/generated/solid_blue_jj2000_decoded.ppm';
  final openjpegFile = 'test_images/generated/solid_blue_openjpeg_decoded.ppm';
  
  print('Comparing PPM files pixel by pixel\n');
  
  final dartPpm = await readPpm(dartFile);
  final javaPpm = await readPpm(javaFile);
  final openjpegPpm = await readPpm(openjpegFile);
  
  print('=== Dart vs Java JJ2000 ===');
  comparePixels(dartPpm, javaPpm, 'Dart', 'Java');
  
  print('\n=== Dart vs OpenJPEG ===');
  comparePixels(dartPpm, openjpegPpm, 'Dart', 'OpenJPEG');
  
  print('\n=== Java vs OpenJPEG (baseline) ===');
  comparePixels(javaPpm, openjpegPpm, 'Java', 'OpenJPEG');
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

void comparePixels(Uint8List pixels1, Uint8List pixels2, String name1, String name2) {
  final minLen = pixels1.length < pixels2.length ? pixels1.length : pixels2.length;
  
  int totalPixels = minLen ~/ 3; // RGB
  int differences = 0;
  int maxDiff = 0;
  int sumDiff = 0;
  
  List<int> firstDiffIndices = [];
  
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
      
      if (firstDiffIndices.length < 10) {
        firstDiffIndices.add(i ~/ 3);
      }
    }
  }
  
  double diffPercent = (differences * 100.0) / totalPixels;
  double avgDiff = differences > 0 ? sumDiff / differences : 0;
  
  print('Total pixels: $totalPixels');
  print('Differences: $differences (${diffPercent.toStringAsFixed(2)}%)');
  print('Max pixel difference: $maxDiff');
  print('Avg difference (where diff > 0): ${avgDiff.toStringAsFixed(2)}');
  
  if (firstDiffIndices.isNotEmpty) {
    print('\nFirst 10 different pixel indices:');
    for (int idx in firstDiffIndices) {
      int i = idx * 3;
      print('  Pixel $idx: $name1 RGB(${pixels1[i]},${pixels1[i+1]},${pixels1[i+2]}) vs '
            '$name2 RGB(${pixels2[i]},${pixels2[i+1]},${pixels2[i+2]})');
    }
  }
}
