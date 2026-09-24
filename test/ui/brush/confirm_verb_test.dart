import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/last_stroke_slot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/confirm_verb.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

/// Which door 확정 opens — the ORDER is the law (confirm-button, 유저
/// 2026-09-24): an open polygon first (it is what the user is looking at),
/// then the transform tool's 적용 (and any transform still in play), and
/// only then the last stroke laid down again.
///
/// ⛔[ConfirmVerb.canConfirm] is pinned beside every press: the rail's ↵
/// reads it, and a lit button that does nothing is the bug it exists to
/// make impossible.
void main() {
  final selection = CanvasSelectionCommands();
  final lastStroke = LastStrokeSlot();
  final tool = ValueNotifier(BrushToolState.defaults);
  final options = ValueNotifier(TransformToolOptions.defaults);
  final verb = ConfirmVerb(
    selection: selection,
    lastStroke: lastStroke,
    tool: tool,
    transformOptions: options,
  );
  final owner = Object();

  var applied = 0;
  var reinputs = 0;
  var canApply = false;
  var sessionOpen = false;

  setUp(() {
    applied = 0;
    reinputs = 0;
    canApply = false;
    sessionOpen = false;
    tool.value = BrushToolState.defaults.copyWith(tool: CanvasTool.brush);
    selection
      ..abandonPolygon()
      ..bind(
        owner,
        hasSelection: () => false,
        deselect: () {},
        closePolygon: () {
          selection.abandonPolygon();
          return true;
        },
        transformActive: () => sessionOpen,
        movePending: () => false,
        applyTransform: () => applied += 1,
        canApplyTransform: () => canApply,
      );
    lastStroke
      ..hold(
        BrushStrokeCommitData(
          sourceDabs: [
            BrushDab(
              center: CanvasPoint(x: 4, y: 4),
              color: 0xFF000000,
              size: 2,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: 0,
            ),
          ],
        ),
      )
      ..reinputHandler = () => reinputs += 1;
  });

  test('the normal state lays the last stroke down again', () {
    expect(verb.canConfirm, isTrue);
    verb.confirm();
    expect(reinputs, 1);
    expect(applied, 0);
  });

  test('an open polygon is closed first — and nothing else happens', () {
    selection.addPolygonPoint(CanvasPoint(x: 0, y: 0));
    expect(verb.canConfirm, isTrue);
    verb.confirm();
    expect(selection.hasOpenPolygon, isFalse, reason: '닫혔다');
    expect(reinputs, 0, reason: '⛔재입력이 끼어들지 않는다');
    expect(applied, 0);
  });

  test('the transform tool asks 적용 — and is grey when 적용 has nothing', () {
    tool.value = tool.value.copyWith(tool: CanvasTool.move);
    expect(verb.canConfirm, isFalse, reason: '⛔재입력으로 새지 않는다');
    verb.confirm();
    expect(reinputs, 0);
    expect(applied, 0);

    canApply = true;
    expect(verb.canConfirm, isTrue);
    verb.confirm();
    expect(applied, 1);
    expect(reinputs, 0);
  });

  test('a transform still in play under another tool is 적용\'s too', () {
    sessionOpen = true;
    canApply = true;
    verb.confirm();
    expect(applied, 1);
    expect(reinputs, 0, reason: '⛔세션 위에 스트로크를 덮지 않는다');
  });

  test('with no canvas to lay the stroke on, it is grey', () {
    lastStroke.reinputHandler = null;
    expect(verb.canConfirm, isFalse, reason: '받을 캔버스가 없다');
    verb.confirm();
    expect(reinputs, 0);
  });
}
