import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/sheet_arrow.dart';

/// 🗣️F-241 (유저 2026-09-29): 「이전/다음 프레임, 이전/다음 블록, 위/아래
/// 레이어 이렇게 개편」 · 「컨트롤+화살표가 아니라 쉬프트+화살표로 변경」 ·
/// 「이전원화 다음원화는 왜 단축키 두개인지? … 컨트롤+, 이런건 삭제」 ·
/// 「이전프레임이랑 왼쪽으로 한걸음이랑 똑같은데 … 싹 삭제」 · 「위/아래
/// 레이어는 x시트로 되있는 상태면 단축키가 바뀌는데, 그런식으로 단축키 바뀐
/// 상황에서 그에맞게 텍스트 내용도 변경」.
///
/// SIX moves, named by what they do, all on the arrows — and the frame's
/// only keys are Shift+arrows: 「이전/다음 프레임은 ,.가 아니라 쉬프트<>만이야.
/// ,.는 삭제」. The arrows are written as the timeline reads them, and the
/// X-sheet — frames running down — turns a pressed arrow to the timeline's
/// reading before it is matched, and shows a bound arrow turned the other
/// way.
void main() {
  EditorActionDefinition definitionFor(String id) =>
      editorActionDefinitions.firstWhere((d) => d.id == id);

  const moves = {
    EditorActionIds.framePrevious,
    EditorActionIds.frameNext,
    EditorActionIds.drawingPrevious,
    EditorActionIds.drawingNext,
    EditorActionIds.layerUp,
    EditorActionIds.layerDown,
  };

  KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  ({EditorShortcutBindings bindings, FlipHudController sheet}) rig({
    required bool xSheet,
  }) {
    final sheet = FlipHudController()..framesRunVertically = xSheet;
    addTearDown(sheet.dispose);
    final bindings = EditorShortcutBindings()..sheet = sheet;
    addTearDown(bindings.dispose);
    return (bindings: bindings, sheet: sheet);
  }

  // ↩️F-261 (유저 2026-10-02): 「프레임이동은 배치 바꾼다기보단 배치 추가. ws
  // 위아래, ad 좌우(프레임)이동. 1프레임씩 이동하는거도 동일하게 쉬프트a
  // 쉬프트d」 — the second set, asked for, beside the arrows. F-241's
  // 「컨트롤+, 이런건 삭제. 절대 멋대로 넣지말고 넣을땐 보고할것」 is why a
  // block's keys are pinned here exactly.
  test('the six moves, and their keys as the timeline reads them', () {
    String keysOf(String id) => [
      for (final a in definitionFor(id).defaultActivators)
        '${a.shift ? 'Shift+' : ''}${a.control ? 'Ctrl+' : ''}'
            '${a.trigger.keyLabel}',
    ].join(' · ');

    expect(
      keysOf(EditorActionIds.framePrevious),
      'Shift+Arrow Left · Shift+A',
      reason: '「이전/다음 프레임은 ,.가 아니라 쉬프트<>만이야. ,.는 삭제」',
    );
    expect(keysOf(EditorActionIds.frameNext), 'Shift+Arrow Right · Shift+D');
    expect(keysOf(EditorActionIds.drawingPrevious), 'Arrow Left · A');
    expect(keysOf(EditorActionIds.drawingNext), 'Arrow Right · D');
    expect(keysOf(EditorActionIds.layerUp), 'Arrow Up · W');
    expect(keysOf(EditorActionIds.layerDown), 'Arrow Down · S');

    final walks = {
      for (final id in moves) id: definitionFor(id).sheetMove,
    };
    expect(walks, {
      EditorActionIds.framePrevious: (arrow: SheetArrow.left, fine: true),
      EditorActionIds.frameNext: (arrow: SheetArrow.right, fine: true),
      EditorActionIds.drawingPrevious: (arrow: SheetArrow.left, fine: false),
      EditorActionIds.drawingNext: (arrow: SheetArrow.right, fine: false),
      EditorActionIds.layerUp: (arrow: SheetArrow.up, fine: false),
      EditorActionIds.layerDown: (arrow: SheetArrow.down, fine: false),
    });
    expect(
      editorActionDefinitions.where((d) => d.sheetMove != null),
      hasLength(moves.length),
      reason: 'no move on the sheet beside the six',
    );
  });

  // F-28's 「입구는 달라도 통하는건 하나」: the flip asks the moves' own table
  // which move walks a way — the extra finger the frame step, as Shift is on
  // the keys — instead of a switch of its own.
  test('the table the flip reads: a way and the extra finger name the move, '
      'and the extra finger on a row is still the row', () {
    expect(
      sheetMoveActionId(SheetArrow.right, fine: true),
      EditorActionIds.frameNext,
    );
    expect(
      sheetMoveActionId(SheetArrow.left, fine: true),
      EditorActionIds.framePrevious,
    );
    expect(
      sheetMoveActionId(SheetArrow.right, fine: false),
      EditorActionIds.drawingNext,
    );
    expect(
      sheetMoveActionId(SheetArrow.left, fine: false),
      EditorActionIds.drawingPrevious,
    );
    expect(
      sheetMoveActionId(SheetArrow.up, fine: true),
      EditorActionIds.layerUp,
    );
    expect(
      sheetMoveActionId(SheetArrow.down, fine: false),
      EditorActionIds.layerDown,
    );
  });

  test('⛔no move on a Ctrl chord — and a direction key, bare or under '
      'Shift, belongs to the six moves alone', () {
    final bindings = EditorShortcutBindings();
    addTearDown(bindings.dispose);
    final keys = bindings.sheetKeys;
    for (final definition in editorActionDefinitions) {
      final move = moves.contains(definition.id);
      for (final activator in definition.defaultActivators) {
        expect(
          move && activator.control,
          isFalse,
          reason: '${definition.id}: 「쉬프트+화살표로 변경」',
        );
        // Ctrl+S saves and Ctrl+D lets go: a chord is its own key. The
        // bare key and its Shift are the ones the sheet turns.
        final turnable =
            keys.placeOf(activator.trigger) != null &&
            !activator.control &&
            !activator.alt &&
            !activator.meta;
        expect(
          turnable && !move,
          isFalse,
          reason: '${definition.id}: a direction key belongs to the moves',
        );
      }
    }
  });

  test('the X-sheet turns an arrow to the timeline\'s reading, and shows '
      'one turned back — the timeline turns nothing', () {
    final timeline = rig(xSheet: false).sheet;
    for (final arrow in SheetArrow.values) {
      expect(timeline.timelineArrowFor(arrow), arrow);
      expect(timeline.sheetArrowFor(arrow), arrow);
    }
    final xSheet = rig(xSheet: true).sheet;
    // Frames run down: ↓ is on in time, ↑ back. The rows run right to left
    // (F-28, 유저 2026-08-31), so → is a step UP the stack.
    expect(xSheet.timelineArrowFor(SheetArrow.down), SheetArrow.right);
    expect(xSheet.timelineArrowFor(SheetArrow.up), SheetArrow.left);
    expect(xSheet.timelineArrowFor(SheetArrow.right), SheetArrow.up);
    expect(xSheet.timelineArrowFor(SheetArrow.left), SheetArrow.down);
    for (final arrow in SheetArrow.values) {
      expect(xSheet.sheetArrowFor(xSheet.timelineArrowFor(arrow)), arrow);
    }
  });

  test('on the X-sheet the arrow that runs WITH the frames presses the '
      'frame and block moves, and the one across them the layer moves', () {
    final bindings = rig(xSheet: true).bindings;
    bool presses(String id, LogicalKeyboardKey key) =>
        bindings.presses(id, down(key));

    expect(
      presses(EditorActionIds.drawingNext, LogicalKeyboardKey.arrowDown),
      isTrue,
    );
    expect(
      presses(EditorActionIds.drawingNext, LogicalKeyboardKey.arrowRight),
      isFalse,
    );
    expect(
      presses(EditorActionIds.drawingPrevious, LogicalKeyboardKey.arrowUp),
      isTrue,
    );
    expect(
      presses(EditorActionIds.layerUp, LogicalKeyboardKey.arrowRight),
      isTrue,
    );
    expect(
      presses(EditorActionIds.layerDown, LogicalKeyboardKey.arrowLeft),
      isTrue,
    );
  });

  testWidgets('Shift+the arrow that runs with the frames is the one-frame '
      'move on either sheet', (tester) async {
    for (final xSheet in [false, true]) {
      final bindings = rig(xSheet: xSheet).bindings;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final along = xSheet
          ? LogicalKeyboardKey.arrowDown
          : LogicalKeyboardKey.arrowRight;
      expect(
        bindings.presses(EditorActionIds.frameNext, down(along)),
        isTrue,
        reason: 'x-sheet: $xSheet',
      );
      expect(
        bindings.presses(EditorActionIds.drawingNext, down(along)),
        isFalse,
        reason: 'Shift makes it a frame, not a block',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  });

  test('the keys are SHOWN as they press on the sheet in front of the user, '
      'and one recorded there is KEPT as the timeline reads it', () {
    const up = SingleActivator(LogicalKeyboardKey.arrowUp);
    const right = SingleActivator(LogicalKeyboardKey.arrowRight);
    const down = SingleActivator(LogicalKeyboardKey.arrowDown);
    final onTimeline = rig(xSheet: false).bindings;
    expect(
      onTimeline.shownActivatorFor(EditorActionIds.layerUp, up).trigger,
      LogicalKeyboardKey.arrowUp,
    );
    final onXSheet = rig(xSheet: true).bindings;
    expect(
      onXSheet.shownActivatorFor(EditorActionIds.layerUp, up).trigger,
      LogicalKeyboardKey.arrowRight,
      reason: '「단축키 바뀐 상황에서 그에맞게 텍스트 내용도 변경」',
    );
    expect(
      onXSheet.shownActivatorFor(EditorActionIds.drawingNext, right).trigger,
      LogicalKeyboardKey.arrowDown,
    );
    expect(
      onXSheet.keptActivatorFor(EditorActionIds.drawingNext, down).trigger,
      LogicalKeyboardKey.arrowRight,
      reason: 'recorded on the X-sheet, kept for the timeline — so it turns '
          'again there',
    );
  });

  // 🚨F-261 (유저 2026-10-02): 「그런 인식못하는 문제같은거 근본 구조적으로 법
  // 통일해줘」 — the arrows were the only keys the sheet turned. A direction
  // key is what the BINDINGS say it is now, so WASD, and any four keys a
  // user records, walk the X-sheet exactly as the arrows do.
  test('WASD walk the X-sheet as the arrows do — S runs with the frames, '
      'D and A cross the rows', () {
    final bindings = rig(xSheet: true).bindings;
    bool presses(String id, LogicalKeyboardKey key) =>
        bindings.presses(id, down(key));

    const drawingNext = EditorActionIds.drawingNext;
    expect(presses(drawingNext, LogicalKeyboardKey.keyS), isTrue);
    expect(presses(drawingNext, LogicalKeyboardKey.keyD), isFalse);
    expect(
      presses(EditorActionIds.drawingPrevious, LogicalKeyboardKey.keyW),
      isTrue,
    );
    expect(presses(EditorActionIds.layerUp, LogicalKeyboardKey.keyD), isTrue);
    expect(presses(EditorActionIds.layerDown, LogicalKeyboardKey.keyA), isTrue);

    final onTimeline = rig(xSheet: false).bindings;
    expect(
      onTimeline.presses(drawingNext, down(LogicalKeyboardKey.keyD)),
      isTrue,
      reason: 'the timeline turns nothing',
    );
  });

  testWidgets('Shift+the WASD key that runs with the frames is the one-frame '
      'move on either sheet', (tester) async {
    for (final xSheet in [false, true]) {
      final bindings = rig(xSheet: xSheet).bindings;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final along = xSheet ? LogicalKeyboardKey.keyS : LogicalKeyboardKey.keyD;
      final back = xSheet ? LogicalKeyboardKey.keyW : LogicalKeyboardKey.keyA;
      expect(
        bindings.presses(EditorActionIds.frameNext, down(along)),
        isTrue,
        reason: 'x-sheet: $xSheet',
      );
      expect(
        bindings.presses(EditorActionIds.framePrevious, down(back)),
        isTrue,
        reason: 'x-sheet: $xSheet',
      );
      expect(
        bindings.presses(EditorActionIds.drawingNext, down(along)),
        isFalse,
        reason: 'Shift makes it a frame, not a block',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  });

  test('a WASD key is SHOWN as it presses on the X-sheet and KEPT as the '
      'timeline reads it — paired within its own set', () {
    const w = SingleActivator(LogicalKeyboardKey.keyW);
    const d = SingleActivator(LogicalKeyboardKey.keyD);
    const s = SingleActivator(LogicalKeyboardKey.keyS);
    final onXSheet = rig(xSheet: true).bindings;
    expect(
      onXSheet.shownActivatorFor(EditorActionIds.layerUp, w).trigger,
      LogicalKeyboardKey.keyD,
      reason: 'W stays in its set — never the arrow →',
    );
    expect(
      onXSheet.shownActivatorFor(EditorActionIds.drawingNext, d).trigger,
      LogicalKeyboardKey.keyS,
    );
    expect(
      onXSheet.keptActivatorFor(EditorActionIds.drawingNext, s).trigger,
      LogicalKeyboardKey.keyD,
    );
  });

  test('any four keys a user puts on the moves turn as a set — the law is '
      'the bindings\', not a list of keys', () {
    final bindings = rig(xSheet: true).bindings;
    for (final (id, key) in [
      (EditorActionIds.layerUp, LogicalKeyboardKey.keyI),
      (EditorActionIds.drawingPrevious, LogicalKeyboardKey.keyJ),
      (EditorActionIds.layerDown, LogicalKeyboardKey.keyK),
      (EditorActionIds.drawingNext, LogicalKeyboardKey.keyL),
    ]) {
      bindings.setActivators(id, [
        ...bindings.activatorsFor(id),
        SingleActivator(key),
      ]);
    }
    bool presses(String id, LogicalKeyboardKey key) =>
        bindings.presses(id, down(key));

    const drawingNext = EditorActionIds.drawingNext;
    expect(presses(drawingNext, LogicalKeyboardKey.keyK), isTrue);
    expect(presses(EditorActionIds.layerUp, LogicalKeyboardKey.keyL), isTrue);
    expect(presses(drawingNext, LogicalKeyboardKey.keyL), isFalse);
    expect(
      bindings
          .shownActivatorFor(
            EditorActionIds.layerUp,
            const SingleActivator(LogicalKeyboardKey.keyI),
          )
          .trigger,
      LogicalKeyboardKey.keyL,
    );
  });

  test('a key alone in its place has no partner to turn into — it presses '
      'its own move on every sheet, and shows and keeps as itself', () {
    final bindings = rig(xSheet: true).bindings;
    bindings.setActivators(EditorActionIds.layerUp, [
      ...bindings.activatorsFor(EditorActionIds.layerUp),
      const SingleActivator(LogicalKeyboardKey.keyI),
    ]);
    const i = SingleActivator(LogicalKeyboardKey.keyI);

    expect(
      bindings.presses(EditorActionIds.layerUp, down(LogicalKeyboardKey.keyI)),
      isTrue,
    );
    expect(
      bindings.presses(
        EditorActionIds.drawingPrevious,
        down(LogicalKeyboardKey.keyI),
      ),
      isFalse,
      reason: 'up on the X-sheet is the previous block — for a SET',
    );
    expect(
      bindings.shownActivatorFor(EditorActionIds.layerUp, i).trigger,
      LogicalKeyboardKey.keyI,
    );
    expect(
      bindings.keptActivatorFor(EditorActionIds.layerUp, i).trigger,
      LogicalKeyboardKey.keyI,
    );
    expect(
      bindings.presses(EditorActionIds.layerUp, down(LogicalKeyboardKey.keyW)),
      isFalse,
      reason: '⛔전제: W is still in its set, and turns',
    );
  });
}
