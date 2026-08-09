import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// R5 #7 — the name tag reaches the rail as a fixed lane GROUP, Transform's
/// sibling, on every SE row.
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
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: s,
            builder: (context, _) => TimelineTabHost(
              session: s,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the group has a header and seven members, and they are the '
      'ones the user listed', (tester) async {
    final s = session();
    await pumpHost(tester, s);
    final seLayer = s.layers.firstWhere((layer) => layer.id == seLayerId);

    final lanes = timelineLanesForLayer(layer: seLayer, session: s, expandedGroupKeys: {});
    final header = lanes.where(
      (lane) => lane.laneId == seNameTagGroupLaneId,
    );
    expect(header, hasLength(1), reason: 'auto-present, never added');
    expect(
      header.single.isGroupHeader,
      isTrue,
    );
    expect(
      header.single.groupEnabled,
      isNull,
      reason: 'a FIXED group has no bypass — the row eye covers it',
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

  testWidgets('the group sits ABOVE Transform — it is a sibling, and the '
      'thing you type into belongs nearer the row', (tester) async {
    final s = session();
    await pumpHost(tester, s);
    final seLayer = s.layers.firstWhere((layer) => layer.id == seLayerId);
    final ids = timelineLanesForLayer(
      layer: seLayer,
      session: s,
      expandedGroupKeys: {},
    ).map((lane) => lane.laneId).toList();
    expect(
      ids.indexOf(seNameTagGroupLaneId),
      lessThan(ids.indexOf('transform-group')),
    );
  });

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
}
