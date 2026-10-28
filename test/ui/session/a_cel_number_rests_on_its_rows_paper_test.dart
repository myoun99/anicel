import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;

/// I-65: an unkeyed cel number stands where its row rests — the middle of
/// the paper the row is posed on — so the session's ◆, a range's Create and
/// the group Reset on its Position lane read that paper, as they do a
/// layer's transform.
void main() {
  late EditorSessionManager s;
  late LayerId row;
  late EffectId number;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    row = s.requireActiveCut.layers.first.id;
    s.selectLayer(row);
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
    number = s.commitLayerById(row)!.effects.single.id;
  });
  tearDown(() => s.dispose());

  CanvasPoint middle() {
    final paper = s.requireActiveCut.canvasSize;
    return CanvasPoint(x: paper.width / 2, y: paper.height / 2);
  }

  LayerEffect held() => s.commitLayerById(row)!.effects.single;

  test('the ◆ freezes it at the middle of the cut\'s canvas', () {
    s.laneVerbs.toggleLaneKeyAt(
      row,
      effectLaneId(number, 'position'),
      3,
      frameIsGlobal: false,
      description: 'Key',
    );

    expect(held().stand.position.keyAt(3)!.value, middle());
  });

  test('the group Reset puts a moved key back there', () {
    s.laneVerbs.setLaneValueAt(
      row,
      effectLaneId(number, 'position'),
      0,
      '12, 34',
      frameIsGlobal: false,
      description: 'Move',
      scaleLinked: false,
    );
    expect(held().stand.position.keyAt(0)!.value, CanvasPoint(x: 12, y: 34));

    expect(s.laneVerbs.resetLaneGroup(row, effectGroupLaneId(number)), isTrue);

    expect(held().stand.position.keyAt(0)!.value, middle());
  });

  test('a range\'s Create keys it there on every frame it covers', () {
    final range = TimelineLaneSelection(
      layerId: row,
      laneId: effectLaneId(number, 'position'),
      startIndex: 2,
      endIndexExclusive: 4,
    );

    s.laneVerbs.createLaneKeysForSelection(range);

    expect(held().stand.position.keys.keys, [2, 3]);
    expect(held().stand.position.keyAt(2)!.value, middle());
  });
}
