import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_film_frame_on_the_engine.dart';

/// Card `a-jpeg-still-is-encoded-on-the-ui-isolate` (the CPU census, 관제
/// 2026-11-13): a JPG still — the export window's, Save As's — is encoded
/// on a worker, as every other still is. ↩️The engine's encoder walked the
/// whole frame on this isolate, a frame at a time through a run of them.
void main() {
  tearDown(() => debugWorkersRunHere = true);

  const jpg = ExportFormatSelection(
    kind: ExportMediaKind.still,
    stillFormat: ExportStillFormat.jpg,
  );

  test('🚨this isolate turns while a JPG is encoded — and what comes back '
      'is the encoder\'s picture', () async {
    // The road production takes: a worker of its own.
    debugWorkersRunHere = false;
    final frame = await filmFrameIn(
      const ui.Color(0xFF204060),
      width: 64,
      height: 32,
    );

    var turns = 0;
    final turning = Timer.periodic(Duration.zero, (_) => turns += 1);
    final List<int>? bytes;
    try {
      bytes = await stillEncoderFor(jpg)!(frame);
    } finally {
      turning.cancel();
    }

    expect(
      turns,
      greaterThan(0),
      reason: 'encoded here, the encode is over before this isolate turns '
          'once — the call hands back a future already done',
    );
    expect(bytes, isNotNull);
    expect(bytes!.take(3), [0xFF, 0xD8, 0xFF], reason: 'a JPEG file');
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final picture = (await codec.getNextFrame()).image;
    final data = await picture.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    expect((picture.width, picture.height), (64, 32));
    picture.dispose();
    codec.dispose();
    final rgb = Uint8List.sublistView(data!, 0, 3);
    expect(rgb[0], closeTo(0x20, 8));
    expect(rgb[1], closeTo(0x40, 8));
    expect(rgb[2], closeTo(0x60, 8));
  });
}
