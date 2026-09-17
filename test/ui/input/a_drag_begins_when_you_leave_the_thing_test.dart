import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_preset_reorder_grid.dart';

import '../../helpers/dart_sources.dart';
import '../../helpers/library_source.dart';

/// 🚨★★★**F-138 — 서 있어야 하는 것은 상자를 벗어나야 끌린다.**
///
/// > 「꽤 최신 브런치로 ios 빌드했는데(1010) 버튼들 펜 사용시 인식이 이상해짐.
/// > … 브러시그룹은 펜을 **떨리면서 클릭해도 제대로 클릭되고**, 드래그 작동
/// > 시작도 **누른채로 다른곳 이동하면 발동**하는 느낌인데, **브러시 버튼은
/// > 그냥 누르는순간 드래그가 발동**됨. 그러니 법 통일하고」 (유저 2026-09-16)
///
/// 🗣️**유저 확정 2026-09-18** (`F-138-Q1`, 답 ①): 「미디어풀처럼 **선택할
/// 필요, 서있는 로직이 없는곳은 지금처럼 바로드래그**, 브러시처럼 **서있어야
/// 하는곳은 누른 상자 벗어나면 시작**으로」.
///
/// ⛔**그리고 허용치는 없다.** 유저 2026-08-30 이 px 비교를 전부 걷어내게 했고
/// (「싹 깔끔하게 걷어내」), 그래서 이 판정은 **거리가 아니라 위치**다 — 클릭을
/// 정하는 그 술어(`ControlPressClaim._releasedInside`)의 반대쪽이다.
void main() {
  Widget grid({required VoidCallback onDragStart}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 130,
          height: 400,
          child: BrushPresetReorderGrid(
            itemCount: 6,
            cellHeight: 40,
            itemKey: (index) => ValueKey<String>('cell-$index'),
            onDragStart: onDragStart,
            onReorder: (_, _) {},
            itemBuilder: (context, index) => ColoredBox(
              color: Colors.blue,
              child: Center(child: Text('$index')),
            ),
          ),
        ),
      ),
    ),
  );

  for (final kind in const [
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  ]) {
    testWidgets('${kind.name}: a tremor inside the cell starts NO drag', (
      tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(grid(onDragStart: () => started += 1));
      await tester.pumpAndSettle();

      final cell = tester.getCenter(find.text('1'));
      final gesture = await tester.startGesture(cell, kind: kind);
      // A pen's hand shake, well inside a 40px-tall cell.
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      await gesture.moveBy(const Offset(1, -3));
      await tester.pump();
      await gesture.moveBy(const Offset(-2, 1));
      await tester.pump();

      expect(
        started,
        0,
        reason:
            '유저: 「브러시그룹은 펜을 **떨리면서 클릭해도 제대로 클릭되고** … '
            '브러시 버튼은 그냥 누르는순간 드래그가 발동됨」',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(started, 0, reason: 'and letting go where it began is a press');
    });

    testWidgets('${kind.name}: and leaving the cell starts it', (tester) async {
      var started = 0;
      await tester.pumpWidget(grid(onDragStart: () => started += 1));
      await tester.pumpAndSettle();

      final cell = tester.getCenter(find.text('1'));
      final gesture = await tester.startGesture(cell, kind: kind);
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      // Out of the cell it pressed — 「누른채로 다른곳 이동하면 발동」.
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();

      expect(started, 1, reason: '유저: 「누른채로 다른곳 이동하면 발동」');
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }

  /// ⛔**AND NOWHERE ELSE.** 🗣️유저 확정: 「미디어풀처럼 선택할 필요, 서있는
  /// 로직이 없는곳은 **지금처럼 바로드래그**」 — the media pool's rows and the
  /// panel tab's grip are grabbed, not stood on, and [F-126] is the reason
  /// they start on the first move. A source scan, because a behaviour test
  /// of a source that did NOT change proves nothing about why.
  test('only the thing you stand on waits', () {
    final waiting = <String>[];
    for (final file in dartFilesUnder('lib/src/ui')) {
      final path = libPath(file);
      if (path == 'lib/src/ui/widgets/owning_draggable.dart') {
        continue; // The one home — it declares the seam and forwards it.
      }
      final source = file.readAsStringSync();
      if (!source.contains('stillOnTheThing:')) {
        continue;
      }
      waiting.add(path);
      expect(
        source,
        contains('pointerIsStillOn('),
        reason:
            '⛔$path waits with a predicate of its own. The seam takes a '
            'callback because a recogniser has no tree to ask — it is not an '
            'invitation to answer a DIFFERENT question here (a distance, a '
            'device kind). 유저 2026-08-30: 「싹 깔끔하게 걷어내」',
      );
    }
    expect(
      waiting,
      ['lib/src/ui/brush/brush_preset_reorder_grid.dart'],
      reason:
          '⛔the preset cell is the one drag source you must first STAND on. '
          'A second name here is either a new standing surface — say so at '
          'the site — or F-126 quietly coming undone somewhere it was never '
          'the question',
    );
  });

  /// ⛔**그리고 이 판정에 거리는 없다** (소스 스캔 래칫). 유저 2026-08-30 이
  /// 이 앱에서 px 비교를 걷어내게 했고, 되돌아오는 길은 늘 「한 번만」이다.
  test('the wait is a position, never a distance', () {
    final source = librarySource('lib/src/ui/widgets/axis_bar_gesture.dart');
    expect(
      source,
      isNot(contains('kTouchSlop')),
      reason: '⛔18px 은 폐기 목록에 이름으로 올라 있다',
    );
    expect(
      source,
      isNot(contains('computeHitSlop')),
      reason: '⛔기기의 슬롭을 묻는 것이 F-126 을 만든 그 질문이다',
    );
    expect(
      librarySource('lib/src/ui/input/control_press_claim.dart'),
      contains('pointerIsStillOn('),
      reason:
          '⛔클릭을 정하는 그 술어와 **같은 함수**다 — 「누른 상자 안인가」. '
          '처음엔 두 벌로 썼고 클론 래칫이 그걸 잡았다(90 → 91)',
    );
  });
}
