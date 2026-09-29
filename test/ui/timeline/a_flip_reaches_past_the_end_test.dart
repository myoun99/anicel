import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

import '../../helpers/scrollable_of.dart';

/// 🗣️F-225 (유저 2026-09-29): 「타임라인 간편오버레이상태에서 플립으로
/// 컷너머 넘어가는등 스크롤 움직이는 조작 발생하는데, 타임라인에서는
/// 발생안하고, 발생해서 스크롤 바뀐상태에서 타임라인 펼치면 스크롤 동기화
/// 안되어있음」 · 「블록있을땐 넘어가는데 빈공간인 갭부분? 엔드라인 너머부분이
/// 조작안하는거같음. 이상한 규칙 둔거같은데 언제든 넘어가도록 통일」.
///
/// The frame axis is endless: a walk goes on past the cut into the dim cells
/// beyond it, and the view has to go with it. The walk's reveal was held to
/// the cells already built, so it stopped at their end — and the folded row,
/// which keeps its window as a value, went on, so the grid opened on a page
/// the row had left.
void main() {
  /// A cut far shorter than the timeline's window, so the built cells end
  /// a little past the window and the walk leaves them quickly.
  Project shortCut() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(cuts: [track.cuts.first.copyWith(duration: 12)]),
      ],
    );
  }

  final frameScroller = find.byKey(
    const ValueKey<String>('timeline-frame-scroll-viewport'),
  );

  Future<EditorSessionManager> openTimeline(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: shortCut())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  ScrollPosition frameAxisOf(WidgetTester tester) =>
      scrollableOf(tester, frameScroller).controller!.position;

  /// Walks with `.` — the Next Frame key — until the playhead stands
  /// [past] cells beyond the cells built when the walk began.
  Future<void> walkPastTheBuiltEnd(
    WidgetTester tester,
    EditorSessionManager session, {
    int past = 6,
  }) async {
    final position = frameAxisOf(tester);
    const cell = TimelineZoomLimits.defaultPixelsPerFrame;
    final builtFrames =
        ((position.maxScrollExtent + position.viewportDimension) / cell)
            .ceil();
    while (session.currentFrameIndex < builtFrames + past) {
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('🚨a walk past the built cells takes the view with it — the '
      'cells grow under it', (tester) async {
    final session = await openTimeline(tester);
    final before = frameAxisOf(tester);
    expect(before.pixels, 0, reason: 'premise: the axis at its start');
    final builtEnd = before.maxScrollExtent + before.viewportDimension;

    await walkPastTheBuiltEnd(tester, session);

    final position = frameAxisOf(tester);
    const cell = TimelineZoomLimits.defaultPixelsPerFrame;
    final frame = session.currentFrameIndex;
    expect(frame * cell, greaterThan(builtEnd), reason: 'premise: past it');
    expect(
      frame * cell,
      greaterThanOrEqualTo(position.pixels),
      reason: 'the playhead\'s cell starts inside the view',
    );
    expect(
      (frame + 1) * cell,
      lessThanOrEqualTo(position.pixels + position.viewportDimension),
      reason: '↩️the view stopped at the end of the cells built before the '
          'walk, and the playhead walked on out of it',
    );
    expect(
      position.maxScrollExtent + position.viewportDimension,
      greaterThanOrEqualTo((frame + 1) * cell),
      reason: 'the cells the view stands on were built',
    );
  });

  testWidgets('🚨opened after the folded row walked past the end, the grid '
      'stands where the row stood', (tester) async {
    final session = await openTimeline(tester);
    Future<void> toggleFold() async {
      await tester.tap(
        find.byKey(const ValueKey<String>('floating-bottom-collapse')),
      );
      await tester.pumpAndSettle();
    }

    final builtWhenOpen = frameAxisOf(tester);
    final openBuiltEnd =
        builtWhenOpen.maxScrollExtent + builtWhenOpen.viewportDimension;
    await toggleFold();
    expect(
      find.byType(CollapsedRowOverlay),
      findsOneWidget,
      reason: 'premise: the panel folded',
    );
    const cell = TimelineZoomLimits.defaultPixelsPerFrame;
    while (session.currentFrameIndex * cell < openBuiltEnd + 6 * cell) {
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final kept = tester
        .widget<CollapsedRowOverlay>(find.byType(CollapsedRowOverlay))
        .frameAxisOffset!
        .value;
    expect(kept, greaterThan(0), reason: 'premise: the folded row turned');

    await toggleFold();

    expect(
      frameAxisOf(tester).pixels,
      kept,
      reason: '↩️the grid held the row\'s place to the cells it had built, '
          'and opened on a page the row had already left',
    );
  });
}
