import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';

/// 🗣️관제 2026-11-20 (card opening-a-transform-box-holds-the-ui-over-
/// half-a-second, ⓑ): the host's ink bounds walk every cel the box frames
/// — over S5_BA cut 352's 62 rows, a walk the box at rest and its pill
/// each asked of their own, a build. A build asks once and hands both
/// what it answered — and a build that has neither asks nothing.
void main() {
  const canvasSize = CanvasSize(width: 400, height: 300);
  const pill = ValueKey<String>('selection-confirm-pill');

  /// The layer with [tool] in hand, nothing selected, over a picture at
  /// (40..240, 40..140) — and how many times it has asked for that ink.
  Future<int Function()> pumpLayer(
    WidgetTester tester,
    CanvasSelectionTool tool,
  ) async {
    final commands = CanvasSelectionCommands();
    var asked = 0;
    Widget layer() => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: CanvasSelectionLayer(
              tool: tool,
              viewport: CanvasViewport(),
              pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
              frameToken: 'frame',
              selectionCommands: commands,
              contentBoundsProvider: () {
                asked += 1;
                return (
                  left: 40,
                  top: 40,
                  rightExclusive: 240,
                  bottomExclusive: 140,
                );
              },
              onLiftRequested: (_) => null,
              onLiftConfirmed: (_, _, _) {},
              onLiftReverted: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(layer());
    await tester.pump();
    final before = asked;
    await tester.pumpWidget(layer());
    return () => asked - before;
  }

  testWidgets('the Move tool\'s box at rest and its pill are answered by '
      'one ask of the host\'s ink a build', (tester) async {
    final asked = await pumpLayer(tester, CanvasSelectionTool.move);
    expect(
      find.byKey(pill),
      findsOneWidget,
      reason: '⛔premise: the pill stands under the box at rest',
    );
    expect(asked(), 1);
  });

  testWidgets('a build with no box at rest asks the host nothing', (
    tester,
  ) async {
    final asked = await pumpLayer(tester, CanvasSelectionTool.select);
    expect(find.byKey(pill), findsNothing, reason: '⛔premise: no box');
    expect(asked(), 0);
  });
}
