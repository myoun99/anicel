import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';

import '../../helpers/repaint_strays.dart';

/// 🚨I-22 ③: A PLAYBACK TICK REPAINTS ITS TICK LAYERS AND THE CANVAS —
/// NOTHING ELSE.
///
/// What a tick moves — the cursor layers, the frame counters, the
/// transport's readouts, the lanes' values — used to rebuild in the build
/// scope of whichever `LayoutBuilder` it happened to sit under, which lays
/// that LayoutBuilder out again, and a layout ends by asking for a paint of
/// everything up to the boundary above it. Measured at the ten-minute zoom
/// (09-27): every playback frame repainted the page root, the dock and the
/// panel bodies around the few pixels that moved. [TickLayer] is where a
/// tick is laid out and painted alone.
///
/// This reads, at each of a run of ticks, every boundary waiting to repaint,
/// and names any that waits at EVERY one of them and is neither a tick layer
/// (or inside one) nor a canvas — whose picture changing IS the tick. Once
/// is not a tick's: what playing changes once (the play button's face, a
/// raster going still) settles, and the run is long enough for it to.
void main() {
  // Long cuts: the window reads no loop's wrap and no cut change.
  const frames = 96;

  /// [withSRow]: an S row gives the storyboard's rail lanes of its own to
  /// open. ⚠️Not the sheet's: its S-row name-tag header overflows its 28px
  /// column (27px, on master before this pin — a defect of its own, handed
  /// on 09-27), and the sheet's lanes are the cel layer's anyway.
  Project project({required bool withSRow}) => Project(
    id: const ProjectId('tick-layers'),
    name: 'Tick layers',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (var i = 0; i < 2; i += 1)
            Cut(
              id: CutId('cut-$i'),
              name: 'cut-$i',
              duration: frames,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('cut-$i-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
        seLayers: [
          if (withSRow)
            Layer(
              id: const LayerId('s1'),
              name: 'S1',
              kind: LayerKind.se,
              frames: const [],
            ),
        ],
      ),
    ],
  );

  String nameOf(RenderObject node) => nameOfBoundary(node, depth: 40);

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  /// Every boundary waiting to repaint that is not a tick layer's (or
  /// inside one) and not a canvas's.
  Set<RenderObject> strays(WidgetTester tester) {
    final allowed = tickLayersAndCanvas(tester);
    return {
      for (final view in tester.binding.renderViews)
        ...repaintStrays(view, allowed: allowed),
    };
  }

  final variants = <String, List<String>>{
    'timeline': [],
    'timeline with its lanes open': ['legend-lanes-toggle'],
    'x-sheet': ['timeline-orientation-toggle-button'],
    // The lanes are opened from the rail's legend, which the sheet has not:
    // opened first, they stay open through the turn.
    'x-sheet with its lanes open': [
      'legend-lanes-toggle',
      'timeline-orientation-toggle-button',
    ],
    'folded timeline': ['floating-bottom-collapse'],
    'folded storyboard': [
      'timeline-mode-storyboard-button',
      'floating-bottom-collapse',
    ],
    'storyboard': ['timeline-mode-storyboard-button'],
    'storyboard with its lanes open': [
      'timeline-mode-storyboard-button',
      'legend-lanes-toggle',
    ],
  };
  for (final MapEntry(key: view, value: taps) in variants.entries) {
    testWidgets('a tick in the $view repaints its tick layers and the '
        'canvas and nothing around them', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(
            initialProject: project(
              withSRow: !taps.contains('timeline-orientation-toggle-button'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in taps) {
        await tap(tester, key);
      }
      if (taps.contains('legend-lanes-toggle')) {
        expect(
          find.byType(TimelineLaneControlsRow),
          findsWidgets,
          reason: 'premise: the lanes are open',
        );
      }
      final playback = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session
          .playbackRig
          .playback;

      await tester.tap(
        find.byKey(const ValueKey<String>('playback-play-button')),
      );
      for (var i = 0; i < 12; i += 1) {
        await tester.pump(const Duration(milliseconds: 42));
      }

      Set<RenderObject>? atEveryTick;
      for (var tick = 0; tick < 4; tick += 1) {
        final before = playback.globalFrameIndexListenable.value;
        // One tick, run to its layout and stopped before the paint, so what
        // waits to repaint can be read.
        await tester.pump(
          const Duration(milliseconds: 42),
          EnginePhase.layout,
        );
        expect(
          playback.globalFrameIndexListenable.value,
          isNot(before),
          reason: 'premise: the pump was a tick',
        );
        final now = strays(tester);
        atEveryTick = atEveryTick?.intersection(now) ?? now;
        await tester.pump();
      }
      expect(
        atEveryTick!.map(nameOf),
        isEmpty,
        reason: atEveryTick.map(nameOf).join('\n\n'),
      );

      // Playback runs on a clock: it stops before the test ends.
      playback.stop();
      await tester.pump();
    });
  }
}
