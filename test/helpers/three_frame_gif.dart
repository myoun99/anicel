import 'dart:io';

/// Writes a three-frame GIF, one pixel a frame, black · white · black, into
/// [directory] and returns its path — no two neighbours alike, because the
/// import folds a repeated frame into a hold and three equal frames would
/// land as ONE cel.
///
/// ⛔THE ONE GIF FIXTURE: a GIF's frames are hand-written LZW here, which no
/// test should spell out twice.
Future<String> writeThreeFrameGif(Directory directory, String name) async {
  // [lzw] is the pixel's LZW code: 0x44 for palette 0, 0x4C for 1.
  List<int> frame(int lzw) => [
    0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // graphic control
    0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // image
    0x02, 0x02, lzw, 0x01, 0x00, // its one pixel
  ];
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes([
    ...'GIF89a'.codeUnits,
    0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // 1×1, two colours
    0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
    ...frame(0x44), ...frame(0x4C), ...frame(0x44),
    0x3B,
  ]);
  return file.path;
}
