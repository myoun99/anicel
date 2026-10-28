import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';

/// 🚨★★★A TEXT BEGUN ON A FRAME WITH NO CEL MAKES ITS CEL (R9-rest) — the
/// real app, a real mouse.
///
/// A frame with no cel is not another law for the text tool. The press asks
/// for the cel as a stroke's press does (I-10, 유저 2026-08-30: 「빈 칸에서
/// 펜다운하면 블록이 생기고 그대로 그려진다」 — under the same 「프레임 자동
/// 생성」 switch), and is then the press it would have been anywhere else: a
/// click a text that grows, a drag a box as wide as the drag. And the cel
/// and the text that made it are ONE step of history, as the stroke and its
/// cel are (「답은 추천대로」 = merged).
void main() {
  setUp(() {
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
  });
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  List<Frame> celsOfTheRow(WidgetTester tester) =>
      sessionOf(tester).activeLayer!.frames;

  List<CelText> textsUnderTool(WidgetTester tester) {
    final cel = celUnderTool(tester)!;
    return cel.coordinator.currentSurfaceOf(cel.key).texts;
  }

  /// The app standing on the frame AFTER its one drawing — no cel there —
  /// with the text tool in hand; and the pixel the tests work at.
  Future<Offset> onTheEmptyFrame(WidgetTester tester) async {
    await pumpTextToolApp(tester);
    sessionOf(tester).selectFrameIndex(1);
    await pumpFrames(tester);
    await takeTextTool(tester);
    expect(celUnderTool(tester), isNull, reason: '⛔fixture: no cel here');
    expect(celsOfTheRow(tester), hasLength(1), reason: '⛔fixture');
    return canvasPixelInView(tester);
  }

  testWidgets('🚨a click makes the cel and begins a text that grows, there '
      '— and the cel and its text are ONE step: one undo leaves the frame '
      'empty again', (tester) async {
    final c = await onTheEmptyFrame(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await clickAt(tester, c.dx, c.dy);

    expect(celsOfTheRow(tester), hasLength(2), reason: 'the press made it');
    final tool = textToolOf(tester);
    expect(tool.hold, CelTextHold.letters);
    expect(tool.session!.content.anchor, CanvasPoint(x: c.dx, y: c.dy));
    expect(tool.session!.content.wrapWidth, isNull);

    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(textsUnderTool(tester).single.content.text, 'hi');
    expect(history.undoCount, steps + 1, reason: 'the cel and its text');

    history.undo();
    await pumpFrames(tester);

    expect(celsOfTheRow(tester), hasLength(1));
  });

  testWidgets('🚨landed by another frame taken, the cel and its text are the '
      'step of the frame they were typed on: one undo there leaves it empty '
      '(I-41)', (tester) async {
    final c = await onTheEmptyFrame(tester);
    final session = sessionOf(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    session.selectFrameIndex(2);
    await pumpFrames(tester);
    session.selectFrameIndex(1);
    await pumpFrames(tester);
    expect(textsUnderTool(tester).single.content.text, 'hi', reason: '⛔');

    session.undo();
    await pumpFrames(tester);

    expect(celsOfTheRow(tester), hasLength(1), reason: 'one undo, no walk');
    expect(session.currentFrameIndex, 1);
  });

  testWidgets('a DRAG makes the cel and begins a box as wide as the drag — '
      'the press it would have been on any frame', (tester) async {
    final c = await onTheEmptyFrame(tester);

    await dragFrom(tester, Offset(c.dx + 220, c.dy + 190), c);

    expect(celsOfTheRow(tester), hasLength(2));
    final tool = textToolOf(tester);
    expect(tool.hold, CelTextHold.letters);
    // The drag is the box, its letters a quarter of their 48 in from it.
    expect(
      tool.session!.content.anchor,
      CanvasPoint(x: c.dx + 12, y: c.dy + 12),
    );
    expect(tool.session!.content.wrapWidth, 196);
    expect(tool.session!.content.minHeight, 166, reason: 'and as tall (F-317)');
  });

  testWidgets('a click that comes up before the cel is here still begins '
      'its text on it — and still as one step', (tester) async {
    final c = await onTheEmptyFrame(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    // Down and up inside one frame: the cel the press made has not been
    // built into the tree yet.
    final mouse = await tester.startGesture(
      onScreen(tester, c.dx, c.dy),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    await pumpFrames(tester);

    final tool = textToolOf(tester);
    expect(tool.hold, CelTextHold.letters);
    expect(tool.session!.content.anchor, CanvasPoint(x: c.dx, y: c.dy));

    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(textsUnderTool(tester).single.content.text, 'hi');
    expect(history.undoCount, steps + 1);
  });

  testWidgets('a DRAG that comes up before the cel is here still begins its '
      'box on it, as wide and as tall as the drag', (tester) async {
    final c = await onTheEmptyFrame(tester);

    // Down, along and up inside one frame.
    final mouse = await tester.startGesture(
      onScreen(tester, c.dx + 220, c.dy + 190),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(onScreen(tester, c.dx, c.dy));
    await mouse.up();
    expect(celUnderTool(tester), isNull, reason: '⛔fixture: not here yet');
    await pumpFrames(tester);

    final content = textToolOf(tester).session!.content;
    expect(content.anchor, CanvasPoint(x: c.dx + 12, y: c.dy + 12));
    expect(content.wrapWidth, 196);
    expect(content.minHeight, 166);
  });

  testWidgets('let go of with nothing typed, the cel stays — the press '
      'made it, as a tap of the pen does — with a step of its own', (
    tester,
  ) async {
    final c = await onTheEmptyFrame(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await clickAt(tester, c.dx, c.dy);
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(textToolOf(tester).session, isNull);
    expect(celsOfTheRow(tester), hasLength(2));
    expect(textsUnderTool(tester), isEmpty);
    expect(history.undoCount, steps + 1);

    history.undo();
    await pumpFrames(tester);

    expect(celsOfTheRow(tester), hasLength(1));
  });

  testWidgets('a text set after on the cel a text let go of empty made is '
      'a step of its own: the cel was the other press\'s', (tester) async {
    final c = await onTheEmptyFrame(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;
    await clickAt(tester, c.dx, c.dy);
    await clickAt(tester, c.dx + 300, c.dy + 200);
    expect(history.undoCount, steps + 1, reason: '⛔fixture: the cel alone');

    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(textsUnderTool(tester).single.content.text, 'hi');
    expect(history.undoCount, steps + 2);

    history.undo();
    await pumpFrames(tester);

    expect(textsUnderTool(tester), isEmpty);
    expect(celsOfTheRow(tester), hasLength(2), reason: 'the cel stays');
  });

  testWidgets('⛔with something else filed between the cel and its text, '
      'they stay apart: one undo takes the text back and nothing of '
      'anybody else\'s', (tester) async {
    final c = await onTheEmptyFrame(tester);
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;
    final between = _Noted();

    await clickAt(tester, c.dx, c.dy);
    history.execute(between);
    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    expect(history.undoCount, steps + 3);

    history.undo();
    await pumpFrames(tester);

    expect(textsUnderTool(tester), isEmpty);
    expect(celsOfTheRow(tester), hasLength(2));
    expect(between.undone, isFalse);
  });

  testWidgets('⛔with 「프레임 자동 생성」 off the press is refused as a '
      'stroke\'s is: no cel, and no text', (tester) async {
    final c = await onTheEmptyFrame(tester);
    AppInput.settings.value = const AppInputSettings();

    await clickAt(tester, c.dx, c.dy);

    expect(celsOfTheRow(tester), hasLength(1));
    expect(textToolOf(tester).session, isNull);
    expect(celUnderTool(tester), isNull);
  });
}

/// A step of somebody else's, filed in between.
class _Noted implements Command {
  bool undone = false;

  @override
  String get description => 'Noted';

  @override
  void execute() => undone = false;

  @override
  void undo() => undone = true;
}
