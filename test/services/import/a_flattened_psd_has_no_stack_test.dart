import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/psd_expand_import.dart';

/// The pixel half of EXPAND — nothing named it (2026-09-05).
///
/// The plan half has its own test (`psd_layer_plan_test`); what is pinned
/// here is the entry's own decision: a FLATTENED document has no stack to
/// expand, and answering null is how the caller falls back to the MERGE
/// reading, which handles it perfectly well.
void main() {
  ImportIdMint mint() {
    var layers = 0;
    var frames = 0;
    return ImportIdMint(
      nextLayerId: () => LayerId('L${layers += 1}'),
      nextFrameId: (_) => FrameId('F${frames += 1}'),
      nextCutId: () => const CutId('C1'),
    );
  }

  Future<PsdExpansion?> expand(Uint8List bytes) => readPsdExpansion(
    bytes: bytes,
    displayName: 'take.psd',
    cutId: const CutId('c'),
    duration: 12,
    canvas: const CanvasSize(width: 64, height: 64),
    fit: MediaFitMode.contain,
    mint: mint(),
  );

  /// A valid 8BPS header with no layer section and no image data — what a
  /// flattened document looks like from here.
  Uint8List flattened() => Uint8List.fromList(const [
    0x38, 0x42, 0x50, 0x53, // 8BPS
    0x00, 0x01, // version 1
    0, 0, 0, 0, 0, 0, // reserved
    0x00, 0x03, // channels
    0, 0, 0, 1, // height
    0, 0, 0, 1, // width
    0x00, 0x08, // depth
    0x00, 0x03, // RGB
    0, 0, 0, 0, // colour mode data
    0, 0, 0, 0, // image resources
    0, 0, 0, 0, // layer and mask
  ]);

  test('🚨a FLATTENED document answers null — there is no stack to expand, '
      'and the MERGE reading handles it perfectly well', () async {
    expect(await expand(flattened()), isNull);
  });

  test('⛔bytes that are not a Photoshop file are refused rather than read '
      'as an empty stack', () async {
    await expectLater(
      expand(Uint8List.fromList([1, 2, 3, 4, 5, 6])),
      throwsA(isA<FormatException>()),
    );
  });
}
