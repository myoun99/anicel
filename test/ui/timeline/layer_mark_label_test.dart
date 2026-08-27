import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerSectionBandCell, layerMarkColor, layerMarkSlotWidth;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineTextOnColor;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// A6 (2026-08-17): the layer colour label — 「①위치 = 레이어 영역 맨 왼쪽
/// ②동그라미 → 세로로 꽉 채우는 심플 사각형, 패딩 절대 금지 ③가로폭 =
/// 세로의 절반 ④가로쓰기 세로표시로 색 이름 텍스트 ⑤클릭 로직 그대로
/// ⑥텍스트 색은 프레임블록의 휘도 법(#1109) 그대로」.
Layer _layer(String id, LayerKind kind, {LayerMark mark = LayerMark.none}) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    mark: mark,
    frames: kind == LayerKind.camera
        ? const []
        : [Frame(id: FrameId('$id-frame'), duration: 1, strokes: const [])],
    timeline: const {},
  );
}

Widget _panel() {
  final layers = [
    _layer('a', LayerKind.animation, mark: const LayerMark(process: LayerProcess.inbetween, revise: LayerRevise.inbetweenCheck)),
    _layer('b', LayerKind.animation, mark: const LayerMark(process: LayerProcess.finish)),
    _layer('plain', LayerKind.animation),
    _layer('cam', LayerKind.camera),
  ];
  return MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers,
        activeLayerId: const LayerId('a'),
        frameCursor: ValueNotifier<int>(0),
        playbackFrameCount: 12,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        orientation: TimelineOrientation.horizontal,
        onOrientationChanged: (_) {},
      ),
    ),
  );
}

void main() {
  _takeLabelPlate();
  _twoLevelPopover();

  testWidgets('the label is a full-height, half-width plate leading the '
      'layer area (A6 ①②③)', (tester) async {
    await tester.pumpWidget(_panel());

    final chip = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    final row = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-row-a')),
    );

    expect(
      chip.height,
      closeTo(row.height, 1.0),
      reason:
          'A6 ②: the plate fills the row height, no padding — at most the '
          'row\'s own bottom divider hairline stays outside it',
    );
    expect(
      chip.width,
      moreOrLessEquals(layerMarkSlotWidth),
      reason: 'A6 ③: width is half the canonical 28px row height',
    );
    expect(
      chip.top,
      moreOrLessEquals(row.top),
      reason: 'A6 ②: flush with the row edge — no vertical padding',
    );
    final sectionCell = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-row-a')),
        matching: find.byType(LayerSectionBandCell),
      ),
    );
    expect(
      chip.left,
      moreOrLessEquals(sectionCell.right),
      reason:
          'A6 ①: the layer area\'s FIRST cell, FLUSH against the section '
          'zone — leftmost, before the twirl, zero gap',
    );
  });

  testWidgets('the colour name stands upright and takes its ink from the '
      'luminance law (A6 ④⑥, #1109)', (tester) async {
    await tester.pumpWidget(_panel());

    // ⚠️`.first`: a labelled row draws TWO columns now (공정 + 수정), and
    // both wear the same ink by construction — the plate hands one colour
    // to every column it writes.
    TextStyle? styleUnder(String key) {
      final label = tester.widgetList<VerticalWritingText>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(VerticalWritingText),
        ),
      ).first;
      return label.style;
    }

    // The ink is the LAW's answer, not a constant: whatever
    // timelineTextOnColor says for this plate is what the label wears.
    // (On today's palette the whole set inks black — 보라도 검정 5.4:1,
    // the #1109 record; the law's white branch is pinned by the block
    // text tests, not re-proven here.)
    expect(
      styleUnder('timeline-layer-mark-a')?.color,
      timelineTextOnColor(layerMarkColor(const LayerMark(process: LayerProcess.inbetween, revise: LayerRevise.inbetweenCheck))),
    );
    expect(
      styleUnder('timeline-layer-mark-b')?.color,
      timelineTextOnColor(layerMarkColor(const LayerMark(process: LayerProcess.finish))),
    );
  });

  testWidgets('the none plate stays bare — paper colour, no name', (
    tester,
  ) async {
    await tester.pumpWidget(_panel());

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-mark-plain')),
        matching: find.byType(VerticalWritingText),
      ),
      findsNothing,
      reason: 'the paper colour has no name to announce; the plate alone '
          'keeps the tap target discoverable',
    );
    // The plate itself is still there — the click logic is untouched (⑤).
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-mark-plain')),
      findsOneWidget,
    );
  });
}

