import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★유저 (guide-sym): 「가이드툴이 선택된 상태로 **그림이 그려짐**」.
///
/// The law the rest of the canvas already keeps: THE TOOL IN HAND OWNS THE
/// CANVAS. Every non-marking tool mounts a layer that stands between the
/// pointer and the cel — the selection tools mount the interaction layer,
/// the eyedropper and the fill mount `canvas-tool-tap-layer` (opaque, and
/// its comment says why: "so no stroke starts"). The guide tool mounted a
/// layer too, and it was the one that let go: `HitTestBehavior.translucent`
/// meant a press that grabbed no handle fell straight through to the
/// stroke pipeline underneath.
///
/// ⚠️These drive the LAYER rather than the whole editor on purpose. The
/// fall-through is a property of this widget's hit test — what sits below
/// it in the panel's Stack is the artwork today and could be anything
/// tomorrow, and a test that named the artwork would be testing the panel.
void main() {
  CutGuides guides() {
    const id = GuideId('sym');
    return CutGuides(
      guides: [
        DrawingGuide(
          id: id,
          name: 'Symmetry',
          shape: SymmetryShape(
            axis: GuideAxis(
              origin: CanvasPoint(x: 100, y: 100),
              angleDegrees: 90,
            ),
          ),
        ),
      ],
      activeSymmetryId: id,
    );
  }

  /// Presses at [at] (layer-local) and reports who heard it.
  ///
  /// The shape is the panel's: something UNDER the guide layer in a Stack
  /// (the canvas), and something ABOVE both as an ancestor (the viewport
  /// gesture layer, which pans and zooms).
  Future<({bool below, bool ancestor})> press(
    WidgetTester tester,
    Offset at,
  ) async {
    var below = false;
    var ancestor = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Listener(
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (_) => ancestor = true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => below = true,
                  ),
                ),
                Positioned.fill(
                  child: GuideEditLayer(
                    guides: guides(),
                    viewport: CanvasViewport(),
                    onGuidesChanged: (_) {},
                    onGuidesCommitted: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(GuideEditLayer));
    final gesture = await tester.startGesture(origin + at);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    return (below: below, ancestor: ancestor);
  }

  // ★The premise, first: (100,100) IS the origin handle under an identity
  // viewport, and (10,10) is nowhere near one. Without this the test could
  // pass by pressing a handle it thought was empty space.
  test('the fixture presses empty canvas, not a handle', () {
    final handles = guideHandles(guides());
    expect(handles, isNotEmpty);
    expect(
      handles.any(
        (h) => (h.position.x - 100).abs() < 1 && (h.position.y - 100).abs() < 1,
      ),
      isTrue,
      reason: 'the origin handle is where the passing case aims',
    );
    expect(
      handles.every(
        (h) => (h.position.x - 10).abs() > 20 || (h.position.y - 10).abs() > 20,
      ),
      isTrue,
      reason: '(10,10) is empty canvas — the case that used to draw',
    );
  });

  testWidgets('a press on empty canvas never reaches what is underneath', (
    tester,
  ) async {
    final heard = await press(tester, const Offset(10, 10));

    expect(
      heard.below,
      isFalse,
      reason: 'with the guide tool in hand this press is not a stroke',
    );
  });

  testWidgets('a press on a handle never reaches what is underneath', (
    tester,
  ) async {
    final heard = await press(tester, const Offset(100, 100));

    expect(heard.below, isFalse);
  });

  // ⛔The other half, and the reason this is not simply "swallow
  // everything": panning and zooming the viewport must keep working while
  // the guide tool is out. Those live in an ANCESTOR
  // (`CanvasViewportGestureLayer` wraps the panel's Stack), and an opaque
  // sibling hides only what is BELOW it — never an ancestor. Written down
  // as an assertion because I had recorded the opposite as fact.
  testWidgets('the viewport above still hears every press', (tester) async {
    expect((await press(tester, const Offset(10, 10))).ancestor, isTrue);
    expect((await press(tester, const Offset(100, 100))).ancestor, isTrue);
  });
}
