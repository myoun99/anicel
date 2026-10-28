@Tags(['gpu'])
library;

import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;
import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/settle_async.dart';

/// F-473's family: what floats over a frame while the pen is up is no
/// picture of the frame's (유저 2026-10-26 「그럼 비슷하게 프리뷰쓰는거 다른
/// 도구들에도 있을텐데 그 도구들도 법 통일해줘」).
void main() {
  Future<void> settle(WidgetTester tester) =>
      lendBothClocks(tester, rounds: 12);

  /// What the window shows over [rect], RGBA row after row.
  Future<Uint8List> shot(WidgetTester tester, Rect rect) async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      final image = await layer.toImage(rect);
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// How many pixels [a] and [b] part at.
  int apart(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i += 4) {
      for (var c = 0; c < 4; c += 1) {
        if ((a[i + c] - b[i + c]).abs() > 2) {
          count += 1;
          break;
        }
      }
    }
    return count;
  }

  testWidgets('a text in hand the frame changed under lands on its cel, and '
      'undone, leaves nothing where it floated', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTextToolApp(tester, project: textToolProject(drawings: 2));
    await takeTextTool(tester);
    await settle(tester);
    final c = canvasPixelInView(tester);
    final around = Rect.fromLTWH(
      onScreen(tester, c.dx, c.dy).dx - 40,
      onScreen(tester, c.dx, c.dy).dy - 40,
      240,
      160,
    );
    final before = await shot(tester, around);

    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await settle(tester);
    expect(
      apart(before, await shot(tester, around)),
      isNonZero,
      reason: 'LIVENESS: the text in hand shows',
    );
    sessionOf(tester).selectFrameIndex(1);
    await settle(tester);
    expect(
      celOf(tester).texts.single.content.text,
      'hi',
      reason: '⛔premise: the frame changed, so the text landed on its cel',
    );
    sessionOf(tester).selectFrameIndex(0);
    await settle(tester);
    // An undo whose edit lies where the session does not stand walks there
    // first (`EditorSessionManager.undo`).
    for (var press = 0; press < 2 && celOf(tester).texts.isNotEmpty; press++) {
      sessionOf(tester).undo();
      await settle(tester);
    }
    sessionOf(tester).selectFrameIndex(0);
    await settle(tester);
    expect(
      celOf(tester).texts,
      isEmpty,
      reason: '⛔premise: undone, the cel holds no text',
    );
    expect(
      apart(before, await shot(tester, around)),
      0,
      reason: 'undone: nothing of the text stays where it floated',
    );
  }, skip: noFlutterGpu != null);
}
