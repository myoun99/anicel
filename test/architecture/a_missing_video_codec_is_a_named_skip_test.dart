import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/os_video_codec.dart';
import '../helpers/source_ledger.dart';

/// 🚨**A TEST THAT NEEDS THE OS VIDEO CODEC ASKS FOR IT THROUGH ONE
/// HELPER** — `osVideoEncoderOrSkip` / `osVideoDecoderOrSkip`
/// (`test/helpers/os_video_codec.dart`) — so a missing one is a skip with
/// why, or a failure where the run must have one, never a silent pass.
///
/// Board F-494 (관제 2026-10-29): the tests that wrote a movie returned when
/// there was no encoder, and those that read one back returned when there
/// was no decoder; one file answered it with a skip, and two with a failure
/// anywhere but Linux. Every copy passed on its own, so the ratchet is a
/// source scan, and it proves it can see what it forbids.
void main() {
  group('what a test does where there is no OS codec', () {
    test('a host with one fails', () {
      expect(videoCodecAbsence(what: 'video encoder', hostHasOne: true), (
        fails: true,
        reason: 'the engine has no OS video encoder on this platform, and '
            'this host has one',
      ));
    });

    test('a host with none skips with why', () {
      expect(videoCodecAbsence(what: 'video encoder', hostHasOne: false), (
        fails: false,
        reason: 'the engine has no OS video encoder on this platform',
      ));
    });
  });

  group('the scan', () {
    /// ⚠️Exempt from its own scan: the lines it plants are STRINGS holding
    /// the very spelling the scan matches.
    const itself =
        'test/architecture/a_missing_video_codec_is_a_named_skip_test.dart';
    const helper = 'test/helpers/os_video_codec.dart';

    /// The files that read the engine's video codec themselves, and why.
    const ledger = <String, String>{
      'test/services/video/qa_video_encoder_test.dart':
          'the encoder\'s own test — it pins the capability answer itself, '
          'and hands the export service the engine\'s encoder to choose by',
    };

    /// Reading a codec, not letting one go: a test that closes or aborts
    /// what an earlier one left is not asking whether there is one.
    final readsTheCodec = RegExp(
      r'QaVideo(?:De|En)coder\.instance(?!\.(?:close|abort)\(\))',
    );

    test('it sees what it forbids', () {
      expect(
        readsTheCodec.hasMatch('QaVideoDecoder.instance.isSupported'),
        isTrue,
      );
      expect(
        readsTheCodec.hasMatch('final encoder = QaVideoEncoder.instance;'),
        isTrue,
      );
      for (final notARead in [
        'QaVideoDecoder.instance.close()',
        'QaVideoEncoder.instance.abort()',
        'osVideoDecoderOrSkip()',
      ]) {
        expect(readsTheCodec.hasMatch(notARead), isFalse, reason: notARead);
      }
    });

    test('no test reads the OS video codec itself, outside the ledger', () {
      expectSetMatchesLedger(
        [
          for (final file in dartFilesUnder('test'))
            if (file.path.replaceAll(r'\', '/') case final path
                when path != itself &&
                    path != helper &&
                    readsTheCodec.hasMatch(
                      codeOfLines(file.readAsStringSync()),
                    ))
              path,
        ],
        ledger.keys,
        unledgered: 'ask with `osVideoEncoderOrSkip` / '
            '`osVideoDecoderOrSkip` — a missing codec is then a skip with '
            'why, or a failure where the run must have one',
        paidOff: 'these no longer read the codec themselves — take them off '
            'the ledger',
      );
      expectEveryEntrySaysWhy(ledger);
    });
  });
}
