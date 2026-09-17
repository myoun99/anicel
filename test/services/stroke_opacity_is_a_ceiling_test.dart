import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// F-12 — **stroke opacity is a CEILING.**
///
/// 유저: 「불투명도 낮춰도 dab 겹치면 100%까지 진해진다」. Dabs accumulate
/// source-over, so a factor carried on each dab is not a ceiling: overlap
/// enough of them and any factor below 1 still converges on opaque. The
/// ceiling has to scale the ACCUMULATED stroke, once — which is what the
/// selection mask already does, so opacity travels as a mask with no shape.
void main() {
  const layerId = LayerId('layer-a');
  const frameId = FrameId('frame-a');
  const canvasSize = CanvasSize(width: 8, height: 8);

  BitmapSurface emptySurface() =>
      BitmapSurface(canvasSize: canvasSize, tileSize: 8);

  /// One pixel's worth of paint at (2, 2), laid [flow] deep.
  BrushDab pixelDab(int sequence, {double flow = 0.5}) => BrushDab(
    center: CanvasPoint(x: 2.5, y: 2.5),
    color: 0xFFFF0000,
    size: 1,
    // The dab's OWN opacity, which after F-12 carries only per-dab
    // variation (the pressure curve, the jitter) and never the setting.
    opacity: 1,
    flow: flow,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  int committedAlphaAt(BrushDabSequence sequence, {int x = 2, int y = 2}) {
    final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: emptySurface(),
      sequence: sequence,
      layerId: layerId,
      frameId: frameId,
    );
    final pixels = bitmapSurfaceRegionPixels(
      result.afterSurface,
      DirtyRegion(
        left: x,
        top: y,
        rightExclusive: x + 1,
        bottomExclusive: y + 1,
      ),
    );
    return pixels[3];
  }

  group('the ceiling holds however many dabs pile up', () {
    test('at full opacity overlapping dabs still reach opaque', () {
      expect(
        committedAlphaAt(
          BrushDabSequence([for (var i = 0; i < 24; i += 1) pixelDab(i)]),
        ),
        255,
        reason:
            'fixture premise: these dabs DO accumulate — without that the '
            'test below would pass on a stroke that simply never got dark',
      );
    });

    test('at 50% they never pass 50%, and more dabs do not change that', () {
      final few = committedAlphaAt(
        BrushDabSequence([for (var i = 0; i < 2; i += 1) pixelDab(i)], 0.5),
      );
      final many = committedAlphaAt(
        BrushDabSequence([for (var i = 0; i < 60; i += 1) pixelDab(i)], 0.5),
      );

      expect(few, greaterThan(0), reason: 'it still paints');
      expect(many, greaterThanOrEqualTo(few), reason: 'and still builds up');
      expect(
        many,
        lessThanOrEqualTo(128),
        reason:
            '🚨THE REPORT: 60 overlapping dabs at 50% must not reach 100%. '
            'This is what fails when the factor rides the dabs.',
      );
    });

    test(
      'every setting is the alpha a saturated stroke lands on',
      () {
        for (final opacity in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          // Enough dabs that the accumulation is saturated (255) before the
          // ceiling, so what lands IS the ceiling and nothing else.
          final landed = committedAlphaAt(
            BrushDabSequence(
              [for (var i = 0; i < 40; i += 1) pixelDab(i, flow: 1)],
              opacity,
            ),
          );
          expect(
            landed,
            (opacity * 255).round(),
            reason: 'a saturated stroke at $opacity lands on exactly $opacity',
          );
        }
      },
    );
  });

  group('the live overlay draws THROUGH the same ceiling', () {
    test('pre-blended pixels are byte-identical to what the commit lands', () {
      const opacity = 0.4;
      final dabs = [for (var i = 0; i < 12; i += 1) pixelDab(i)];

      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: 8,
      )..strokeOpacity = opacity;
      rasterizer.blendFrom(dabs, from: 0);
      final live = rasterizer.preBlendedOverlayTile(
        tileX: 0,
        tileY: 0,
        base: emptySurface(),
        mode: BrushBlendMode.color,
        erase: false,
      );
      expect(live, isNotNull, reason: 'the stroke touched this tile');

      final committed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: emptySurface(),
        sequence: BrushDabSequence(dabs, opacity),
        layerId: layerId,
        frameId: frameId,
      );
      final expected = bitmapSurfaceRegionPixels(
        committed.afterSurface,
        DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 8,
          bottomExclusive: 8,
        ),
      );

      // The overlay uploads premultiplied bytes, so compare the one channel
      // the ceiling moves and the only one premultiplication leaves alone.
      for (var i = 0; i < 64; i += 1) {
        expect(
          live!.readPremultiplied(Uint8List.fromList)[i * 4 + 3],
          expected[i * 4 + 3],
          reason: 'pixel $i: what is on screen IS what commits',
        );
      }
    });

    test('a selection and the ceiling BOTH survive', () {
      final selection = Uint8List(4)..setAll(0, [0, 128, 200, 255]);
      final folded = strokeCoverageMask(
        selection: selection,
        pixelCount: 4,
        opacity: 0.5,
      )!;

      expect(folded[0], 0, reason: 'outside the selection stays outside');
      // mul255(128, 128) = 64, mul255(200, 128) = 100, mul255(255, 128) = 128
      expect(folded[1], 64);
      expect(folded[2], 100);
      expect(folded[3], 128, reason: 'fully selected is capped by the ceiling');
      expect(
        selection,
        Uint8List(4)..setAll(0, [0, 128, 200, 255]),
        reason: 'the caller keeps its selection — the fold copies',
      );
    });

    test('a masked tile at full opacity is the selection mask untouched', () {
      final selection = Uint8List(3)..setAll(0, [0, 77, 255]);
      expect(
        identical(
          strokeCoverageMask(selection: selection, pixelCount: 3, opacity: 1),
          selection,
        ),
        isTrue,
        reason:
            'no ceiling = no work, so the no-opacity path allocates exactly '
            'what it always did',
      );
      expect(
        strokeCoverageMask(pixelCount: 3, opacity: 1),
        isNull,
        reason: 'and with no selection either there is nothing to mask',
      );
    });

    test('with no selection the ceiling still reaches the kernel', () {
      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: 8,
      )..strokeOpacity = 0.5;
      rasterizer.blendFrom([
        for (var i = 0; i < 30; i += 1) pixelDab(i),
      ], from: 0);
      final live = rasterizer.preBlendedOverlayTile(
        tileX: 0,
        tileY: 0,
        base: emptySurface(),
        mode: BrushBlendMode.color,
        erase: false,
      )!;

      expect(
        live.readPremultiplied(Uint8List.fromList)[(2 * 8 + 2) * 4 + 3],
        lessThanOrEqualTo(128),
        reason:
            'the mask is built from the ceiling alone when there is no '
            'selection to fold it into — otherwise the stroke on screen goes '
            'opaque and only the commit obeys',
      );
    });

    test('a selection still clips while the ceiling caps', () {
      final rasterizer =
          BrushLiveStrokeRasterizer(canvasSize: canvasSize, tileSize: 8)
            ..strokeOpacity = 0.5
            ..selectionRegion = CanvasSelectionRegion.shape(
              CanvasSelectionShape.rect(left: 0, top: 0, right: 2, bottom: 8),
            );
      rasterizer.blendFrom([
        for (var i = 0; i < 30; i += 1) pixelDab(i),
      ], from: 0);
      final live = rasterizer.preBlendedOverlayTile(
        tileX: 0,
        tileY: 0,
        base: emptySurface(),
        mode: BrushBlendMode.color,
        erase: false,
      );

      // (2, 2) is outside a selection that ends at x = 2.
      expect(
        live?.readPremultiplied(Uint8List.fromList)[(2 * 8 + 2) * 4 + 3] ?? 0,
        0,
        reason: 'the selection is not softened into a 50% edge by the fold',
      );
    });
  });

  group('where the number lives', () {
    // ⛔The offline `brushInputSamplesToBrushDabs` used to demonstrate these
    // two, and it is gone (nothing in the app ever called it). The law is
    // the same and it belongs to the TYPE: the ceiling is a property of the
    // stroke, and it is not on the dabs.
    test('the ceiling is the SEQUENCE\'s, and the dabs stay at 1.0', () {
      final sequence = BrushDabSequence([
        for (var i = 0; i < 4; i += 1) pixelDab(i),
      ], 0.3);

      expect(sequence.opacity, 0.3);
      expect(
        sequence.dabs.map((dab) => dab.opacity),
        everyElement(1.0),
        reason:
            '🚨a dab carrying the setting is the bug itself — it would '
            'accumulate past 0.3 and the ceiling would then square it',
      );
    });

    test('an empty stroke still carries its ceiling', () {
      expect(BrushDabSequence(const [], 0.3).opacity, 0.3);
    });

    test('the ceiling round-trips and counts as identity', () {
      final sequence = BrushDabSequence([pixelDab(0)], 0.25);
      final restored = BrushDabSequence.fromJson(sequence.toJson());

      expect(restored.opacity, 0.25);
      expect(restored, sequence);
      expect(restored.hashCode, sequence.hashCode);
      expect(
        BrushDabSequence([pixelDab(0)], 0.25) ==
            BrushDabSequence([pixelDab(0)], 0.5),
        isFalse,
        reason:
            'two strokes that differ only in ceiling are different strokes — '
            'a redo must not pick up the other one',
      );
      expect(
        BrushDabSequence([pixelDab(0)]).toJson().containsKey('opacity'),
        isFalse,
        reason: 'a full-strength stroke serialises exactly as it always did',
      );
      expect(
        BrushDabSequence.fromJson({'dabs': const []}).opacity,
        1.0,
        reason: 'and a stroke saved before F-12 reads back at full strength',
      );
    });

    test('adding dabs keeps the ceiling', () {
      final sequence = BrushDabSequence([pixelDab(0)], 0.25);
      expect(sequence.add(pixelDab(1)).opacity, 0.25);
      expect(sequence.addAll([pixelDab(1), pixelDab(2)]).opacity, 0.25);
    });
  });
}
