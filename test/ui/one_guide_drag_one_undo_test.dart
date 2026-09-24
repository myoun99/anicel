import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// 🚨★★★ONE GUIDE DRAG IS ONE UNDO (guide-slider-one-undo).
///
/// 유저 (guide-sym): 「대칭자나 퍼스자 등 해당 자에 대한 위치이동 등 **편집도
/// 전부 언두 기록**」. 🧪Measured before touching anything, because reading
/// said the opposite: every guide write already goes through
/// `SetCutGuidesCommand` and undo already restores it. What it did NOT do is
/// stop at one — ONE drag of the settings panel's line-count slider pushed
/// **eleven** entries, so undo took the drag apart a sample at a time.
///
/// ★The law is the one the guide EDIT LAYER already kept and the opacity
/// bars keep: a drag PREVIEWS and a release COMMITS. The edit layer's preview
/// lived in the canvas area's own State, so the panel — another subtree — had
/// nowhere to preview to and committed instead. The preview is the cut
/// verbs' now, and there is one of it.
void main() {
  const id = GuideId('g');

  CutGuides oneSymmetry({int lineCount = 2, CanvasPoint? origin}) => CutGuides(
    guides: [
      DrawingGuide(
        id: id,
        name: '대칭 1',
        shape: SymmetryShape(
          axis: GuideAxis(
            origin: origin ?? CanvasPoint(x: 10, y: 10),
            angleDegrees: 0,
          ),
          lineCount: lineCount,
        ),
      ),
    ],
    activeSymmetryId: id,
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  /// The whole app with the guide tool in hand; its session.
  Future<EditorSessionManager> guideToolApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final s = workspace.session;
    // The default project has no cel at the playhead, and the canvas the
    // guide layers ride on is the one that draws a cel — and it mounts them
    // only while the cut HAS a guide.
    s.createDrawingAtCurrentFrame();
    s.cutVerbs.setActiveCutGuides(oneSymmetry());
    s.selectedGuideId = id;
    await tester.pumpAndSettle();
    final tool = workspace.brushTool!;
    tool.value = tool.value.copyWith(tool: CanvasTool.guide);
    await tester.pumpAndSettle();
    expect(
      find.byType(GuideEditLayer),
      findsOneWidget,
      reason: '⛔전제: 가이드 툴을 들었다',
    );
    return s;
  }

  testWidgets('one drag of the settings panel\'s bar is ONE undo — and the '
      'canvas follows every sample of it', (tester) async {
    final s = await guideToolApp(tester);
    final verbs = s.cutVerbs;
    // The tool settings group ships closed on the left rail (slot 2).
    final group = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$group')));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey<String>('guide-line-count'));
    expect(slider, findsOneWidget, reason: '⛔전제: 그 가이드의 설정이 떴다');
    final entries = s.historyManager.undoCount;

    final box = tester.getRect(slider);
    final gesture = await tester.startGesture(
      Offset(box.left + 8, box.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 10; i += 1) {
      await gesture.moveTo(
        Offset(box.left + 8 + i * (box.width - 16) / 10, box.center.dy),
      );
      await tester.pump();
      expect(
        verbs.activeCutGuidesForDisplay,
        isNot(verbs.activeCutGuides),
        reason: 'sample $i shows without being written',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      verbs.activeCutGuidesForDisplay,
      verbs.activeCutGuides,
      reason: 'the release lands the preview and lets it go',
    );
    expect(
      s.historyManager.undoCount,
      entries + 1,
      reason: '⛔ONE for the drag — eleven is what this file was written '
          'against',
    );

    s.undo();
    expect(
      verbs.activeCutGuides,
      oneSymmetry(),
      reason: '「편집도 전부 언두 기록」 — one undo puts the guide back',
    );
  });

  testWidgets('a HANDLE drag on the canvas is one undo too — the same preview, '
      'and the overlay draws every sample of it', (tester) async {
    final s = await guideToolApp(tester);
    final verbs = s.cutVerbs;
    final editLayer = find.byType(GuideEditLayer);

    // The axis origin — a handle — under a point the pen can reach.
    final press = visibleCanvasPoint(tester);
    final local = press - tester.getTopLeft(editLayer);
    final origin = tester
        .widget<GuideEditLayer>(editLayer)
        .viewport
        .viewportToCanvas(ViewportPoint(x: local.dx, y: local.dy));
    verbs.setActiveCutGuides(oneSymmetry(origin: origin));
    await tester.pumpAndSettle();
    final entries = s.historyManager.undoCount;

    GuideOverlayPainter overlay() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GuideOverlayPainter>()
        .single;

    final gesture = await tester.startGesture(
      press,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 8; i += 1) {
      await gesture.moveTo(press + Offset(6.0 * i, 0));
      await tester.pump();
      expect(
        verbs.activeCutGuidesForDisplay,
        isNot(verbs.activeCutGuides),
        reason: 'sample $i shows without being written',
      );
      expect(
        overlay().guides,
        verbs.activeCutGuidesForDisplay,
        reason: 'the overlay draws the drag in flight',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(s.historyManager.undoCount, entries + 1, reason: '⛔ONE');
    expect(verbs.activeCutGuidesForDisplay, verbs.activeCutGuides);
  });

  test('⛔a drag that ends where it began still lets go of the preview', () {
    final s = session();
    final verbs = s.cutVerbs;
    verbs
      ..setActiveCutGuides(oneSymmetry())
      ..previewActiveCutGuides(oneSymmetry(lineCount: 8));
    expect(verbs.activeCutGuidesForDisplay, isNot(verbs.activeCutGuides));
    final entries = s.historyManager.undoCount;

    // The same value the cut already holds: nothing is written, and the
    // preview must still go — or the canvas stays pinned to a picture
    // nothing will ever replace.
    verbs.setActiveCutGuides(oneSymmetry());
    expect(verbs.activeCutGuidesForDisplay, verbs.activeCutGuides);
    expect(s.historyManager.undoCount, entries, reason: 'nothing written');
  });

  test('⛔what the BRUSH snaps to is the written guides, never the preview',
      () {
    final s = session();
    final verbs = s.cutVerbs;
    verbs
      ..setActiveCutGuides(oneSymmetry())
      ..previewActiveCutGuides(
        oneSymmetry(origin: CanvasPoint(x: 500, y: 10)),
      );
    expect(
      verbs.activeCutGuides,
      oneSymmetry(),
      reason: 'two questions, two getters — a drag in flight is not saved '
          'and not snapped to',
    );
  });
}
