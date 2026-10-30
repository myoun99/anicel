import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/track_conte_row.dart' show trackConteRowId;
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneControlsRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/home_page_probes.dart';

/// 🗣️I-132-Q28 a 「Fx 목록에 그 fx 가 회색으로 남고」 on the conte panel as
/// on the timeline: every row it draws — the V row, an S row, a conte row —
/// greys the header of an effect of a plugin this device has not, from the
/// app's one list.
void main() {
  final glow = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': <Object?>[],
  })!;
  LayerEffect glowing(String id) => LayerEffect.defaults(
    id: EffectId(id),
    kind: EffectKind.plugin,
    plugin: glow,
  );
  const conteId = LayerId('cut-1-conte');

  testWidgets('through the app: the V row\'s, an S row\'s and a conte row\'s '
      'header of one the device has not grey', (tester) async {
    final base = conteTrackProject();
    final track = base.tracks.single;
    Layer wearing(Layer row, String id) => row.copyWith(effects: [glowing(id)]);
    final project = base.copyWith(
      tracks: [
        track.copyWith(
          effects: [glowing('fx-v')],
          lanesExpanded: true,
          seLayers: [wearing(track.seLayers.single, 'fx-s')],
          cuts: [
            track.cuts.first.copyWith(
              layers: [
                for (final row in track.cuts.first.layers)
                  if (row.id == conteId) wearing(row, 'fx-c') else row,
              ],
            ),
            ...track.cuts.skip(1),
          ],
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project)),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    SessionRowButtonPresses(session)
      ..toggleLanes(conteSeId)
      ..toggleLanes(conteId);
    await tester.pumpAndSettle();

    bool? greyed(LayerId row, String effect) {
      final headers = find.descendant(
        of: find.byType(StoryboardPanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TimelineLaneControlsRow &&
              widget.layer.id == row &&
              widget.lane.laneId == effectGroupLaneId(EffectId(effect)),
        ),
      );
      return headers.evaluate().isEmpty
          ? null
          : tester
                .widget<TimelineLaneControlsRow>(headers.first)
                .lane
                .pluginNotOnDevice;
    }

    expect(greyed(trackTransformLaneCarrierId(track.id), 'fx-v'), isTrue);
    expect(greyed(conteSeId, 'fx-s'), isTrue);
    // A conte row's labels stand on the track's row at its seat.
    expect(greyed(trackConteRowId(track.id), 'fx-c'), isTrue);
  });
}
