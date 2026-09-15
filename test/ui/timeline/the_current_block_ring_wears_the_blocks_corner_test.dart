import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_selected_exposure_outline.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// F-79 — the ring around the current block wears the block's own corner.
///
/// 유저 2026-09-11: 「현재 프레임 블록을 표시하는 블록의 외곽 라인. 타임라인
/// 줌이 100%일땐 외곽 강조실루엣이랑 블록의 실루엣이랑 동일한데 줌이 33%등
/// 작아질수록 점점 어긋남. 강조 실루엣이 더 모서리가 동그람」.
///
/// A block's corner is 6px, no larger than half the cell it rounds — the block
/// tiles clamp every cell's rounded rect that way. The ring wraps the whole run,
/// so nothing clamped it: at 8px cells (33%) the blocks rounded to 4 and the
/// ring stayed 6.
void main() {
  /// The ring's corner over a three-frame block on the default project's
  /// drawing row, at [pixelsPerFrame].
  Future<Radius> ringCornerAt(
    WidgetTester tester,
    double pixelsPerFrame,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.exposureVerbs.setCommaForSelectionOrCurrent(3);
    session.selectFrameIndex(1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineTabHost(
            session: session,
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: pixelsPerFrame,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final outline = find.byKey(
      ValueKey<String>(
        'timeline-selected-exposure-range-outline-'
        '${session.activeLayerId!.value}',
      ),
    );
    expect(outline, findsOneWidget, reason: 'fixture: the ring is drawn');
    final ring = tester.widget<TimelineSelectionRing>(
      find.descendant(of: outline, matching: find.byType(TimelineSelectionRing)),
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return ring.borderRadius.topLeft;
  }

  testWidgets('at 33% (8px cells) the ring rounds like the blocks: 4px', (
    tester,
  ) async {
    expect(await ringCornerAt(tester, 8), const Radius.circular(4));
  });

  testWidgets('at 100% the ring and the blocks agree on the full 6px', (
    tester,
  ) async {
    expect(await ringCornerAt(tester, 24), const Radius.circular(6));
  });
}
