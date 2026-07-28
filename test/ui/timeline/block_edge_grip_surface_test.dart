import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/home_page.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_cell_style.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';

import 'timeline_row_chrome_probe.dart';

/// An edge has two inks, and which one it takes is decided by what it sits
/// ON, not by the theme (feedback #11): the timeline's blocks are near-white
/// paper in every theme, while the storyboard strip is the cut block, which
/// follows the theme and goes dark.
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
  group('the bar has two inks', () {
    test('a dark surface takes the LIGHT ink, a light one the dark ink', () {
      final onPaper = blockEdgeGripBarColor(BlockEdgeGripInk.rest);
      final onLane = blockEdgeGripBarColor(
        BlockEdgeGripInk.rest,
        surface: Brightness.dark,
      );

      expect(onPaper, isNot(onLane));
      expect(onPaper.r, timelineDrawingInkColor.r);
      expect(onLane.r, timelineLaneInkColor.r);
      // The light bar is genuinely lighter, which is the whole point: the
      // near-black one vanished against a dark cut block.
      expect(
        onLane.computeLuminance(),
        greaterThan(onPaper.computeLuminance()),
      );
    });

    test('the timeline\'s own pixels do not move — paper is the default', () {
      expect(
        blockEdgeGripBarColor(BlockEdgeGripInk.rest),
        timelineDrawingInkColor.withValues(alpha: 0.38),
      );
      expect(
        blockEdgeGripBarColor(BlockEdgeGripInk.hovered),
        timelineDrawingInkColor.withValues(alpha: 0.95),
      );
    });

    test('a LIVE drag keeps the accent on both surfaces — a drag in flight '
        'must not change colour with its row', () {
      expect(
        blockEdgeGripBarColor(BlockEdgeGripInk.dragging),
        blockEdgeGripBarColor(
          BlockEdgeGripInk.dragging,
          surface: Brightness.dark,
        ),
      );
    });
  });

  testWidgets('the storyboard strip asks for the THEME\'s brightness while '
      'the timeline row stays on paper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: HomePage(initialProject: _project()),
      ),
    );
    await tester.pumpAndSettle();

    // The cut-internal timeline's storyboard row: paper, whatever the theme.
    expect(
      timelineRowChromePainter(tester, 'cut-1-sb')!.gripSurface,
      Brightness.light,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    // The strip's grips sit on the cut block, which went dark with the theme.
    expect(
      timelineRowChromePainter(
        tester,
        _trackId.value,
        prefix: 'storyboard',
      )!.gripSurface,
      Brightness.dark,
    );
  });
}
