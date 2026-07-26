import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/timeline_repeat.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';

/// Design E: the STORYBOARD row refuses repeat/hold regions. A derived
/// instance would look exactly like a conte panel while owning no memo of
/// its own, so the answer is to copy the frames instead.
void main() {
  test('a repeat region is refused on a storyboard row and still lands on '
      'an animation row', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    // The default animation row takes one.
    s.createDrawingAtCurrentFrame();
    final animationId = s.activeLayer!.id;
    s.setRunEdgeBehavior(
      layerId: animationId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );
    expect(
      s.layers.firstWhere((layer) => layer.id == animationId).runBehaviors,
      isNotEmpty,
    );

    // The same call on a storyboard row changes nothing.
    s.addLayerOfKind(LayerKind.storyboard);
    final storyboardId = s.activeLayer!.id;
    expect(s.activeLayer!.kind, LayerKind.storyboard);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.setRunEdgeBehavior(
      layerId: storyboardId,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.repeat,
    );

    final storyboard = s.layers.firstWhere((layer) => layer.id == storyboardId);
    expect(storyboard.runBehaviors, isEmpty);
    expect(storyboard.timeline.values.any((entry) => entry.ghost), isFalse);
  });
}
