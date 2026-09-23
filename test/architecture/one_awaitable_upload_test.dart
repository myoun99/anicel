import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★**ONE AWAITABLE BYTES→PICTURE UPLOAD, AND IT IS THE ONE THAT CAN
/// SAY NO.**
///
/// `ui.decodeImageFromPixels` starts two futures and attaches an error
/// handler to neither — the inner chain is not even returned to the outer
/// one — so its callback fires exactly once on success and ZERO times on any
/// failure, and nothing at all reaches the caller. Read in the SDK source
/// (`sky_engine/lib/ui/painting.dart`); every decode failure funnels into
/// `Codec.getNextFrame`'s null-image branch and completes with an error into
/// that dropped chain. That is the DART side of the call, so no backend
/// escapes it — the sentence used to name Skia-on-Windows as the case that
/// proved it, which stopped being true when 3.47 made Impeller the desktop
/// default (2026-09-16) and was never the reason anyway.
///
/// Seven places in `lib/` bridged that callback to a `Future` with a
/// `Completer<ui.Image>` that had no `completeError`, so the only way any of
/// them could settle was success. Each one was a place that waited forever
/// on a refused decode: the media viewer's read-ahead, an export, a brush
/// tip save, a compose loop that also leaked its native staging buffer.
/// They were the SAME ALGORITHM written out seven times, which under this
/// repo's connascence rule makes them copies however differently they read.
///
/// ⛔A behaviour test cannot close this. Seven copies that all agree today
/// pass every test there is; what fails is the eighth, written next year by
/// someone who reached for the SDK function because it was there. So the
/// nail is a source scan, and the number is ZERO — `uploadRawRgba` and
/// `decodeStraightRgbaImage` in `lib/src/services/straight_rgba_image.dart`
/// are awaitable, and nothing needs a Completer to reach a picture any more.
///
/// ⚠️This does NOT ban `ui.decodeImageFromPixels`. Five call sites use it as
/// what it is — fire-and-forget, no future, nobody waiting — and converting
/// those is a different round with a different question (board card
/// `a-decode-marker-nobody-clears`: their in-flight markers are cleared only
/// in the success callback, so a refusal wedges them in another way). What
/// is banned is the BRIDGE, because a bridge implies a caller who waits.
void main() {
  Iterable<({String path, int line, String text})> sourceLines() sync* {
    for (final file in dartFilesUnder('lib/src')) {
      final relative = file.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src'));
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        yield (path: key, line: index + 1, text: lines[index]);
      }
    }
  }

  /// 🚨THE INSTRUMENT FIRST. A scan that walked an empty tree would report
  /// zero offenders and read exactly like a pass — this repo has been caught
  /// by a green that was measuring nothing more than once.
  test('the premise: it read the real tree', () {
    expect(sourceLines().length, greaterThan(100000));
  });

  test('🚨nothing bridges a decode callback to a future it cannot fail', () {
    final offenders = [
      for (final line in sourceLines())
        if (line.text.contains('Completer<ui.Image>') &&
            !line.text.trimLeft().startsWith('///') &&
            !line.text.trimLeft().startsWith('//'))
          '${line.path}:${line.line}  ${line.text.trim()}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'a `Completer<ui.Image>` here means someone is AWAITING a picture, '
          'and the only thing there is to bridge from is a callback that is '
          'never invoked on failure — so the await is one refusal away from '
          'lasting forever. Await `uploadRawRgba` (premultiplied bytes) or '
          '`decodeStraightRgbaImage` (straight alpha) instead: they run the '
          'identical six engine steps as a chain of awaits, and therefore '
          'reject. If a Completer is genuinely wanted for something else, '
          'say what and why here rather than deleting the check.\n'
          '${offenders.join('\n')}',
    );
  });
}
