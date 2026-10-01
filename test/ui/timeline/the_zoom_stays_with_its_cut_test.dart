import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// F-253 (유저 2026-10-01): 「타임라인패널의 줌 상태는 컷마다 기억하도록.
/// 지금 한번 바꾸면 컷마다 다른컷에서 바꾼 값 따라가니」.
///
/// The zoom was the window's one value, so whatever a cut was zoomed to
/// every other cut showed too. Each cut keeps its own now, and a cut nobody
/// zoomed opens at the default rather than at the last cut's.
void main() {
  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 48,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-layer'), name: 'A', frames: const []),
    ],
  );

  Project project() => Project(
    id: const ProjectId('zoom-per-cut'),
    name: 'Zoom per cut',
    createdAt: DateTime.utc(2026, 10, 1),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [cut('cut-a'), cut('cut-b')],
      ),
    ],
  );

  testWidgets('each cut keeps the zoom it was left at — and one nobody '
      'zoomed opens at the default', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project()),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    double zoom() =>
        tester.widget<TimelinePanel>(find.byType(TimelinePanel)).pixelsPerFrame;
    Future<void> step({required bool zoomIn}) async {
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            zoomIn ? 'timeline-zoom-in-button' : 'timeline-zoom-out-button',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> open(String id) async {
      session.selectCut(CutId(id));
      await tester.pumpAndSettle();
      expect(session.activeCutId, CutId(id), reason: 'premise: $id is open');
    }

    await open('cut-a');
    expect(zoom(), TimelinePanel.defaultPixelsPerFrame);
    await step(zoomIn: true);
    final zoomA = zoom();
    expect(zoomA, greaterThan(TimelinePanel.defaultPixelsPerFrame));

    await open('cut-b');
    expect(
      zoom(),
      TimelinePanel.defaultPixelsPerFrame,
      reason: 'B was never zoomed — it must not follow the zoom A was left at',
    );
    await step(zoomIn: false);
    final zoomB = zoom();
    expect(zoomB, lessThan(TimelinePanel.defaultPixelsPerFrame));

    await open('cut-a');
    expect(zoom(), zoomA, reason: 'A comes back at its own zoom');
    await open('cut-b');
    expect(zoom(), zoomB, reason: 'and B at its own');
  });
}
