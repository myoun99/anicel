import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/fx_basis.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/lane_row_slice.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show
        canvasManipulatorsForLane,
        transformGroupHeaderLane,
        transformLaneDisplayOrder;

import '../../helpers/timeline_host.dart';

/// R5 #7 — the name tag reaches the rail as a fixed lane GROUP on every SE
/// row, its members holding the row's pose (audio-fx-grows-like-the-pros-Q3
/// · Q4).
void main() {
  const seLayerId = LayerId('nt-se');

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('nt-project'),
      name: 'Name Tag',
      createdAt: DateTime.utc(2026, 8, 9),
      tracks: [
        Track(
          id: const TrackId('nt-track'),
          name: 'Video',
          seLayers: [
            Layer(
              id: seLayerId,
              name: 'S1',
              kind: LayerKind.se,
              frames: const [],
              timeline: const {},
            ),
          ],
          cuts: [
            Cut(
              id: const CutId('nt-cut'),
              name: 'Cut',
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(
                  id: const LayerId('nt-cel'),
                  name: 'A',
                  frames: const [],
                  timeline: const {},
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> pumpHost(WidgetTester tester, EditorSessionManager s) async {
    addTearDown(s.dispose);
    await pumpTimelineHostOn(
      tester,
      s,
      surface: const Size(1400, 900),
      pixelsPerFrame: 24,
    );
  }

  testWidgets('a DRAWING row has no name-tag lanes — the group belongs to '
      'SE rows alone', (tester) async {
    final s = session();
    await pumpHost(tester, s);
    final cel = s.layers.firstWhere(
      (layer) => layer.id == const LayerId('nt-cel'),
    );
    expect(
      timelineLanesForLayer(
        layer: cel,
        session: s,
        expandedGroupKeys: {},
      ).where((lane) => laneIsSeNameTag(lane.laneId)),
      isEmpty,
    );
  });

  Layer seRow(EditorSessionManager s) =>
      s.layers.firstWhere((layer) => layer.id == seLayerId);

  testWidgets('the group has a header and seven members, and they are the '
      'ones the user listed', (tester) async {
    final s = session();
    await pumpHost(tester, s);
    final seLayer = seRow(s);

    final lanes = timelineLanesForLayer(
      layer: seLayer,
      session: s,
      expandedGroupKeys: {},
    );
    final header = lanes.where(
      (lane) => lane.laneId == seNameTagGroupLaneId,
    );
    expect(header, hasLength(1), reason: 'auto-present, never added');
    expect(
      header.single.isGroupHeader,
      isTrue,
    );
    expect(
      header.single.previewText,
      isNotNull,
      reason: 'the header carries its preview',
    );

    final expanded = timelineLanesForLayer(
      layer: seLayer,
      session: s,
      expandedGroupKeys: {'${seLayerId.value}|$seNameTagGroupLaneId'},
    );
    expect(
      expanded
          .where((lane) => lane.laneId.startsWith('name-tag:'))
          .map((lane) => lane.laneId)
          .toList(),
      seNameTagLaneDisplayOrder,
    );
  });

  testWidgets('🎯the S row\'s transform is no group of its own: its lanes '
      'are the name tag\'s members, after its own, and the header wears its '
      'switch, its basis chip and its keys (audio-fx-grows-like-the-pros-Q3 · '
      'Q4)', (tester) async {
    final s = session();
    await pumpHost(tester, s);
    s.laneVerbs.setLaneValueAt(
      seLayerId,
      'rotation',
      3,
      '30°',
      frameIsGlobal: false,
      description: 'Edit Rotation',
      scaleLinked: false,
    );
    final seLayer = seRow(s);
    expect(seLayer.transformTrack.rotation.keys.keys, [3], reason: '⛔전제');

    final folded = timelineLanesForLayer(
      layer: seLayer,
      session: s,
      expandedGroupKeys: {},
    );
    expect(
      folded.map((lane) => lane.laneId),
      isNot(contains(transformGroupHeaderLane.laneId)),
    );
    final header = folded.singleWhere(
      (lane) => lane.laneId == seNameTagGroupLaneId,
    );
    expect(header.groupEnabled, seLayer.transformEnabled);
    expect(header.groupBasis, seLayer.transformBasis);
    expect(header.headsAGraph, isTrue);
    expect(header.keyMarks.keys, [3], reason: 'the pose\'s keys in its union');

    final ids = timelineLanesForLayer(
      layer: seLayer,
      session: s,
      expandedGroupKeys: {'${seLayerId.value}|$seNameTagGroupLaneId'},
    ).map((lane) => lane.laneId).toList();
    final head = ids.indexOf(seNameTagGroupLaneId);
    expect(
      ids.sublist(head + 1, head + 1 + seNameTagLaneDisplayOrder.length + 5),
      [...seNameTagLaneDisplayOrder, ...transformLaneDisplayOrder],
    );
    expect(
      s.laneVerbs.laneVerbTargets([seNameTagGroupLaneId]),
      [...seNameTagLaneDisplayOrder, ...transformLaneDisplayOrder],
      reason: 'the header stands for every member it holds',
    );
  });

  test('🎯the header\'s switch is the name tag fx\'s — the row\'s transform '
      'switch, folded in (Q5: 「이름표 전체를 끈다」) — and its basis chip the '
      'pose\'s', () {
    final s = session();
    addTearDown(s.dispose);
    expect(s.laneVerbs.isLaneGroupOn(seLayerId, seNameTagGroupLaneId), isTrue);

    s.laneVerbs.toggleLaneGroupEnabled(
      seLayerId,
      seNameTagGroupLaneId,
      description: 'Toggle',
    );
    expect(seRow(s).transformEnabled, isFalse);
    expect(
      s.laneVerbs.isLaneGroupOn(seLayerId, seNameTagGroupLaneId),
      isFalse,
    );
    expect(seRow(s).effects, isEmpty, reason: 'no fx was made to switch');

    s.laneVerbs.setLaneGroupBasis(
      seLayerId,
      seNameTagGroupLaneId,
      FxBasis.block,
      description: 'Basis',
    );
    expect(seRow(s).transformBasis, FxBasis.block);
    expect(
      canvasManipulatorsForLane(seNameTagGroupLaneId),
      canvasManipulatorsForLane(transformGroupHeaderLane.laneId),
      reason: 'standing on the group is standing on the pose it holds',
    );
  });

  test('🎯the header\'s Reset answers — a typed size back to a new tag\'s, '
      'and the pose it holds back to rest, one undo (F-374: 「참조fx에서 '
      '리셋버튼도 안먹힘」, and so here)', () {
    final s = session();
    addTearDown(s.dispose);
    // What the tag shows at the frame — a typed size is a key now
    // (F-407), not the style it was made with.
    double? size() => seRow(s).seNameTag?.resolveAt(0).style.fontSize;
    double rotation() => seRow(s).transformTrack.rotation.keys[0]!.value;
    s.laneVerbs.setLaneValueAt(
      seLayerId,
      seNameTagSizeLaneId,
      0,
      '48',
      frameIsGlobal: false,
      description: 'Edit Size',
      scaleLinked: false,
    );
    s.laneVerbs.setLaneValueAt(
      seLayerId,
      'rotation',
      0,
      '30°',
      frameIsGlobal: false,
      description: 'Edit Rotation',
      scaleLinked: false,
    );
    expect(size(), 48, reason: '⛔전제: the size was typed');
    expect(rotation(), 30, reason: '⛔전제: the pose was keyed');

    expect(
      s.laneVerbs.resetsLaneGroup(seLayerId, seNameTagGroupLaneId),
      isTrue,
      reason: 'its Reset is lit off rest (F-583)',
    );
    expect(
      s.laneVerbs.resetLaneGroup(seLayerId, seNameTagGroupLaneId),
      isTrue,
    );
    expect(
      s.laneVerbs.resetsLaneGroup(seLayerId, seNameTagGroupLaneId),
      isFalse,
      reason: 'back at rest, its Reset is out (F-583)',
    );

    expect(size(), SeNameTag.defaultStyle.fontSize);
    expect(rotation(), 0);
    s.undo();
    expect(size(), 48);
    expect(rotation(), 30, reason: 'one step took both back');
  });

  test('🎯the pose alone off rest lights the Reset too', () {
    final s = session();
    addTearDown(s.dispose);
    s.laneVerbs.setLaneValueAt(
      seLayerId,
      'rotation',
      0,
      '30°',
      frameIsGlobal: false,
      description: 'Edit Rotation',
      scaleLinked: false,
    );
    expect(
      s.laneVerbs.resetsLaneGroup(seLayerId, seNameTagGroupLaneId),
      isTrue,
    );
  });

  test('🎯a pose lane is read live where the tag holds it — its key, as '
      'the rail\'s sweep asks (F-475)', () {
    final s = session();
    addTearDown(s.dispose);
    s.laneVerbs.setLaneValueAt(
      seLayerId,
      'rotation',
      0,
      '30°',
      frameIsGlobal: false,
      description: 'Edit Rotation',
      scaleLinked: false,
    );
    expect(
      s.laneVerbs.isLaneKeyedAt(seLayerId, 'rotation', 0, frameIsGlobal: false),
      isTrue,
    );
    expect(
      s.laneVerbs.isLaneKeyedAt(seLayerId, 'rotation', 5, frameIsGlobal: false),
      isFalse,
    );
  });

  test('🎯a pose edit hands the header a new row and the tag\'s own lanes '
      'the ones they had — a tag never typed included', () {
    final s = session();
    addTearDown(s.dispose);
    final before = seRow(s);
    expect(before.seNameTag, isNull, reason: '⛔전제');
    s.laneVerbs.setLaneValueAt(
      seLayerId,
      'rotation',
      0,
      '30°',
      frameIsGlobal: false,
      description: 'Edit Rotation',
      scaleLinked: false,
    );
    final after = seRow(s);
    expect(
      identical(
        laneRowSlice(before, seNameTagGroupLaneId),
        laneRowSlice(after, seNameTagGroupLaneId),
      ),
      isFalse,
      reason: 'the header shows the pose\'s keys beside the tag\'s',
    );
    for (final laneId in seNameTagLaneDisplayOrder) {
      expect(
        identical(laneRowSlice(before, laneId), laneRowSlice(after, laneId)),
        isTrue,
        reason: '$laneId shows what it showed',
      );
    }
  });
}
