// THE CANVAS AREA STACKS ITS OVERLAYS ONLY WHEN THERE IS SOMETHING TO SHOW:
// A GUIDE PUTS THE GUIDE OVERLAY UP, A DIMMED TRACK PUTS THE FADE WASH UP,
// AND NEITHER IS THERE BEFORE.
//
// Two mutants of the interactive-canvas build cut (2026-09-03) survived
// every test that pumps the editor: the overlay builder replaced by null,
// and the fade-wash gate widened to `opacity <= 1` (a wash on every cut,
// at alpha zero). Nothing looked for the overlays themselves; these pins do.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
}

Finder _guideOverlays() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is GuideOverlayPainter,
);

Finder _fadeWashes() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter.runtimeType.toString() == '_CutFadeWashPainter',
);

void main() {
  testWidgets('a guide puts the guide overlay over the canvas', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_guideOverlays(), findsNothing, reason: 'no guides yet');

    session.cutVerbs.setActiveCutGuides(
      CutGuides(
        guides: [
          DrawingGuide(
            id: const GuideId('g'),
            name: 'Mirror',
            shape: SymmetryShape(
              axis: GuideAxis(
                origin: CanvasPoint(x: 100, y: 100),
                angleDegrees: 0,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(_guideOverlays(), findsOneWidget);
  });

  testWidgets('a dimmed track puts the fade wash over the canvas', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_fadeWashes(), findsNothing, reason: 'full opacity: no wash');

    final trackId = session.repository.requireProject().tracks.first.id;
    session.commitTrackOpacity(trackId, 0.5);
    await tester.pumpAndSettle();
    expect(_fadeWashes(), findsOneWidget);
  });
}
