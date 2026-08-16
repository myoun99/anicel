import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';

import 'timeline_row_chrome_probe.dart';

/// An edge's ink is decided by the COLOR it sits on, not by the theme
/// (feedback #11 gave it two inks by surface; 2026-08-17 unified the pick
/// with the block text's ground law): a paper block — the purple paper
/// included — takes the black bar, the dark cut-block plate takes the
/// white one, and no bar wears an outline anywhere.
const _trackId = TrackId('ink-track');

Project _project() => Project(
  id: const ProjectId('ink-project'),
  name: 'Ink',
  createdAt: DateTime.utc(2026, 7, 28),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-1'),
          name: 'cut-1',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('cut-1-sb'),
              name: 'SB',
              kind: LayerKind.storyboard,
              frames: [
                Frame(id: const FrameId('f0'), duration: 1, strokes: const []),
                Frame(id: const FrameId('f5'), duration: 1, strokes: const []),
              ],
              timeline: const {
                0: TimelineExposure.drawing(FrameId('f0'), length: 5),
                5: TimelineExposure.drawing(FrameId('f5'), length: 5),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('the bar\'s ink is the ground law\'s pick', () {
    test('a dark ground takes the LIGHT ink, a light one the dark ink', () {
      final onPaper = blockEdgeGripBarColor(BlockEdgeGripInk.rest);
      final onPlate = blockEdgeGripBarColor(
        BlockEdgeGripInk.rest,
        ground: AppColors.washUp,
      );

      expect(onPaper, isNot(onPlate));
      expect(onPaper.withValues(alpha: 1), timelineTextOnLightGroundColor);
      expect(onPlate.withValues(alpha: 1), timelineTextOnDarkGroundColor);
      // The light bar is genuinely lighter, which is the whole point: the
      // near-black one vanished against a dark cut block.
      expect(
        onPlate.computeLuminance(),
        greaterThan(onPaper.computeLuminance()),
      );
    });

    test('the PURPLE paper takes the dark bar — the same pick its numbers '
        'make, one law for text and edges', () {
      final onPurple = blockEdgeGripBarColor(
        BlockEdgeGripInk.rest,
        ground: layerMarkColor(LayerMark.purple),
      );
      expect(onPurple.withValues(alpha: 1), timelineTextOnLightGroundColor);
      expect(
        onPurple,
        blockEdgeGripBarColor(BlockEdgeGripInk.rest),
        reason:
            'purple sits on the same side of the crossover as the plain '
            'paper, so the bar does not change weight between them',
      );
    });

    test('the paper default keeps the dark bar\'s weights', () {
      expect(
        blockEdgeGripBarColor(BlockEdgeGripInk.rest),
        timelineTextOnLightGroundColor.withValues(alpha: 0.38),
      );
      expect(
        blockEdgeGripBarColor(BlockEdgeGripInk.hovered),
        timelineTextOnLightGroundColor.withValues(alpha: 0.95),
      );
    });

    test('a LIVE drag keeps the accent on both grounds — a drag in flight '
        'must not change colour with its row', () {
      expect(
        blockEdgeGripBarColor(BlockEdgeGripInk.dragging),
        blockEdgeGripBarColor(
          BlockEdgeGripInk.dragging,
          ground: AppColors.washUp,
        ),
      );
    });
  });

  testWidgets('the storyboard strip hands its grips the cut-block plate '
      'while the timeline row hands them its layer\'s paper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: HomePage(initialProject: _project()),
      ),
    );
    await tester.pumpAndSettle();

    // The cut-internal timeline's storyboard row: its own (unmarked) paper.
    expect(
      timelineRowChromePainter(tester, 'cut-1-sb')!.gripGround,
      layerMarkColor(LayerMark.none),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    // The strip's grips sit on the cut block's resting plate, which is
    // dark — so the ground law gives them the light bar there.
    expect(
      timelineRowChromePainter(
        tester,
        _trackId.value,
        prefix: 'storyboard',
      )!.gripGround,
      AppColors.washUp,
    );
  });
}
