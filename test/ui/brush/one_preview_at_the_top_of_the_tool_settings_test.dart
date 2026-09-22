import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_stroke_live_preview.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';

import '../../helpers/library_source.dart';

/// 🚨★★★I-33 — **프리뷰는 도구 설정의 맨 위, 한 자리.**
///
/// > 「도구 설정 패널에 **프리뷰 항목 신설**. 잘라내기도구의 스탬프도 이거
/// > 재사용? 그쪽을 재사용해도되고 아무튼 **통일하고 필요없어지는 잔재제거**.
/// > 프리뷰 항목은 일단 **스탬프도구,브러시/지우개** 의 도구설정에서 비추게.
/// > 위치는 **도구 설정의 맨 위**. **프리뷰라는 텍스트는 필요없음**. 세련되게.
/// > **브러시/지우개의 프리뷰는 스트로크를 보여줌. 설정하는거에 맞춰서 실시간
/// > 갱신되는**. 도구 라이브러리패널도 그렇게 되있는거 맞나? 아무튼 확인하고
/// > **법 최대한 통일**」 (유저 2026-09-16)
///
/// 🔬**확인한 것**(착수 0수): 도구 라이브러리 패널은 브러시/지우개일 때 프리셋
/// 목록을 그대로 보여 주고, 각 행의 스트로크는 **그 프리셋의 설정**을 그린다 —
/// 손에 든 브러시는 프리셋이 아니므로 **거기는 실시간으로 안 바뀐다.** 그래서
/// 「실시간 갱신」은 이 패널의 새 일이고, 목록의 위젯을 그대로 쓸 수 없다.
CutPiece _piece() => CutPiece(
  image: BrushStampImage(
    id: 'p',
    width: 40,
    height: 24,
    rgba: Uint8List(40 * 24 * 4),
  ),
  originLeft: 5,
  originTop: 6,
);

