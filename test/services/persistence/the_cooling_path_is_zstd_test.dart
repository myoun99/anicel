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
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// 🚨★★★**THE FLOOR IS SILENT, SO SOMETHING HAS TO WATCH IT.**
///
/// A cel is compressed when it COOLS, and cooling runs in a background
/// isolate (`BrushFrameStore._coolLoop`) — and if the compressor ever
/// refused over there what the main isolate takes, [compressAnicelPayload]
/// would quietly write deflate instead. ↩️Until the connection round
/// (connection-round-checklist H) each isolate probed for the C engine on
/// its own, and a pin here said the probe survived the hop; the names are
/// the code asset's now, bound in every isolate alike.
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

  AnicelCelBlob cooled() => AnicelCelBlob.ofSurface(
    key,
    BitmapSurface(
      canvasSize: const CanvasSize(width: 256, height: 256),
      tileSize: 128,
    ),
  );

  test(
    'a cel cooled in a background isolate carries the zstd codec byte',
    () async {
      // The blob a cel cools into, made in the same kind of isolate.
      final codec = await Isolate.run(() => cooled().codec);
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
    expect(cooled().codec, anicelCodecZstd);
  });

  /// The other half of the contract. ↩️「without an engine」 until the
  /// connection round: a refusal is what is left of that world.
  group('where zstd refuses', () {
    setUp(() => QaCelCompressor.debugForceRefusal = true);
    tearDown(() => QaCelCompressor.debugForceRefusal = false);

    test('the floor is deflate, and it still round-trips', () {
      final blob = cooled();
      expect(
        blob.codec,
        anicelCodecDeflate,
        reason: 'a refusal means the payload must be readable by dart:io',
      );
      expect(blob.decoded((back) => back.key), key);
    });

    test('and a deflate payload decompresses through dart:io alone', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(4096, (i) => i & 0xFF),
      );
      final packed = compressAnicelPayload(bytes);
      expect(packed.codec, anicelCodecDeflate);
      expect(decompressAnicelPayload(packed.codec, packed.bytes), bytes);
    });

    /// 🚨**WHAT A PERSON IS TOLD WHEN A FILE WILL NOT OPEN.**
    ///
    /// `_showFileError` writes `'$error'` onto the screen, so whatever is
    /// thrown here IS the message. zlib throws「Filter error, bad data」—
    /// it names its own internal filter and says nothing about the file —
    /// and 유저 2026-08-31 met exactly that on a project, with nothing in
    /// it to act on. The zstd arm has always answered in the app's terms;
    /// this pins that BOTH do.
    test('🚨 a payload that will not inflate says so in the app terms', () {
      // Not a deflate stream at all: the shape a truncated archive, or a
      // file from a build that laid its bytes down differently, arrives in.
      final rubbish = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 7 + 3) & 0xFF),
      );
      expect(
        () => decompressAnicelPayload(anicelCodecDeflate, rubbish),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('could not be decompressed'),
              contains('damaged'),
              // ⛔zlib's own words stay, at the END — a bug report needs
              // them and a dialog must not lead with them.
              contains('Filter error'),
            ),
          ),
        ),
      );
    });

    test('🚨 an empty manifest entry says the file is truncated', () {
      expect(
        () => decodeAnicelProjectEntryBytes(
          anicelProjectEntryNameCompressed,
          Uint8List(0),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('truncated'),
          ),
        ),
        reason:
            '`bytes.first` on an empty entry is StateError: No element, and '
            'that goes on the screen verbatim',
      );
    });
  });
}
