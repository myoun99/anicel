import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨★★★F-243: AN IMAGE DRAWN IN AN ADVANCED BLEND IS HELD TO ITS OWN RECT.
///
/// On the Windows app (Impeller GLES) an image drawn in multiply or screen
/// is blended over everything the pass reaches, its border stretched
/// outward, and a clip to the image's own rect is what held it
/// (`blendsInPlace` has the measurement). This runner rasters with Skia,
/// which never reaches past, so the pin is the CLIP laid right before each
/// image draw — read off the calls — for the two draws every layer and every
/// folder composites through.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ui.Image imageOf(int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF3050C0),
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// The clip laid right before each image [draw] makes, or null where the
  /// draw was not held.
  List<Object?> clipsBeforeTheImages(void Function(Canvas canvas) draw) {
    final canvas = TestRecordingCanvas();
    draw(canvas);
    final calls = [for (final call in canvas.invocations) call.invocation];
    Object? clipBefore(int at) =>
        at > 0 && calls[at - 1].memberName == #clipRect
        ? calls[at - 1].positionalArguments[0]
        : null;
    return [
      for (var i = 0; i < calls.length; i += 1)
        if (calls[i].memberName == #drawImage ||
            calls[i].memberName == #drawImageRect)
          clipBefore(i),
    ];
  }

  final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [3, 3]);

  group('a layer image', () {
    const rect = Rect.fromLTWH(8, 4, 60, 40);
    const atOriginRect = Rect.fromLTWH(0, 0, 60, 40);

    List<Object?> heldTo(
      LayerBlendMode blend, {
      List<ResolvedLayerEffect> effects = const [],
      bool atOrigin = false,
    }) {
      final image = imageOf(60, 40);
      addTearDown(image.dispose);
      return clipsBeforeTheImages(
        (canvas) => drawPosedLayerImage(
          canvas,
          image: image,
          worldRect: atOrigin ? atOriginRect : rect,
          extent: atOrigin ? atOriginRect : rect,
          canvasSize: const CanvasSize(width: 120, height: 80),
          pose: null,
          opacity: 1,
          blendMode: blend,
          effects: effects,
          texelScale: 1,
          filterQuality: ui.FilterQuality.low,
          drawAtOriginWhen: (_, _) => atOrigin,
        ),
      );
    }

    test('in multiply and screen, held to where it lands', () {
      expect(heldTo(LayerBlendMode.multiply), [rect]);
      expect(heldTo(LayerBlendMode.screen), [rect]);
      expect(
        heldTo(LayerBlendMode.multiply, atOrigin: true),
        [atOriginRect],
        reason: 'the whole-image draw at the origin is the same image',
      );
    });

    test('in normal and add, drawn as it always was', () {
      expect(heldTo(LayerBlendMode.normal), [null]);
      expect(heldTo(LayerBlendMode.add), [null]);
    });

    test('with a blur, not clipped — the spread is part of what it draws', () {
      expect(heldTo(LayerBlendMode.multiply, effects: [blur]), [null]);
    });
  });

  group('a sub-tree blit (a folder, the row being drawn on)', () {
    const bounds = Rect.fromLTWH(6, 4, 40, 30);

    ({List<Object?> clips, Rect destination}) blitWith(Paint paint) {
      final clips = clipsBeforeTheImages(
        (canvas) => drawSubtreeAsImage(
          canvas: canvas,
          bounds: bounds,
          rasterScale: 1,
          paintSubtree: (into, _) => into.drawRect(
            bounds,
            Paint()..color = const Color(0xFF3050C0),
          ),
          compose: (blit) => blit(paint),
        ),
      );
      return (clips: clips, destination: debugLastSubtreeRaster!.destination);
    }

    test('in multiply, held to its destination', () {
      final blit = blitWith(Paint()..blendMode = BlendMode.multiply);
      expect(blit.clips, [blit.destination]);
    });

    test('in srcOver and plus, not', () {
      expect(blitWith(Paint()).clips, [null]);
      expect(blitWith(Paint()..blendMode = BlendMode.plus).clips, [null]);
    });

    test('with a paint filter, never — the NO CLIP decision on the blit', () {
      final blit = blitWith(
        Paint()
          ..blendMode = BlendMode.multiply
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      );
      expect(blit.clips, [null]);
    });
  });
}
