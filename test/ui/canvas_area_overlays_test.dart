// THE CANVAS AREA STACKS ITS OVERLAYS ONLY WHEN THERE IS SOMETHING TO SHOW:
// A GUIDE PUTS THE GUIDE OVERLAY UP, A CUT AN O.L THINS PUTS THE FADE WASH
// UP, AND NEITHER IS THERE BEFORE.
//
// Two mutants of the interactive-canvas build cut (2026-09-03) survived
// every test that pumps the editor: the overlay builder replaced by null,
// and the fade-wash gate widened to `opacity <= 1` (a wash on every cut,
// at alpha zero). Nothing looked for the overlays themselves; these pins do.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart' show backdropShareUnder;
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

  // ↩️A dimmed TRACK put it up: the V row's static opacity was the other
  // thing that thinned a cut, until it left with its bar (I-73, 10-08).
  testWidgets('a cut an O.L thins puts the fade wash over the canvas', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_fadeWashes(), findsNothing, reason: 'no transition: no wash');

    // An O.L over the cut's last six frames, and the playhead inside it.
    final duration = session.activeCutOrNull!.duration;
    session.transitions.updateTransitionInstructions({
      duration - 6: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    session.selectFrameIndex(duration - 3);
    await tester.pumpAndSettle();
    expect(_fadeWashes(), findsOneWidget);
  });

  // How strong that wash is: what the live cut and the O.L's other cuts
  // leave of the frame is the backdrop's (F-227). ↩️Each share was its ramp
  // times its track's opacity until the V row lost it (I-73), which is when
  // the sum first stood with nothing pinning it.
  test('the wash is what the live cut and its partners leave', () {
    expect(
      backdropShareUnder(0.75, const []),
      0.25,
      reason: 'no partner: 1 − fade, the wash as it always was',
    );
    expect(
      backdropShareUnder(0.5, const [0.5]),
      0,
      reason: 'an O.L\'s two halves are the whole frame',
    );
    expect(
      backdropShareUnder(0.1, const [0.25, 0.5]),
      closeTo(0.6, 1e-9),
      reason:
          'the partners\' shares ADD (0.75): for the live cut to keep 0.1 '
          'of the frame out of the quarter they leave, the wash under them '
          'is 0.6',
    );
    expect(backdropShareUnder(0.5, const [1]), 0, reason: 'nothing is left');
  });
}
