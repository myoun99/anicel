import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

import '../../helpers/transform_tool_on_canvas.dart';
import '../../helpers/wait_window.dart';

/// 🔎검증/서피스 (2026-11-21, card a-mesh-warp-turns-the-selection-into-its-
/// box): 「올가미 타원을 メッシュワープ 로 변형하면 … 상자 테두리 사각형으로
/// 바뀌고, 엔터로 확정하면 선택이 그 사각형이 된다 — 自由変形 은 모양 그대로」.
/// A selection goes where the box takes its pixels, whichever way the box
/// warps (`StampCarry.regionThrough`): the ants as the session moves it,
/// and the selection the confirm lands.
void main() {
  // In the square's own box, so the mesh's grid stands where it does under
  // the square ([transformToolFirstInside] at (320,220)).
  final diamond = CanvasSelectionRegion.shape(
    CanvasSelectionShape([
      CanvasPoint(x: 330, y: 200),
      CanvasPoint(x: 360, y: 230),
      CanvasPoint(x: 330, y: 260),
      CanvasPoint(x: 300, y: 230),
    ]),
  );
  // The fixture's ink at (310,210), outside the diamond: nothing lifts it,
  // and the mesh moves none of it.
  final leftBehind = CanvasPoint(x: 310, y: 210);
  // Inside the diamond, in a cell no node of which is pulled.
  final kept = CanvasPoint(x: 345, y: 230);

  testWidgets('🚨a lasso the mesh warps keeps its own shape — the ants as '
      'it goes and the selection it lands, holding none of the ink the mesh '
      'never moved', (tester) async {
    final tool = await pumpTransformTool(
      tester,
      options: const TransformToolOptions(mode: TransformMode.mesh),
      selected: false,
    );
    tool.commands.setRegion(diamond);
    await tester.pump();
    await tester.pump();

    await dragOnTransformLayer(
      tester,
      const Offset(320, 220),
      const Offset(332, 215),
    );
    final shown = antsOnScreen(tester).committedRegion!;
    expect(shown, isNot(same(diamond)), reason: '⛔premise: the mesh moved');
    expect(shown.containsPoint(kept), isTrue);
    expect(shown.containsPoint(leftBehind), isFalse, reason: 'the ants');

    await windowBehind(tester, () async => tool.commands.applyTransform());
    await tester.pump();

    final landed = tool.commands.region!;
    expect(landed, isNot(same(diamond)), reason: '⛔premise: it landed');
    expect(landed.containsPoint(kept), isTrue);
    expect(landed.containsPoint(leftBehind), isFalse, reason: 'it landed');
  });
}
