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

  test('the six moves, and their keys as the timeline reads them', () {
    String keysOf(String id) => [
      for (final a in definitionFor(id).defaultActivators)
        '${a.shift ? 'Shift+' : ''}${a.control ? 'Ctrl+' : ''}'
            '${a.trigger.keyLabel}',
    ].join(' · ');

    expect(
      keysOf(EditorActionIds.framePrevious),
      'Shift+Arrow Left',
      reason: '「이전/다음 프레임은 ,.가 아니라 쉬프트<>만이야. ,.는 삭제」',
    );
    expect(keysOf(EditorActionIds.frameNext), 'Shift+Arrow Right');
    expect(keysOf(EditorActionIds.drawingPrevious), 'Arrow Left');
    expect(keysOf(EditorActionIds.drawingNext), 'Arrow Right');
    expect(keysOf(EditorActionIds.layerUp), 'Arrow Up');
    expect(keysOf(EditorActionIds.layerDown), 'Arrow Down');
    for (final id in moves) {
      expect(definitionFor(id).readsTheSheet, isTrue, reason: id);
    }
  });

  test('⛔no Ctrl+arrow and no second key for a block is left — and no '
      'direction action beside the moves', () {
    for (final definition in editorActionDefinitions) {
      for (final activator in definition.defaultActivators) {
        final arrow = SheetArrow.of(activator.trigger) != null;
        expect(
          arrow && activator.control,
          isFalse,
          reason: '${definition.id}: 「쉬프트+화살표로 변경」',
        );
        expect(
          arrow && !moves.contains(definition.id),
          isFalse,
          reason: '${definition.id}: an arrow belongs to the six moves',
        );
      }
    }
    for (final id in [
      EditorActionIds.drawingPrevious,
      EditorActionIds.drawingNext,
    ]) {
      expect(
        definitionFor(id).defaultActivators,
        hasLength(1),
        reason: '$id: 「컨트롤+, 이런건 삭제」',
      );
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
}
