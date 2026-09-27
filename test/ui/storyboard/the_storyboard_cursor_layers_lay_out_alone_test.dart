import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
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
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

/// 🚨I-22 ③: THE STORYBOARD'S CURSOR LAYERS LAY OUT ALONE.
///
/// The playhead tint and the standing ring follow the playhead, and each
/// rebuilds on a tick. A rebuild inside a `LayoutBuilder`'s subtree lays
/// that LayoutBuilder out again (Flutter's build scope), and a layout ends
/// by asking for a paint of the region above it: both sat in the scope of
/// the storyboard body's LayoutBuilder, so every playback frame laid the
/// body out again and repainted the panel around it (measured at 0.16px,
/// profile build: the panel's paint-through 107ms of a 908ms tick sample).
/// Each rides a layer of its own now — its own boundary and its own scope.
void main() {
  const frames = 24;

  Project project() => Project(
    id: const ProjectId('cursor-layers'),
    name: 'Cursor layers',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (var i = 0; i < 4; i += 1)
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
      ),
    ],
  );

  testWidgets('a playhead move inside a cut moves the tint and the ring and '
      'lays out none of the storyboard around them', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final stripsColumn = find.byKey(
      const ValueKey<String>('storyboard-timeline-scroll-content'),
    );
    // The body's LayoutBuilder: the nearest one above the strips.
    final body = tester.renderObject(
      find
          .ancestor(of: stripsColumn, matching: find.byType(LayoutBuilder))
          .first,
    );
    // What the strips scroll in: the first boundary above them.
    final strips = tester.renderObject(stripsColumn);
    var up = strips.parent!.parent;
    while (up != null && !up.isRepaintBoundary) {
      up = up.parent;
    }
    final scroller = up!;
    expect(strips.parent, isA<RenderRepaintBoundary>(), reason: 'premise');

    final tint = find.byKey(const ValueKey<String>('storyboard-playhead'));
    final ring = find.byKey(const ValueKey<String>('storyboard-standing-cell'));
    // A seek — not a session notify: nothing rebuilds for it but what
    // follows the cursor.
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(2);
    await tester.pumpAndSettle();
    final tintAtTwo = tester.getRect(tint);
    final ringAtTwo = tester.getRect(ring);

    // Frame 2 → 12, inside cut-0. A rebuild in the body's scope asks the
    // body for a layout from a frame callback; one scheduled after it reads
    // what it asked. The frame then runs to its layout, and stops before the
    // paint, so what waits to repaint can be read too.
    session.selectFrameIndex(12);
    bool? bodyAsked;
    SchedulerBinding.instance.scheduleFrameCallback(
      (_) => bodyAsked = body.debugNeedsLayout,
    );
    await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
    expect(bodyAsked, isNotNull, reason: 'premise: the frame was read');
    expect(
      bodyAsked,
      isFalse,
      reason: 'the cursor layers rebuild in scopes of their own',
    );
    expect(
      scroller.debugNeedsPaint,
      isFalse,
      reason: 'and what they lay out paints on their own layers',
    );
    await tester.pump();
    expect(
      tester.getRect(tint).left,
      greaterThan(tintAtTwo.left),
      reason: 'premise: the tint followed the playhead',
    );
    expect(
      tester.getRect(ring).left,
      greaterThan(ringAtTwo.left),
      reason: 'premise: the ring followed the playhead',
    );
  });
}
