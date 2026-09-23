import 'package:anicel/src/services/media/media_byte_source.dart';

/// A reader's hold on a file that is only ever itself — no project, no
/// carried copy: what a test that is not about WHERE the bytes are hands a
/// reader that asks (`ProjectFile.holdMediaBytes` in the app).
Future<HeldMediaBytes> theFileItself(String path) async =>
    (source: MediaFileBytes(path), release: () {});
