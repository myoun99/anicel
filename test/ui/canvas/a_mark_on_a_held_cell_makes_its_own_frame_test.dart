import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';

import '../../helpers/cel_text_tool_harness.dart';
import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

/// 🗣️I-113 (유저 2026-10-19): 「프레임 자동생성 버튼 동작 변경. 블록
/// 홀드구간에서 그리면 해당부분에 프레임 추가하듯이 추가하도록 동작변경.
/// 지금은 기존 같은 블록에 그림그려짐」.
///
/// With the toggle on, a held cell is a place a mark makes its own cel, as
/// the ＋ does there: the block is cut at the playhead and the mark lands
/// on the new cel — one undo for both, as on a frame with none (I-10).
/// Every door a mark asks for its cel by answers it: the drawing view's,
/// the shape tool's and the text tool's.
void main() {
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Layer row(WidgetTester tester) => sessionOf(tester).activeLayer!;

  /// Where the row's drawings start, and how long each holds.
  Map<int, int?> blocks(WidgetTester tester) => {
    for (final MapEntry(:key, :value) in row(tester).timeline.entries)
      if (value.isDrawing && !value.ghost) key: value.length,
  };

  /// The app with its one drawing held three frames, the toggle as [auto],
  /// standing on [frame].
  Future<void> open(
    WidgetTester tester, {
    required bool auto,
    required int frame,
  }) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      autoCreateFrameOnDraw: auto,
    );
    await pumpTextToolApp(tester);
    final session = sessionOf(tester);
    session.repository.replaceLayer(
      layer: row(tester).copyWith(
        timeline: {
          0: const TimelineExposure.drawing(textToolFrameId, length: 3),
        },
      ),
    );
    session.selectFrameIndex(frame);
    await pumpFrames(tester);
    expect(blocks(tester), {0: 3}, reason: '⛔fixture: one drawing, held');
  }

  Future<void> stroke(WidgetTester tester) async {
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 120));
    await pen.moveBy(const Offset(40, 30));
    await tester.pump();
    await pen.moveBy(const Offset(30, 20));
    await tester.pump();
    await pen.up();
    await pumpFrames(tester);
  }

  bool drawnAt(WidgetTester tester, int frame) =>
      sessionOf(tester).renderCaches.layerContentBoundsAt(
        row(tester),
        frame,
      ) !=
      null;

  testWidgets('🚨with the toggle on, a stroke on a held cell makes its own '
      'frame there, as the ＋ does, and draws on it — one undo puts the '
      'hold back', (tester) async {
    await open(tester, auto: true, frame: 1);

    await stroke(tester);

    expect(blocks(tester), {0: 1, 1: 2});
    expect(drawnAt(tester, 1), isTrue, reason: 'the line is on the new cel');
    expect(drawnAt(tester, 0), isFalse, reason: 'the held one is untouched');
    sessionOf(tester).historyManager.undo();
    await pumpFrames(tester);
    expect(blocks(tester), {0: 3});
    expect(row(tester).frames, hasLength(1));
    sessionOf(tester).playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('with the toggle off, the stroke goes on the held cel', (
    tester,
  ) async {
    await open(tester, auto: false, frame: 1);

    await stroke(tester);

    expect(blocks(tester), {0: 3});
    expect(drawnAt(tester, 0), isTrue);
    sessionOf(tester).playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('on the block\'s head the stroke goes on the cel there — the '
      'drawing itself, where the ＋ makes nothing', (tester) async {
    await open(tester, auto: true, frame: 0);

    await stroke(tester);

    expect(blocks(tester), {0: 3});
    expect(drawnAt(tester, 0), isTrue);
    sessionOf(tester).playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the shape tool\'s drag makes its own frame on a held cell '
      'too, and the shape lands on it', (tester) async {
    await open(tester, auto: true, frame: 1);
    await tester.tap(find.byKey(const ValueKey<String>('tool-shape-button')));
    await pumpFrames(tester);

    await stroke(tester);

    expect(blocks(tester), {0: 1, 1: 2});
    expect(drawnAt(tester, 1), isTrue);
    expect(drawnAt(tester, 0), isFalse);
    sessionOf(tester).playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the text tool\'s click makes its own cel on a held cell and '
      'begins the text on it', (tester) async {
    await open(tester, auto: true, frame: 1);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);

    await clickAt(tester, c.dx, c.dy);

    expect(blocks(tester), {0: 1, 1: 2});
    expect(celUnderTool(tester)!.key, isNot(textToolKey));
    expect(textToolOf(tester).hold, CelTextHold.letters);
  });

  testWidgets('🚨a text click that comes up before its cel is here begins on '
      'that cel, never on the held one it gave way beside', (tester) async {
    await open(tester, auto: true, frame: 1);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);

    // Down and up inside one frame: the cel the press made is not built
    // into the tree yet, and the held one still stands under the tool.
    final mouse = await tester.startGesture(
      onScreen(tester, c.dx, c.dy),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    await pumpFrames(tester);
    expect(
      textToolOf(tester).hold,
      CelTextHold.letters,
      reason: 'the text began once its cel came',
    );
    await typeText(tester, 'hi');
    await clickAt(tester, c.dx + 300, c.dy + 200);

    final made = celUnderTool(tester)!;
    expect(made.key, isNot(textToolKey), reason: '⛔전제: the new cel');
    expect(
      made.coordinator.currentSurfaceOf(made.key).texts.single.content.text,
      'hi',
    );
    expect(celOf(tester).texts, isEmpty, reason: 'the held cel has none');
  });
}
