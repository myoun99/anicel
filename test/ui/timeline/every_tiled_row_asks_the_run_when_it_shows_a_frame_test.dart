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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import '../../helpers/storyboard_host.dart';
import '../storyboard_conte_row_probe.dart';

/// 🚨THE SUBSTRATE TILES ARE LET GO BY THE RUN'S OWN ORDER (card
/// playback-draws-frames-the-film-did-not-change-in, 2026-10-24): a store
/// past its room lets go of the tile the playing run shows latest, which it
/// asks each row's painter ([TimelineRowCellsPainter.stepsUntilShown]).
/// The store's side is pinned beside it (`timeline_grid_tile_store_test`);
/// this is the wiring — ⛔every surface that bakes tiles, not the one that
/// was easiest to mount: the rail across, the x-sheet down, the
/// storyboard's conte row on the film's frames. A row asked nothing
/// answers null and its tiles fall back to recency, which no screenful
/// would show.
void main() {
  const trackId = TrackId('run-track');
  const first = CutId('run-a');
  const second = CutId('run-b');
  const length = 12;

  Layer conte(String cut) => Layer(
    id: LayerId('$cut-sb'),
    name: 'SB',
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('$cut-p'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$cut-p'), length: 4)},
  );

  Cut cut(CutId id) => Cut(
    id: id,
    name: id.value,
    duration: length,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      for (var i = 0; i < 3; i += 1)
        Layer(
          id: LayerId('${id.value}-cel-$i'),
          name: '$i',
          frames: const [],
          timeline: const {},
        ),
      conte(id.value),
    ],
  );

  Project project() => Project(
    id: const ProjectId('run-project'),
    name: 'Run',
    createdAt: DateTime.utc(2026, 10, 24),
    tracks: [
      Track(id: trackId, name: 'Video', cuts: [cut(first), cut(second)]),
    ],
  );

  /// The film playing from frame 5, round and round: the second cut's own
  /// frame f is the film's 12 + f.
  PlayingDemand filmFromFive() => PlayingDemand(
    totalFrames: 2 * length,
    loops: () => true,
    playhead: () => 5,
    picturesOf: (_) => const [],
    playlistFrameOf: (cutId, frameIndex) => switch (cutId) {
      first => frameIndex,
      second => length + frameIndex,
      _ => null,
    },
  );

  List<TimelineRowCellsPainter> tiledRows(WidgetTester tester) => [
    for (final paint in tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    ))
      if (paint.painter case final TimelineRowCellsPainter row
          when row.tileStore != null)
        row,
  ];

  for (final orientation in TimelineOrientation.values) {
    testWidgets('🚨the timeline\'s rows ($orientation) answer the run\'s '
        'steps to the active cut\'s frames — and nothing while nothing '
        'plays', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      addTearDown(session.playbackRig.prerenderScheduler.cancel);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: session,
              builder: (context, _) => TimelineTabHost(
                session: session,
                orientation: orientation,
                onOrientationChanged: (_) {},
                pixelsPerFrame: 24,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.activeCutId, first, reason: '⛔premise: the first cut');
      final rows = tiledRows(tester);
      expect(rows, isNotEmpty, reason: '⛔premise: rows that bake tiles');

      expect(
        {for (final row in rows) row.stepsUntilShown?.call(7)},
        {null},
        reason: 'no run plays — the warmer stands around the playhead',
      );

      session.playbackRig.prerenderScheduler.follow(filmFromFive());
      expect(
        {for (final row in rows) row.stepsUntilShown?.call(7)},
        {2},
        reason: 'frame 7 of the active cut, two steps past the playhead',
      );
      expect(
        {for (final row in rows) row.stepsUntilShown?.call(3)},
        {2 * length - 2},
        reason: 'frame 3 is behind it: shown once the run comes round',
      );
    });
  }

  testWidgets('🚨the storyboard\'s conte row answers the run\'s steps to '
      'the cut under each film frame, at that cut\'s own frame', (
    tester,
  ) async {
    final session = await pumpStoryboardHost(tester, project());
    addTearDown(session.playbackRig.prerenderScheduler.cancel);
    final row = conteRowPainter(tester, trackId.value);

    expect(row.stepsUntilShown?.call(3), isNull, reason: 'nothing plays');

    session.playbackRig.prerenderScheduler.follow(filmFromFive());
    expect(
      row.stepsUntilShown?.call(length + 2),
      length + 2 - 5,
      reason: 'film frame 14 is the second cut\'s frame 2',
    );
    expect(
      row.stepsUntilShown?.call(3),
      2 * length - 2,
      reason: 'film frame 3 is the first cut\'s, behind the playhead',
    );
    expect(
      row.stepsUntilShown?.call(2 * length + 4),
      isNull,
      reason: 'past the last cut there is no cut to ask',
    );
  });
}
