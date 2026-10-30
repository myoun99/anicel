@Tags(['gpu'])
library;

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';

import '../../helpers/a_stroke_written_into_the_picture_shown.dart';

/// 🚨A STEP ON A ROW POSED ALONG THE AXES IS WRITTEN INTO THE PICTURE
/// (one-picture-per-frame, 유저 2026-10-25 「원본 기준 위에서 푼다」): told
/// through the pose — moved, scaled, stretched, flipped, turned a quarter —
/// and patched there ([aStrokeIsWrittenIntoThePictureShown]), pixel for
/// pixel what the frame drawn as it stands shows. ↩️Every posed row drew
/// the frame as it stands, the whole view at canvas resolution, at every
/// step (2026-10-27); a turn off the axes still does
/// (`CanvasLayerStackView`'s `_spreadThroughItsPose` has the measurement).
///
/// 🔬Each pixel to within 1/255 a channel: a pose of no whole scale lays a
/// tile's seam inside a pixel, and the tester's Vulkan halves the patched
/// level and the level round it apart by one along it — the line of the
/// seam at 50% on a 1.5 screen, 0 everywhere else (2026-10-30), as it
/// halves line art (`a_stroke_is_written_into_the_picture_shown_on_impeller
/// _test.dart`).
void main() {
  final views = {
    'panned': CanvasViewport(panX: 8, panY: 4),
    'at 200%': CanvasViewport(zoom: 2, panX: -6, panY: -10),
    'at 50%': CanvasViewport(zoom: 0.5, panX: 8, panY: 4),
  };
  const ratios = [1.0, 1.5];
  // A pixel short of its tile's edge, as the spreading rows' step is.
  const strokeAt = Rect.fromLTRB(6, 6, 15, 15);
  final blur = [
    ResolvedLayerEffect(kind: EffectKind.blur, values: [4, 0]),
  ];

  const enlarged = GuideTransform(2.5, 0, 0, 2.5, -15.3, -14.1);
  CompositeNode<CanvasStackRow> row(
    BrushFrameKey cel,
    GuideTransform pose, {
    double opacity = 1,
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(
      opacity: opacity,
      frameKey: cel,
      placement: pose,
    ),
  );

  for (final (name, stack) in <(
    String,
    List<CompositeNode<CanvasStackRow>> Function(BrushFrameKey cel),
  )>[
    ('moved', (cel) => [row(cel, const GuideTransform(1, 0, 0, 1, 3, 2))]),
    ('halved', (cel) => [row(cel, const GuideTransform(0.5, 0, 0, 0.5, 5, 5))]),
    (
      'stretched',
      (cel) => [row(cel, const GuideTransform(1.37, 0, 0, 0.83, 3.3, 2.7))],
    ),
    ('enlarged', (cel) => [row(cel, enlarged)]),
    (
      'flipped',
      (cel) => [row(cel, const GuideTransform(-1.21, 0, 0, 1.07, 37.45, 0.61))],
    ),
    (
      'turned a quarter',
      (cel) => [row(cel, const GuideTransform(0, 1.3, -1.3, 0, 30.2, -3.4))],
    ),
    ('enlarged, at half', (cel) => [row(cel, enlarged, opacity: 0.5)]),
    (
      'enlarged, in a blurred folder',
      (cel) => [
        CompositeGroup<CanvasStackRow>(
          children: [row(cel, enlarged)],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: blur,
        ),
      ],
    ),
  ]) {
    group('a row $name', () {
      aStrokeIsWrittenIntoThePictureShown(
        views: views,
        ratios: ratios,
        strokeAt: strokeAt,
        apartBy: 1,
        stack: stack,
        withThePinsOfNoView: false,
      );
    });
  }
}
