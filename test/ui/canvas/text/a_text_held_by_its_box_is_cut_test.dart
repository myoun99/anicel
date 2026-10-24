import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart' show CelTextHold;
import 'package:anicel/src/ui/session/text_clipboard.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/key_chords.dart';

/// THE SHARED PILL'S 잘라내기 OF A TEXT (the-pill-cut-skips-text-and-keys,
/// in I-123's family): 복사 and 잘라내기 are ONE pair (「복사=원본 남기고 클립
/// 저장 · 잘라내기=원본 지우고 클립 저장」), so the text held by its box — the
/// thing in hand, which the copy takes ahead of every rung (I-101) — is
/// what the cut takes: off its cel, into the hand. ↩️The cut asked the frame
/// board alone, and lifted the block of the cel the text stood on.
///
/// The collaborator the cut lives in — named so the mutation runner runs
/// this file for it.
TextClipboard textClipboardOf(WidgetTester tester) =>
    sessionOf(tester).textClipboard;

void main() {
  /// 'hi' typed at the middle of the canvas and held by its BOX.
  Future<void> hiHeldByItsBox(WidgetTester tester, {Project? project}) async {
    await pumpTextToolApp(
      tester,
      project: project ?? textToolProject(drawings: 2),
    );
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(textToolOf(tester).hold, CelTextHold.box, reason: '⛔fixture');
  }

  TimelineToolbarPanelContext pill(WidgetTester tester) =>
      TimelineToolbarPanelContext(sessionOf(tester));

  testWidgets('🎯Ctrl+X takes the text off its cel and into the hand — the '
      'drawing stays — and Ctrl+V on another frame sets it there as it was '
      'shown', (tester) async {
    await hiHeldByItsBox(tester);
    final copied = celOf(tester).texts.single;
    final session = sessionOf(tester);
    final row = session.activeLayer!.timeline;

    expect(pill(tester).canCutRun, isTrue);
    await pressCtrl(tester, LogicalKeyboardKey.keyX);
    await pumpFrames(tester);

    expect(celOf(tester).texts, isEmpty, reason: 'off its cel');
    expect(session.activeLayer!.timeline, row, reason: 'the block stays');
    expect(textClipboardOf(tester).holdsText, isTrue);
    expect(session.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);

    session.selectFrameIndex(1);
    await pumpFrames(tester);
    await pressCtrl(tester, LogicalKeyboardKey.keyV);
    await pumpFrames(tester);

    final pasted = celOf(tester, textToolSecondKey).texts.single;
    expect(pasted.content, copied.content);
    expect(pasted.plate, copied.plate);
  });

  testWidgets('the pill\'s button cuts it the same, and one undo puts it '
      'back on its cel', (tester) async {
    await hiHeldByItsBox(tester);
    final copied = celOf(tester).texts.single;

    pill(tester).cutPress!.call();
    await pumpFrames(tester);
    expect(celOf(tester).texts, isEmpty);

    sessionOf(tester).undo();
    await pumpFrames(tester);
    expect(celOf(tester).texts.single.content, copied.content);
  });

  testWidgets('while its letters are typed into, the cut is not the '
      'text\'s — as the copy is not', (tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    expect(textToolOf(tester).hold, CelTextHold.letters, reason: '⛔전제');

    pill(tester).cutPress?.call();

    expect(textClipboardOf(tester).holdsText, isFalse);
  });
}
