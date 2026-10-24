import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/canvas/blends_in_place.dart';

/// 🚨★★★F-243: AN IMAGE DRAWN IN A BLEND THAT IS NOT IN PLACE IS HELD TO ITS
/// OWN RECT.
///
/// On the Windows app (Impeller GLES) an image drawn in multiply or screen
/// is blended over everything the pass reaches, its border stretched
/// outward, and a clip to the image's own rect is what held it
/// (`blendsInPlace` has the measurement). This runner rasters with Skia,
/// which never reaches past, so the pin is the CLIP laid right before the
/// image draw — read off the calls.
///
/// ↩️It read the two draws every layer and every folder composited through
/// (`drawPosedLayerImage`, `drawSubtreeAsImage`) until such a layer painted
/// normal over its backdrop (a-blurred-folder-cut-by-the-view-moves-on-
/// vulkan): a row's blend is `srcOver` or `plus` now. What still draws in
/// another are the overlay's tiles — `src` off the surface's grid, an
/// eraser's `dstOut` — and they are drawn through [drawHeldToItsRect].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rect = Rect.fromLTWH(8, 4, 60, 40);

  /// The clip laid right before the image [paint] draws through
  /// [drawHeldToItsRect], or null where the draw was not held.
  Object? clipBeforeTheImage(Paint paint) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 60, 40),
      Paint()..color = const Color(0xFF3050C0),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(60, 40);
    picture.dispose();
    addTearDown(image.dispose);
    final canvas = TestRecordingCanvas();
    drawHeldToItsRect(
      canvas,
      rect,
      paint,
      () => canvas.drawImage(image, rect.topLeft, paint),
    );
    final calls = [for (final call in canvas.invocations) call.invocation];
    final at = calls.indexWhere((call) => call.memberName == #drawImage);
    return at > 0 && calls[at - 1].memberName == #clipRect
        ? calls[at - 1].positionalArguments[0]
        : null;
  }

  test('a tile in src or an eraser\'s dstOut is held to its rect', () {
    expect(clipBeforeTheImage(Paint()..blendMode = BlendMode.src), rect);
    expect(clipBeforeTheImage(Paint()..blendMode = BlendMode.dstOut), rect);
  });

  test('in srcOver and plus, drawn as it always was', () {
    expect(clipBeforeTheImage(Paint()), isNull);
    expect(clipBeforeTheImage(Paint()..blendMode = BlendMode.plus), isNull);
  });

  test('with a paint filter, never — its spread is what it draws', () {
    expect(
      clipBeforeTheImage(
        Paint()
          ..blendMode = BlendMode.dstOut
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      ),
      isNull,
    );
  });
}
