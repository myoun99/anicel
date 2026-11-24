import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

/// Card the-input-inspector-climbs-and-cuts-its-lines (유저 2026-11-24
/// 「입력인스펙터는 게다가 줄이 매번올라가서 보이지도않고 오른쪽부분 잘리고」), in
/// the narrowest window it is read on: a Galaxy Tab, 1579 logical pixels
/// wide.
const _card = ValueKey<String>('input-inspector-card');
const _panel = ValueKey<String>('input-inspector-panel');

void main() {
  tearDown(InputInspector.reset);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1579, 987));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    InputInspector.visible.value = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InputInspectorHost(child: SizedBox.expand())),
      ),
    );
  }

  /// Every kind of line the panel writes, each as long as it gets.
  void sayEverything() {
    InputInspector.record(
      const PointerMoveEvent(
        kind: PointerDeviceKind.invertedStylus,
        pointer: 123456,
        pressure: 0.73,
        pressureMax: 4,
        tilt: 1.23,
        orientation: -3.14,
        buttons: 31,
        position: Offset(1578, 986),
      ),
    );
    for (final kind in [
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
    ]) {
      InputInspector.record(PointerDownEvent(kind: kind));
      InputInspector.record(PointerHoverEvent(kind: kind));
      InputInspector.record(PointerUpEvent(kind: kind));
    }
    InputInspector.echoes = 123456;
    InputInspector.arrivals = 1234567;
    for (var i = 0; i < 6; i += 1) {
      InputInspector.note(
        'probe$i ${List.filled(12, 'word$i').join(' ')} '
        '${'x' * 40}',
      );
    }
    for (var i = 0; i < 3; i += 1) {
      InputInspector.pin('grid$i', 'grid$i frac=(0.250, 0.000) ${'y' * 60}');
    }
  }

  testWidgets('🎯as lines come, the card keeps its top edge and its size', (
    tester,
  ) async {
    await pumpHost(tester);
    final card = tester.getRect(find.byKey(_card));
    final panel = tester.getRect(find.byKey(_panel));

    sayEverything();
    await tester.pump();

    expect(tester.getRect(find.byKey(_card)), card);
    expect(tester.getRect(find.byKey(_panel)), panel);
    expect(card.right, lessThanOrEqualTo(1579), reason: 'on the screen');
  });

  testWidgets('🎯no line the panel writes is cut — the longest wraps inside '
      'it', (tester) async {
    await pumpHost(tester);
    sayEverything();
    await tester.pump();

    final panel = tester.getRect(find.byKey(_panel));
    final lines = find
        .descendant(of: find.byKey(_panel), matching: find.byType(RichText))
        .evaluate()
        .map((element) => element.renderObject! as RenderParagraph)
        .toList();
    expect(lines.length, greaterThan(20), reason: 'every line is laid');
    for (final line in lines) {
      final text = line.text.toPlainText();
      expect(line.didExceedMaxLines, isFalse, reason: text);
      final box = line.localToGlobal(Offset.zero) & line.size;
      expect(box.left, greaterThanOrEqualTo(panel.left - 0.5), reason: text);
      expect(box.right, lessThanOrEqualTo(panel.right + 0.5), reason: text);
      // Its words laid in its box: no word is wider than the panel.
      for (final word in line.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      )) {
        expect(
          word.right,
          lessThanOrEqualTo(line.size.width + 0.5),
          reason: text,
        );
      }
    }
  });
}
