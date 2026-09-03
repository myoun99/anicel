// THE DOCK'S DROP WELL BRIGHTENS UNDER THE HAND.
//
// A survivor of the mutation campaign (2026-09-04, the drop zone's
// footprint/well split): the well built with `hovered` forced false. The
// zone still reserved its footprint and still accepted the drop, so every
// existing test stayed green — none of them looks at what the well DRAWS
// while a tab is over it, which is the whole signal that says "let go
// here".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

void main() {
  const wellKey = ValueKey<String>('editor-dock-drop-rail-probe');
  const payload = EditorPanelTabDragData(tabId: 't', fromGroupId: 'elsewhere');

  /// The well's border side right now — the hover tell.
  BorderSide wellBorder(WidgetTester tester) {
    final container = tester.widget<Container>(find.byKey(wellKey));
    final shape = (container.decoration! as ShapeDecoration).shape;
    return (shape as OutlinedBorder).side;
  }

  testWidgets('a tab held over the well deepens its border; away from it '
      'the well stays quiet', (tester) async {
    final dragging = ValueNotifier<EditorPanelTabDragData?>(payload);
    addTearDown(dragging.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Draggable<EditorPanelTabDragData>(
                data: payload,
                feedback: SizedBox(width: 20, height: 20),
                // A bare SizedBox is not hit-testable — the gesture would
                // never reach the Draggable and no drag would start.
                child: ColoredBox(
                  color: Color(0xFF888888),
                  child: SizedBox(width: 60, height: 60),
                ),
              ),
              const SizedBox(width: 200),
              SizedBox(
                height: 200,
                child: EditorDockDropZone(
                  dockId: 'probe',
                  axis: Axis.vertical,
                  draggingTab: dragging,
                  canAcceptTab: (_) => true,
                  onDropped: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final quiet = wellBorder(tester);

    // Lift the tab and carry it onto the well.
    final from = tester.getCenter(
      find.byType(Draggable<EditorPanelTabDragData>),
    );
    final onto = tester.getCenter(find.byKey(wellKey));
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveTo(onto);
    await tester.pump();

    final held = wellBorder(tester);
    expect(
      held.width,
      greaterThan(quiet.width),
      reason:
          'the well under the hand is the "let go here" signal — a well '
          'built with hovered always false draws the resting state through '
          'the whole drag',
    );
    expect(
      held.color,
      isNot(quiet.color),
      reason: 'and it deepens its colour with it',
    );

    // Carrying it away puts the well back to resting.
    await gesture.moveTo(from);
    await tester.pump();
    expect(wellBorder(tester).width, quiet.width);
    await gesture.up();
    await tester.pump();
  });
}