Future<void> _pump(
  WidgetTester tester, {
  required CanvasTool tool,
  CutPieceSlot? slot,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 320,
        height: 720,
        child: ToolSettingsPanel(
          state: BrushToolState.defaults.copyWith(tool: tool),
          onChanged: (_) {},
          fillOptions: const FloodFillOptions(),
          onFillOptionsChanged: (_) {},
          selectionMaskOptions: SelectionMaskOptions.none,
          eyedropperSource: CanvasColorSampleSource.display,
          cutPieceSlot: slot,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('🚨the brush previews its own STROKE, at the top of the panel', (
    tester,
  ) async {
    await _pump(tester, tool: CanvasTool.brush);

    final slot = find.byKey(ToolSettingsPreview.slotKey);
    expect(slot, findsOneWidget, reason: '「도구 설정 패널에 프리뷰 항목 신설」');
    expect(
      find.descendant(of: slot, matching: find.byType(BrushStrokeLivePreview)),
      findsOneWidget,
      reason: '「브러시/지우개의 프리뷰는 스트로크를 보여줌」',
    );
    expect(
      tester.getRect(slot).top,
      lessThan(tester.getRect(find.byType(ToolSettingsPanel)).center.dy),
      reason: '「위치는 도구 설정의 맨 위」',
    );
  });

  testWidgets('🚨and so does the eraser', (tester) async {
    await _pump(tester, tool: CanvasTool.eraser);
    expect(
      find.descendant(
        of: find.byKey(ToolSettingsPreview.slotKey),
        matching: find.byType(BrushStrokeLivePreview),
      ),
      findsOneWidget,
    );
  });

  testWidgets('🚨the stamp shows the held piece in THE SAME slot', (
    tester,
  ) async {
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    slot.hold(_piece());
    await _pump(tester, tool: CanvasTool.cutStamp, slot: slot);

    expect(
      find.descendant(
        of: find.byKey(ToolSettingsPreview.slotKey),
        matching: find.byType(CutPiecePreview),
      ),
      findsOneWidget,
      reason: '「잘라내기도구의 스탬프도 이거 재사용 … 아무튼 통일」',
    );
    expect(
      find.byType(CutPiecePreview),
      findsOneWidget,
      reason:
          '⛔**잔재제거** — 섹션 안에 제 사본을 또 그리면 같은 그림이 한 화면에 '
          '둘이 된다',
    );
  });

  testWidgets('⛔no word says "preview", and a tool with nothing to show has '
      'no slot at all', (tester) async {
    await _pump(tester, tool: CanvasTool.brush);
    expect(
      find.textContaining('review', findRichText: true),
      findsNothing,
      reason: '유저: 「프리뷰라는 텍스트는 필요없음」',
    );
    expect(
      find.textContaining('프리뷰', findRichText: true),
      findsNothing,
      reason: '같은 말, 한국어로도',
    );

    await _pump(tester, tool: CanvasTool.fill);
    expect(
      find.byKey(ToolSettingsPreview.slotKey),
      findsNothing,
      reason: '「일단 스탬프도구, 브러시/지우개」 — 나머지는 아직 아니다',
    );
  });

  /// ⛔**연속값을 캐시 키로 쓰지 말 것** — the live preview's settings change on
  /// every frame of a slider drag, so its bakes must COALESCE and must not be
  /// filed in the preset cache. 🧪Driven through the widget's own seam: the
  /// real bake runs in an isolate, and a test that awaited it would be
  /// measuring the scheduler instead of this rule.
  testWidgets('🚨a storm of settings bakes ONE at a time, newest last', (
    tester,
  ) async {
    final asked = <double>[];
    final gates = <Completer<BrushStrokeSample>>[];
    Future<BrushStrokeSample> rasterize(
      BrushSettings settings,
      int width,
      int height,
    ) {
      asked.add(settings.size);
      final gate = Completer<BrushStrokeSample>();
      gates.add(gate);
      return gate.future;
    }

    var settings = BrushSettings(size: 1);
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 60,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return BrushStrokeLivePreview(
                    settings: settings,
                    rasterize: rasterize,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(asked, [1], reason: 'the first build asks for what it is showing');

    for (var size = 2; size <= 9; size += 1) {
      settings = BrushSettings(size: size.toDouble());
      setOuter(() {});
      await tester.pump();
    }
    expect(
      asked,
      [1],
      reason:
          '⛔여덟 번 바뀌는 동안 **굽는 것은 여전히 하나** — 중간값마다 워커에 '
          '쌓았으면 낡은 그림이 다 구워진 뒤에야 손이 멈춘 값이 나온다',
    );

    gates.first.complete(BrushStrokeSample(image: await _pixel()));
    await tester.pump();
    await tester.pump();
    expect(
      asked,
      [1, 9],
      reason:
          '🚨그리고 다음에 굽는 것은 **손이 멈춘 값**이다 — 큐가 아니라 한 칸',
    );
  });

  /// 🚨★★★**한 번 굽고, 값이 바뀔 때만 다시 굽는다** (유저 2026-09-22:
  /// 「스트로크는 한번 굽고, 값이 바뀔때만 구우면 되는게 맞지않나?」).
  ///
  /// 🔬유저 실기 09-22: 아무것도 안 하는데 화면이 계속 갱신되고, Show Repaints
  /// 에서 이 프리뷰만 **앰버 테두리**(= 연속 프레임마다 살아 있어 굽기를 스스로
  /// 포기한 상태)를 달고 있었다. 구운 그림이 도착하면 `setState` → 빌드 →
  /// **같은 값을 또 요청** → 또 도착 … 스스로 도는 고리다. 그동안 워커 하나가
  /// 계속 돌고 완료마다 프레임이 예약되니, 손이 멈춰 있는데도 앱 전체가 매
  /// 프레임 다시 래스터된다.
  ///
  /// 옆의 프리셋 프리뷰는 같은 법을 `_sampleSettings` 로 이미 지키고 있었다
  /// ([BrushStrokePreview]) — **화면에 있는 것은 다시 요청할 값이 아니다.**
  testWidgets('🚨once it has what it asked for it stops asking — and asks '
      'again only when the value changes', (tester) async {
    final asked = <double>[];
    final gates = <Completer<BrushStrokeSample>>[];
    Future<BrushStrokeSample> rasterize(
      BrushSettings settings,
      int width,
      int height,
    ) {
      asked.add(settings.size);
      final gate = Completer<BrushStrokeSample>();
      gates.add(gate);
      return gate.future;
    }

    var settings = BrushSettings(size: 1);
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 60,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return BrushStrokeLivePreview(
                    settings: settings,
                    rasterize: rasterize,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(asked, [1], reason: 'the first build asks for what it shows');

    gates.single.complete(BrushStrokeSample(image: await _pixel()));
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      asked,
      [1],
      reason:
          '⛔구운 그림이 이미 화면에 있다 — 그것을 또 굽는 것은 아무것도 바꾸지 '
          '않으면서 워커와 프레임만 먹는다',
    );

    settings = BrushSettings(size: 4);
    setOuter(() {});
    await tester.pump();
    expect(asked, [1, 4], reason: '「값이 바뀔때만 구우면 되는게 맞지않나?」');
  });

  /// ⛔**그리고 그 그림들은 프리셋 캐시에 들어가지 않는다.** 행동으로는 못
  /// 잰다 — 이음매로 구우니 캐시를 아예 안 만진다 — 그래서 소스 스캔이다.
  /// 512칸짜리 LRU에 슬라이더가 지나간 값이 쌓이면, 목록이 실제로 재사용하는
  /// 프리셋들이 그만큼 밀려난다.
  test('한 번 쓰고 버릴 그림은 캐시에 안 넣는다', () {
    final source = librarySource('lib/src/ui/brush/brush_stroke_live_preview.dart');
    expect(
      source,
      contains('rasterizeUncached'),
      reason: '풀은 같이 쓰고, 보관은 안 한다',
    );
    expect(
      source,
      isNot(contains('.ensure(')),
      reason:
          '⛔`ensure` 는 키로 보관한다 — 연속값을 키로 쓰는 순간 그게 바로 '
          '「캐시 넣기 전 네 질문」이 막는 것이다',
    );
  });
}

Future<ui.Image> _pixel() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(1, 1);
}
