import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/native/qa_audio_decoder.dart';

import 'temp_dir.dart';

/// The file at [path] decoded whole, as it is — the ordinary case of the
/// decoder's one door ([QaAudioDecoder.decodeSpan]). Null when there is no
/// engine, or nothing recognized it.
QaDecodedAudio? decodeAudioFile(String path) => QaAudioDecoder.instance
    ?.decodeSpan(path, length: File(path).lengthSync(), framed: false);

/// [bytes] decoded through a scratch file: the decoder has no door that takes
/// bytes in memory, because nothing in the app has any to hand it.
QaDecodedAudio? decodeAudioBytes(Uint8List bytes) {
  final directory = Directory.systemTemp.createTempSync('anicel-decode');
  try {
    final path = '${directory.path}${Platform.pathSeparator}sound';
    File(path).writeAsBytesSync(bytes);
    return decodeAudioFile(path);
  } finally {
    deleteTempQuietly(directory);
  }
}
