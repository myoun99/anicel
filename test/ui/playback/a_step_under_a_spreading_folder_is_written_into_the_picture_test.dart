@Tags(['gpu'])
library;

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';

import '../../helpers/a_stroke_written_into_the_picture_shown.dart';

/// 🚨A STEP UNDER A FOLDER OR AN ADJUSTMENT THAT SPREADS IS WRITTEN INTO
/// THE PICTURE TOO (one-picture-per-frame, 유저 2026-10-25 「원본 기준 위에서
/// 푼다」): where it shows is grown by the chain's spread and patched there
/// ([aStrokeIsWrittenIntoThePictureShown]), pixel for pixel what the frame
/// drawn as it stands shows. ↩️It drew the frame as it stands, the whole
/// view at canvas resolution, at every step.
///
/// The stroke ends a pixel short of its tile's edge, so the blur carries it
/// past the tile — and past the pixel the change is widened by.
void main() {
  final views = {
    'panned': CanvasViewport(panX: 8, panY: 4),
    'at 200%': CanvasViewport(zoom: 2, panX: -6, panY: -10),
    'at 50%': CanvasViewport(zoom: 0.5, panX: 8, panY: 4),
  };
  const ratios = [1.0, 1.5];
  const strokeAt = Rect.fromLTRB(6, 6, 15, 15);
  final blur = [
    ResolvedLayerEffect(kind: EffectKind.blur, values: [4, 4]),
  ];

  CompositeNode<CanvasStackRow> row(BrushFrameKey cel) =>
      CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(opacity: 1, frameKey: cel),
      );

  group('a row in a blurred folder', () {
    aStrokeIsWrittenIntoThePictureShown(
      views: views,
      ratios: ratios,
      strokeAt: strokeAt,
      stack: (cel) => [
        CompositeGroup<CanvasStackRow>(
          children: [row(cel)],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: blur,
        ),
      ],
      withThePinsOfNoView: false,
    );
  });

  group('a row under a blurring adjustment', () {
    aStrokeIsWrittenIntoThePictureShown(
      views: views,
      ratios: ratios,
      strokeAt: strokeAt,
      stack: (cel) => [
        CompositeAdjustment<CanvasStackRow>(
          children: [row(cel)],
          effects: blur,
          mix: 1,
        ),
      ],
      withThePinsOfNoView: false,
    );
  });
}
