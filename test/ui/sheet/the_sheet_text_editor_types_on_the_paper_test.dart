import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/sheet/sheet_text_edit_layer.dart';

/// The sheets' ONE in-place editor ([SheetTextEditLayer] — the timesheet's
/// header and memo, the conte's ACTION): a tap on a target puts a field ON
/// the printed words, at the view's zoom, in the face the sheet prints.
void main() {
  final viewport = CanvasViewport(zoom: 2, panX: 10, panY: 20);
  const style = TextStyle(fontSize: 8, color: Color(0xFF101010));

  Future<List<String>> pumpLayer(WidgetTester tester) async {
    final committed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: SheetTextEditLayer(
                  viewport: viewport,
                  fieldKey: 'field',
                  barrierKey: 'barrier',
                  targets: [
                    SheetTextTarget(
                      keyValue: 'target',
                      box: const Rect.fromLTWH(0, 0, 100, 40),
                      textRect: const Rect.fromLTWH(4, 4, 92, 32),
                      text: 'A',
                      style: style,
                      onCommitted: committed.add,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return committed;
  }

  testWidgets('the field lands on the printed words: laid out on the paper '
      'in the sheet\'s own face and size, shown at the view\'s zoom', (
    tester,
  ) async {
    await pumpLayer(tester);
    await tester.tap(find.byKey(const ValueKey<String>('target')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey<String>('field'));
    expect(field, findsOneWidget);
    // Paper (4, 4) under zoom 2 and pan (10, 20).
    expect(tester.getTopLeft(field), const Offset(18, 28));
    // Paper 92 × 32 — and room for the caret past the printed width, 3 —
    // at zoom 2.
    expect(tester.getBottomRight(field), const Offset(18 + 190, 28 + 64));
    final typed = tester.widget<TextField>(field).style!;
    expect(
      typed.fontSize,
      8,
      reason: 'set at the printed 8, as the printer sets it — the view '
          'zooms the paper, not the words',
    );
    expect(typed.color, style.color);
  });

  testWidgets('a tap away commits only what changed; Esc takes it back', (
    tester,
  ) async {
    final committed = await pumpLayer(tester);
    final target = find.byKey(const ValueKey<String>('target'));
    final field = find.byKey(const ValueKey<String>('field'));
    final barrier = find.byKey(const ValueKey<String>('barrier'));

    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(barrier, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(committed, isEmpty, reason: 'nothing typed, nothing written');

    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(committed, isEmpty, reason: 'Esc cancels');
    expect(field, findsNothing);

    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'C');
    await tester.tap(barrier, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(committed, ['C']);
  });

  // F-188: the field hides the printed words it sets again, and only them —
  // the memo band is open handwriting space round its typed note.
  testWidgets('it hides the printed words only where they were printed: a '
      'mark beside them stays on the page', (tester) async {
    const screen = ValueKey<String>('screen');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screen,
            child: Stack(
              children: [
                // The page: white, a mark at paper (80, 30) — inside the
                // words' rect, clear of the one word.
                Positioned.fill(child: CustomPaint(painter: _Page(viewport))),
                Positioned.fill(
                  child: SheetTextEditLayer(
                    viewport: viewport,
                    fieldKey: 'field',
                    barrierKey: 'barrier',
                    targets: [
                      SheetTextTarget(
                        keyValue: 'target',
                        box: const Rect.fromLTWH(0, 0, 100, 40),
                        textRect: const Rect.fromLTWH(4, 4, 92, 32),
                        text: 'A',
                        style: style,
                        onCommitted: (_) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('target')));
    await tester.pumpAndSettle();

    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(screen),
    );
    final bytes = (await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData();
      final width = image.width;
      image.dispose();
      return (data!.buffer.asUint8List(), width);
    }))!;
    // Paper (81, 31) under zoom 2 and pan (10, 20).
    const at = Offset(10 + 2 * 81, 20 + 2 * 31);
    final i = (at.dy.floor() * bytes.$2 + at.dx.floor()) * 4;
    expect(
      [bytes.$1[i], bytes.$1[i + 1], bytes.$1[i + 2]],
      [0xFF, 0, 0],
      reason: 'the mark beside the words is still on the page',
    );
  });
}

/// A page with a red mark beside where its words are printed.
class _Page extends CustomPainter {
  const _Page(this.viewport);

  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
    canvas.drawRect(
      Rect.fromLTWH(
        viewport.panX + viewport.zoom * 80,
        viewport.panY + viewport.zoom * 30,
        viewport.zoom * 4,
        viewport.zoom * 4,
      ),
      Paint()..color = const Color(0xFFFF0000),
    );
  }

  @override
  bool shouldRepaint(_Page oldDelegate) => oldDelegate.viewport != viewport;
}