/// I-5 — 테이크 라벨이 색 라벨 바로 오른쪽에, 같은 크기로, 항상 자리를
/// 예약한 채 선다.
void _takeLabelPlate() {
  testWidgets('테이크 플레이트가 색 라벨 오른쪽에 같은 크기로 선다', (tester) async {
    await tester.pumpWidget(_panel());

    final mark = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    final take = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-take-a')),
    );

    expect(
      take.left,
      closeTo(mark.right, 0.5),
      reason: '유저: 「위치는 색 라벨 **바로 오른쪽**에」',
    );
    expect(
      take.width,
      closeTo(mark.width, 0.5),
      reason: '유저: 「색 라벨이랑 **같은 디자인**으로」',
    );
    expect(
      take.height,
      closeTo(mark.height, 0.5),
      reason: '띠 높이는 그대로 — 두 플레이트가 같은 행에 나란히 선다',
    );
  });

  testWidgets('⛔테이크가 없어도 자리는 그대로다 — 붙는다고 이름이 밀리지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(_panel());
    // 기본 픽스처에는 테이크가 없다. 그래도 플레이트는 그려져 있어야 한다.
    final take = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-take-a')),
    );
    expect(
      take.width,
      greaterThan(0),
      reason: '🚨없다가 생기는 UI 금지 — 자리는 항상 예약하고 내용만 바꾼다',
    );
  });

  testWidgets('테이크 팝오버는 1–9 만 낸다 — 「없음」은 없다', (tester) async {
    await tester.pumpWidget(_panel());

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-take-a')),
    );
    await tester.pumpAndSettle();

    for (final take in LayerMark.takeChoices) {
      expect(
        find.byKey(ValueKey<String>('layer-take-option-$take')),
        findsOneWidget,
        reason: '테이크 $take',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('layer-take-option-none')),
      findsNothing,
      reason: '유저: 「테이크도 … 라벨없음 삭제해. 테이크는 기본값 T1」 — '
          '그림은 언제나 어떤 판이라 부재가 없다',
    );
  });

  testWidgets('⛔테이크 라벨에는 배경이 없다 — 글자만, 레이어 이름처럼', (tester) async {
    await tester.pumpWidget(_panel());
    // 유저 2026-08-27: 「테이크라벨은 **배경 삭제**해. 그러고 글자만 심플하게
    // **레이어이름처럼 디자인 통일**해서」.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-take-a')),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
      reason: '🚨색 라벨은 채워진 플레이트지만 테이크는 아니다',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
        matching: find.byType(ColoredBox),
      ),
      findsWidgets,
      reason: '⚠️대조군 — 색 라벨은 여전히 칠해진다. 이 단언이 없으면 위의 '
          '단언은 「둘 다 안 칠해진다」로도 통과한다',
    );
  });
}

/// 🚨★★★팝오버는 **두 겹**이다. 유저 설계(I-4): 「거기 **호버하면 추가로
/// 앵커팝오버로 수정라벨이 뜨도록**. 즉 축으로서 2가지가 존재하도록」.
///
/// ⛔한 번 평평하게 만들었다가 유저에게 잡혔다: 「니가 아티팩트로 제시한거랑
/// 이거랑 똑같다고 생각하냐? … 대체 왜 정한대로 안만드는거야?」. 그래서 이
/// 테스트는 「수정 항목이 있다」가 아니라 **「처음에는 없다가 호버해야 나온다」**
/// 를 잰다 — 평평한 목록은 전자를 통과시킨다.
void _twoLevelPopover() {
  testWidgets('첫 겹은 공정만 낸다 — 수정은 아직 화면에 없다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    await tester.pumpAndSettle();

    for (final process in LayerProcess.values) {
      expect(
        find.byKey(ValueKey<String>('layer-mark-option-${process.jsonValue}')),
        findsOneWidget,
        reason: '${process.displayName} 은 첫 겹에 있다',
      );
    }
    // 🚨THE ASSERTION THAT KILLS THE FLAT LIST.
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-animation-director'),
      ),
      findsNothing,
      reason: '수정은 호버 전에는 없어야 한다 — 평평하게 펼치면 여기서 죽는다',
    );
  });

  testWidgets('공정에 호버하면 그 공정의 수정만 옆에 뜬다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('layer-mark-option-layout')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-animation-director'),
      ),
      findsOneWidget,
      reason: '레이아웃의 작화감독 수정이 두 번째 겹에 뜬다',
    );
    expect(
      find.byKey(const ValueKey<String>('layer-mark-option-layout')),
      findsWidgets,
      reason: '⚠️첫 겹은 닫히지 않는다 — 옆에 나란히 뜬다',
    );
    // 그 공정이 참조하지 않는 수정은 안 뜬다.
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-inbetween-check'),
      ),
      findsNothing,
      reason: '레이아웃은 동화검사를 참조하지 않는다',
    );
  });

  testWidgets('용지는 수정이 없으므로 두 번째 겹도 없다 — 바로 골라진다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    await tester.pumpAndSettle();

    final paper = find.byKey(
      const ValueKey<String>('layer-mark-option-paper'),
    );
    expect(paper, findsOneWidget);
    expect(
      find.descendant(of: paper, matching: find.byIcon(Icons.chevron_right)),
      findsNothing,
      reason: '유저: 「용지는 수정공정 존재 안하도록」 — 겹을 예고하면 안 된다',
    );
  });
}

