import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pinned_fingerprints.dart';

/// A straight picture goes up to the display premultiplied by the app's
/// one premultiply, on a worker — and an upload the engine refuses says
/// so. ↩️Beside it the C took the pass (`premultipliedStraightRgba`), and
/// here stood its pins — the two branches one rounding, a refused decode
/// giving its native scratch back — until nothing asked it
/// (a-float-premultiplies-in-the-c-each-step). The kernel itself — the
/// GPU engine library's since C ABI 83 — is pinned to the Dart over every
/// colour at every alpha where the tiles it still multiplies go up
/// (`a_tile_upload_is_the_apps_premultiply_test`).
void main() {
  /// 🚨★★★**A DECODE THAT CANNOT SUCCEED HAS TO SAY SO.**
  ///
  /// `ui.decodeImageFromPixels` chains two futures and attaches an error
  /// handler to neither, so its callback fires once on success and never on
  /// failure — the caller is told nothing at all. Every image upload in this
  /// app wrapped that in a `Completer` with no `completeError`, which turned
  /// one refused frame into a panel that waited for it forever.
  ///
  /// The fixture is the cheapest genuine refusal there is: a descriptor that
  /// claims 64×64 RGBA over four bytes. Nothing validates that
  /// (`ImageDescriptor.raw` does no length check), so the engine gets as far
  /// as building the image and then hands back nothing — the same road a
  /// resize allocation takes when it fails on a small device, which is the
  /// case this exists for and the one a test cannot stage.
  ///
  /// ⚠️`runAsync`: the upload is engine work on a real thread, and the fake
  /// clock does not drive it. Without this the test would pass on a
  /// TIMEOUT-shaped hang rather than on the rejection.
  group('a refused upload rejects instead of hanging', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    test('the premultiplied door', () async {
      await binding.runAsync(() async {
        await expectLater(
          uploadRawRgba(Uint8List(4), width: 64, height: 64),
          throwsA(anything),
        );
      });
    });
  });

  // 🧭관제 2026-11-11 18:47 (gpu-export-path 1b ②): a viewer's page and a
  // cut piece go up premultiplied on a worker by the app's one premultiply —
  // the engine's, one ledger row pinning both (`surface/premultiply`) — and
  // no C is asked.
  group('on a worker', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    tearDown(() => debugWorkersRunHere = true);

    test('🎯a straight picture goes up premultiplied as the engine '
        'premultiplies it — every byte under every alpha', () async {
      // Every alpha (down) by every byte c (across) as R c, G 255 − c,
      // B 7c mod 256, as the engine's every_byte_by_every_alpha lays them.
      final bytes = Uint8List(256 * 256 * 4);
      var at = 0;
      for (var alpha = 0; alpha <= 255; alpha += 1) {
        for (var c = 0; c <= 255; c += 1) {
          bytes[at++] = c;
          bytes[at++] = 255 - c;
          bytes[at++] = (7 * c) % 256;
          bytes[at++] = alpha;
        }
      }
      final before = Uint8List.fromList(bytes);
      debugWorkersRunHere = false;

      final shown = await binding.runAsync(() async {
        final image = await decodeStraightRgbaImageOnAWorker(
          rgba: bytes,
          width: 256,
          height: 256,
        );
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return data!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      });

      expect(fingerprintHex(shown!), pinnedFingerprint('surface/premultiply'));
      expect(bytes, before, reason: 'the caller\'s buffer is never touched');
    });

    test('a refused upload rejects instead of hanging', () async {
      debugWorkersRunHere = false;
      await binding.runAsync(() async {
        await expectLater(
          decodeStraightRgbaImageOnAWorker(
            rgba: Uint8List(4),
            width: 64,
            height: 64,
          ),
          throwsA(anything),
        );
      });
    });
  });
}
