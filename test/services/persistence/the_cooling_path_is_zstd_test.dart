import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/persistence/anicel_payload_codec.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// 🚨★★★**THE FLOOR IS SILENT, SO SOMETHING HAS TO WATCH IT.**
///
/// A cel is compressed when it COOLS, and cooling runs in a background
/// isolate (`BrushFrameStore._coolLoop`). Statics do not cross an isolate
/// boundary, so `QaCelCompressor.instance` re-probes for the engine over
/// there — and if it ever failed to find what the main isolate found,
/// [compressAnicelPayload] would quietly write deflate instead.
///
/// ⛔Nothing would go red. Deflate is a legitimate answer by design ("a
/// file this app writes must never need a library that might not be
/// there"), the blob carries a codec byte, and both codecs round-trip.
/// The app would simply get slower to scrub — the 0.11ms promotion back
/// to 3.35ms — with no error anywhere.
///
/// 유저 2026-08-30 asked exactly this: 「식을때 압축된다고? 그게 지금
/// zstd로 안되고있단거고?」. The answer was yes-it-is-zstd, and it was
/// verified by hand rather than by anything that would keep being true.
void main() {
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  AnicelCelEntry entry() => AnicelCelEntry.fromSurface(
    key,
    BitmapSurface(
      canvasSize: const CanvasSize(width: 256, height: 256),
      tileSize: 128,
    ),
  );

  /// Whether THIS run has an engine at all. A machine without one cannot
  /// answer the question, and must say so rather than pass.
  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  test(
    'the compressor survives the isolate hop the cooling loop makes',
    () async {
      if (!engineHere()) {
        markTestSkipped('no engine on this run — nothing to compare against');
        return;
      }
      // ⛔The assertion is CONDITIONAL on the main isolate having one, which
      // is what makes it meaningful: "both absent" is a fine state, "here
      // but not there" is the regression.
      final overThere = await Isolate.run(() {
        final compressor = QaCelCompressor.instance;
        return compressor != null && compressor.isSupported;
      });
      expect(
        overThere,
        isTrue,
        reason:
            'the main isolate found the engine and the background one did '
            'not, so every cooled cel would silently become deflate',
      );
    },
  );

  test(
    'a cel cooled in a background isolate carries the zstd codec byte',
    () async {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      final cooled = entry();
      // The exact call `_coolLoop` makes, in the same kind of isolate.
      final codec = await Isolate.run(() => AnicelCelBlob.encode(cooled).codec);
      expect(
        codec,
        anicelCodecZstd,
        reason:
            'this is the byte a save writes into the .anicel — the cold and '
            'file-ref tiers hand it through untouched',
      );
    },
  );

  test('and the main isolate agrees, so a hot cel encoded at save time '
      'matches what cooling wrote', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    expect(AnicelCelBlob.encode(entry()).codec, anicelCodecZstd);
  });

  /// The other half of the contract, and the one every machine can run.
  group('without an engine', () {
    setUp(() => QaCelCompressor.debugInstanceOverride = () => null);
    tearDown(() {
      QaCelCompressor.debugInstanceOverride = null;
      QaCelCompressor.debugResetForTests();
    });

    test('the floor is deflate, and it still round-trips', () {
      final blob = AnicelCelBlob.encode(entry());
      expect(
        blob.codec,
        anicelCodecDeflate,
        reason: 'no engine means the payload must be readable by dart:io',
      );
      expect(blob.decode().key, key);
    });

    test('and a deflate payload decompresses without the engine', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(4096, (i) => i & 0xFF),
      );
      final packed = compressAnicelPayload(bytes);
      expect(packed.codec, anicelCodecDeflate);
      expect(decompressAnicelPayload(packed.codec, packed.bytes), bytes);
    });
  });
}
