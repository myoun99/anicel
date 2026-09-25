import 'package:anicel/src/services/media/media_byte_source.dart';

/// A reader's hold on a file that is only ever itself — no project, no
/// carried copy: what a test that is not about WHERE the bytes are hands a
/// reader that asks (`ProjectFile.holdMediaBytes` in the app). Its bytes
/// never move.
Future<HeldMediaBytes> theFileItself(String path) async => HeldMediaBytes(
  source: MediaFileBytes(path),
  release: () {},
  moved: const Stream<HeldBytesMove>.empty(),
  again: () => theFileItself(path),
);
