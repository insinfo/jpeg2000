/// Base container for component sample blocks exchanged between JJ2000 stages.
abstract class DataBlk {
  static const int typeByte = 0;
  static const int typeShort = 1;
  static const int typeInt = 3;
  static const int typeFloat = 4;

  int ulx = 0;
  int uly = 0;
  int w = 0;
  int h = 0;
  int offset = 0;
  int scanw = 0;
  bool progressive = false;

  static int sizeOf(int type) {
    switch (type) {
      case typeByte:
        return 8;
      case typeShort:
        return 16;
      case typeInt:
      case typeFloat:
        return 32;
      default:
        throw ArgumentError('Unsupported data type: $type');
    }
  }

  int getDataType();

  Object? getData();

  void setData(Object? data);

  @override
  String toString() {
    final typeLabel = () {
      switch (getDataType()) {
        case typeByte:
          return 'Unsigned Byte';
        case typeShort:
          return 'Short';
        case typeInt:
          return 'Integer';
        case typeFloat:
          return 'Float';
        default:
          return 'Unknown';
      }
    }();
    return 'DataBlk: upper-left($ulx,$uly), width=$w, height=$h, '
        'progressive=$progressive, offset=$offset, scanw=$scanw, type=$typeLabel';
  }
}
