import 'dart:typed_data';

/// The first index at or after [from] where [needle] starts in [bytes],
/// with the whole needle ending at or before [until] (the end by default);
/// -1 when absent. THE byte-needle scan — a FourCC, a UTF-16BE key, a
/// property name are all this with a different needle, whichever file
/// format holds them.
int indexOfBytes(Uint8List bytes, List<int> needle, int from, [int? until]) {
  final end = (until ?? bytes.length) - needle.length;
  for (var i = from; i <= end; i++) {
    var ok = true;
    for (var k = 0; k < needle.length; k++) {
      if (bytes[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}