/// 🚨호버가 겹을 **옮긴다**. 유저 2026-08-27 실기: 「호버한것마다 팝오버
/// 갱신하고 없으면 팝오버 열게 없는곳에 호버하면 사라지고 해야하는데 **전혀
/// 갱신안되고있음**. 추가팝오버도 기존 팝오버에 **딱 붙어서** 열리는게아니라
/// 뭔가 **겹쳐있음**」.
///
/// ⛔첫 구현은 겹을 `showMenu` 로 또 띄웠다 — 메뉴는 **라우트**라 쌓이기만 하고
/// 바뀌지 않는다. 이 셋이 그 실패를 각각 잡는다.
void _submenuFollowsTheHover() {
  Future<void> hover(WidgetTester tester, String key) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(ValueKey<String>(key))));
    await tester.pumpAndSettle();
  }

  testWidgets('다른 공정에 호버하면 겹이 그 공정 것으로 바뀐다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    await tester.pumpAndSettle();

    await hover(tester, 'layer-mark-option-inbetween');
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-inbetween-inbetween-check'),
      ),
      findsOneWidget,
      reason: '동화의 동화검사',
    );

    await hover(tester, 'layer-mark-option-layout');
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-inbetween-inbetween-check'),
      ),
      findsNothing,
      reason: '🚨앞 공정의 겹이 남아 있으면 안 된다 — 이게 신고된 증상이다',
    );
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-animation-director'),
      ),
      findsOneWidget,
      reason: '레이아웃 것으로 갈아탔다',
    );
  });

  testWidgets('겹이 없는 행에 호버하면 열려 있던 겹이 사라진다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    await tester.pumpAndSettle();

    await hover(tester, 'layer-mark-option-layout');
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-animation-director'),
      ),
      findsOneWidget,
    );

    // 용지는 수정이 없다.
    await hover(tester, 'layer-mark-option-paper');
    expect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-animation-director'),
      ),
      findsNothing,
      reason: '유저: 「없는곳에 호버하면 **사라지고** 해야하는데」',
    );
  });

  testWidgets('겹은 부모 행의 오른쪽에 딱 붙는다 — 겹치지 않는다', (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
    );
    await tester.pumpAndSettle();
    await hover(tester, 'layer-mark-option-layout');

    final parent = tester.getRect(
      find.byKey(const ValueKey<String>('layer-mark-option-layout')),
    );
    final childRow = tester.getRect(
      find.byKey(
        const ValueKey<String>('layer-mark-option-layout-animation-director'),
      ),
    );
    expect(
      childRow.left,
      greaterThanOrEqualTo(parent.right),
      reason: '🚨유저: 「기존 팝오버에 **딱 붙어서** 열리는게아니라 뭔가 '
          '겹쳐있음」 — 자식은 부모 오른쪽 밖에서 시작해야 한다',
    );
  });
}

/// 🚨읽는 방향은 **표면**이 정한다. 유저 2026-08-27:
/// 「LO작감시 왼쪽에 작감 오른쪽에 LO 오는데, 그게아니라 **평범하게 왼쪽에 LO
/// 오른쪽에 작감** 오도록. 이유는 지금 **레이어영역 자체가 왼쪽부터 오른쪽으로
/// 읽는걸 기준으로** 설계하고있어」 · 「x시트는 **가로쓰기 가로표기**로 **위에
/// LO 아래에 작감**」.
void _stageComesFirst() {
  testWidgets('레일에서는 공정이 왼쪽, 수정이 오른쪽', (tester) async {
    await tester.pumpWidget(_panel());
    final texts = tester
        .widgetList<VerticalWritingText>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
            matching: find.byType(VerticalWritingText),
          ),
        )
        .toList();
    expect(texts, hasLength(2), reason: '동화 + 동검 두 칼럼');

    final first = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
        matching: find.byWidget(texts.first),
      ),
    );
    final second = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-mark-a')),
        matching: find.byWidget(texts.last),
      ),
    );
    expect(texts.first.text, '동화', reason: '공정이 먼저 그려진다');
    expect(texts.last.text, '동검');
    expect(
      first.left,
      lessThan(second.left),
      reason: '🚨공정이 **왼쪽**에 온다 — 레이어 영역은 좌→우로 읽는다',
    );
  });
}
