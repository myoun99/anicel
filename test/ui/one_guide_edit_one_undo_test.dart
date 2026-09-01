import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★유저 (guide-sym): 「대칭자나 퍼스자 등 해당 자에 대한 **위치이동 등
/// 편집도 전부 언두 기록**」.
///
/// 🧪Measured before touching anything, because reading said the opposite:
/// every guide write already goes through `SetCutGuidesCommand` and undo
/// already restores. What it does NOT do is stop at one — ONE drag of the
/// line-count slider pushed **eleven** entries, so undo took the drag apart
/// a pixel at a time. That is the defect behind the report.
///
/// ★The law is the one the guide EDIT LAYER already kept: a drag PREVIEWS
/// and a release COMMITS. The preview used to live in `editor_canvas_area`'s
/// own State, which is why the settings panel — a different subtree — had
/// nowhere to preview to and committed instead. It is the session's now, so
/// there is one of it.
void main() {
  const id = GuideId('g');

  CutGuides oneSymmetry({int lineCount = 2}) => CutGuides(
    guides: [
      DrawingGuide(
        id: id,
        name: '대칭 1',
        shape: SymmetryShape(
          axis: GuideAxis(origin: CanvasPoint(x: 10, y: 10), angleDegrees: 0),
          lineCount: lineCount,
        ),
      ),
    ],
    activeSymmetryId: id,
  );

  EditorSessionManager freshSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  int undoDepth(EditorSessionManager session) {
    var depth = 0;
    while (session.historyManager.canUndo) {
      session.historyManager.undo();
      depth += 1;
    }
    return depth;
  }

  testWidgets('one slider drag is ONE undo', (tester) async {
    final session = freshSession();
    session.setActiveCutGuides(oneSymmetry());
    final before = undoDepth(session);
    // Put it back and start counting from a known floor.
    session.setActiveCutGuides(oneSymmetry());
    expect(before, 1, reason: 'the premise: the setup itself is one entry');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => GuideSettings(
              guides: session.activeCutGuidesForDisplay,
              selectedGuideId: id,
              onGuidesCommitted: session.setActiveCutGuides,
              onGuidesPreview: session.previewCutGuides,
            ),
          ),
        ),
      ),
    );

    final slider = find.byKey(const ValueKey<String>('guide-line-count'));
    expect(slider, findsOneWidget);
    final box = tester.getRect(slider);
    final gesture = await tester.startGesture(
      Offset(box.left + 8, box.center.dy),
    );
    for (var i = 1; i <= 10; i += 1) {
      await gesture.moveTo(
        Offset(box.left + 8 + i * (box.width - 16) / 10, box.center.dy),
      );
      await tester.pump();
      // ⚠️The canvas still follows every sample — that is what the preview
      // buys, and losing it would be the price nobody asked to pay.
      expect(
        session.activeCutGuidesForDisplay,
        isNot(session.activeCutGuides),
        reason: 'sample $i shows, without being written',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      session.activeCutGuidesForDisplay,
      session.activeCutGuides,
      reason: 'the release lands the preview and clears it',
    );
    expect(
      undoDepth(session),
      2,
      reason:
          '⛔ONE for the drag, one for the setup above it. Eleven is what '
          'this file was written against',
    );
  });

  testWidgets('a handle drag is one undo, and undo puts it back', (
    tester,
  ) async {
    final session = freshSession();
    session.setActiveCutGuides(oneSymmetry());
    final origin = oneSymmetry().guides.single.shape;

    // The edit layer's own pair, called the way it calls them.
    for (var i = 1; i <= 5; i += 1) {
      session.previewCutGuides(
        CutGuides(
          guides: [
            DrawingGuide(
              id: id,
              name: '대칭 1',
              shape: SymmetryShape(
                axis: GuideAxis(
                  origin: CanvasPoint(x: 10.0 + i, y: 10),
                  angleDegrees: 0,
                ),
              ),
            ),
          ],
          activeSymmetryId: id,
        ),
      );
    }
    expect(
      session.activeCutGuidesForDisplay,
      isNot(session.activeCutGuides),
      reason: 'the premise: the drag really was showing something',
    );

    session.setActiveCutGuides(session.activeCutGuidesForDisplay);
    expect(undoDepth(session), 2, reason: 'setup + the drag, and nothing else');

    // ★And the round trip the user actually asked about.
    session.historyManager.redo();
    session.historyManager.redo();
    session.historyManager.undo();
    expect(
      session.activeCutGuides.guides.single.shape,
      origin,
      reason: '「편집도 전부 언두 기록」 — one undo puts the guide back',
    );
  });

  test('⛔a preview nobody released is dropped, not left on screen', () {
    final session = freshSession();
    session.setActiveCutGuides(oneSymmetry());
    session.previewCutGuides(oneSymmetry(lineCount: 8));
    expect(session.activeCutGuidesForDisplay, isNot(session.activeCutGuides));

    session.forgetGuidePreview();
    expect(
      session.activeCutGuidesForDisplay,
      session.activeCutGuides,
      reason: 'a cancelled drag leaves the canvas where it was',
    );
  });

  test('⛔a drag that ends where it began still clears the preview', () {
    final session = freshSession();
    session.setActiveCutGuides(oneSymmetry());
    session.previewCutGuides(oneSymmetry(lineCount: 8));

    // The same value the cut already holds: `setActiveCutGuides` returns
    // early, and it must still let go of the preview — otherwise the canvas
    // is pinned to a preview nothing will ever replace.
    session.setActiveCutGuides(oneSymmetry());
    expect(session.activeCutGuidesForDisplay, session.activeCutGuides);
  });
}
