import 'dart:typed_data';
import 'package:jpeg2000/src/j2k/util/MsgLogger.dart';

class QuietLogger implements MsgLogger {
  @override
  void printmsg(int severity, String message) {
    if (severity >= MsgLogger.warning) {
      // print('[${MsgLogger.labelFor(severity)}]: $message');
    }
  }

  @override
  void println(String message, int firstLineIndent, int indent) {
    // Suppress
  }

  @override
  void flush() {}
}

class PpmProbe {
  final int width;
  final int height;
  final int maxValue;
  final int pixelCount;
  final Set<int> uniqueChannelValues;
  final bool hasChrominance;

  PpmProbe(this.width, this.height, this.maxValue, this.pixelCount,
      this.uniqueChannelValues, this.hasChrominance);

  static PpmProbe fromBytes(Uint8List data) {
    if (data.length < 11) {
      throw ArgumentError("PPM stream too short");
    }

    int index = 0;
    final tokens = <String>[];
    
    // Helper to read next token
    // void readToken() { ... } // Unused

    // Reset index to find the start of binary data properly.
    index = 0;
    tokens.clear();
    
    while (tokens.length < 4 && index < data.length) {
       // Skip whitespace
       while (index < data.length && _isWhitespace(data[index])) {
         index++;
       }
       
       if (index >= data.length) break;
       
       if (data[index] == 35) { // Comment
         while (index < data.length && data[index] != 10) {
           index++;
         }
         continue;
       }
       
       final start = index;
       while (index < data.length && !_isWhitespace(data[index]) && data[index] != 35) {
         index++;
       }
       
       tokens.add(String.fromCharCodes(data.sublist(start, index)));
    }
    
    // After the last token (maxval), there is exactly one whitespace char (usually newline).
    if (index < data.length && _isWhitespace(data[index])) {
      index++;
    }

    if (tokens.length < 4) {
      throw ArgumentError("Incomplete PPM header");
    }

    if (tokens[0] != "P6") {
      throw ArgumentError("Unsupported PPM magic: ${tokens[0]}");
    }

    final width = int.parse(tokens[1]);
    final height = int.parse(tokens[2]);
    final maxValue = int.parse(tokens[3]);

    final remaining = data.length - index;
    final pixelCount = remaining ~/ 3;
    final unique = <int>{};
    bool chroma = false;
    
    final inspect = (pixelCount < 512) ? pixelCount : 512;
    
    for (int i = 0; i < inspect; i++) {
      final base = index + i * 3;
      if (base + 2 >= data.length) break;
      
      final r = data[base];
      final g = data[base + 1];
      final b = data[base + 2];
      
      unique.add(r);
      unique.add(g);
      unique.add(b);
      
      if (r != g || g != b) {
        chroma = true;
      }
    }

    return PpmProbe(width, height, maxValue, pixelCount, unique, chroma);
  }

  static bool _isWhitespace(int charCode) {
    return charCode == 32 || charCode == 9 || charCode == 10 || charCode == 13;
  }
}

