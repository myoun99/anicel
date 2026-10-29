import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨**A TEST WRITES ITS MOVIE THROUGH ONE WRITER** — `writeEncodedMovie`
/// (`test/helpers/encoded_movie.dart`).
///
/// Board test-movie-writers-with-sound-are-five-copies (2026-10-29): six
/// tests each opened the engine's encoder and looped their pictures and
/// sound into it — one algorithm, six spellings, one of them laying a frame
/// a fixed count of samples that drifts off the frames at 44.1kHz. Every
/// copy passed on its own, so the ratchet is a source scan, and it proves
/// it can see what it forbids.
void main() {
  /// ⚠️Exempt from its own scan: the lines it plants are STRINGS holding
  /// the very spelling the scan matches.
  const itself = 'test/architecture/a_movie_is_written_one_way_test.dart';
  const writer = 'test/helpers/encoded_movie.dart';

  /// The files that write frames into the encoder themselves, and why.
  const ledger = <String, String>{
    'test/services/video/qa_video_encoder_test.dart':
        'the encoder\'s own test — what it drives frame by frame is the '
        'encoder, odd sizes and refused calls among it',
    'test/services/video/qa_video_encoder_v21_test.dart':
        'the encoder\'s own test of its second entry points — its subject '
        'is the call, not a movie to read',
  };

  final writesAFrame = RegExp(r'\.writeFrame\(');

  test('the scan sees what it forbids', () {
    expect(writesAFrame.hasMatch('encoder.writeFrame(grey)'), isTrue);
    expect(writesAFrame.hasMatch('expect(e.writeFrame(\n rgba), isTrue)'), isTrue);
    expect(writesAFrame.hasMatch('writeEncodedMovie(path, frames: 6)'), isFalse);
    expect(writesAFrame.hasMatch('void writeFrameCount()'), isFalse);
  });

  test('no test writes a movie\'s frames itself, outside the ledger', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('test'))
          if (file.path.replaceAll(r'\', '/') case final path
              when path != itself &&
                  path != writer &&
                  writesAFrame.hasMatch(file.readAsStringSync()))
            path,
      ],
      ledger.keys,
      unledgered: 'write it with `writeEncodedMovie` — pictures, sound and '
          'its rate are its arguments',
      paidOff: 'these no longer write frames themselves — take them off the '
          'ledger',
    );
    expectEveryEntrySaysWhy(ledger);
  });
}
