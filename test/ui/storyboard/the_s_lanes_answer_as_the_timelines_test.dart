import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

import '../../helpers/named_finders.dart';

/// I-89 ① ⓕ (2026-10-20) — what the conte panel's S rows answer, against
/// the timeline's (유저 2026-10-13: 「다시 말하지만 이런건 다 콘티패널에도
/// 동일하게 있어야해. 같은 법으로」):
///
/// * a lane cell's double click opens or keys the cell it NAMES, as the
///   timeline's door does — it answered where the first click had stood;
/// * a lane's strip shows a key slid in flight where its label does — it
///   drew the committed keys.
///
/// The row's sound wearing its gain and fades is pinned beside the row's
/// other strips (`storyboard_lane_controls_test`).
void main() {
  Layer seRow(EditorSessionManager s, LayerId id) =>
      s.activeTrack.seLayers.firstWhere((layer) => layer.id == id);

  /// The conte panel over a fresh session, its first S row holding
  /// [rowOf]'s answer, its lanes and their Transform group twirled down.
  Future<(EditorSessionManager, LayerId)> pumpSeLanes(
    WidgetTester tester, {
    Layer Function(Layer row)? rowOf,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final se = s.activeTrack.seLayers.first;
    if (rowOf != null) {
      s.repository.replaceLayer(layer: rowOf(se));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: s,
            builder: (context, _) => StoryboardTabHost(
              session: s,
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.named('storyboard-lane-toggle-${se.id}'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.named('storyboard-lane-group-toggle-${se.id}-transform-group'),
    );
    await tester.pumpAndSettle();
    return (s, se.id);
  }

  TimelineLaneFrameRow strip(WidgetTester tester, LayerId se) =>
      tester.widget<TimelineLaneFrameRow>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TimelineLaneFrameRow &&
              widget.layer.id == se &&
              widget.lane.laneId == 'position',
        ),
      );

  testWidgets('a lane cell\'s double click keys the cell it names, not the '
      'one the first click stood on', (tester) async {
    final (s, se) = await pumpSeLanes(tester);
    s.standOnRow(
      LaneRowAddress(se, 'position'),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 2,
    );
    await tester.pumpAndSettle();
    expect(seRow(s, se).transformTrack.keyedFrames, isEmpty, reason: '⛔전제');

    strip(tester, se).laneRange!.onActivateAt!(se, 'position', 6);
    await tester.pumpAndSettle();

    expect(s.editingGlobalFrame, 6);
    expect(seRow(s, se).transformTrack.keyedFrames, {6});
  });

  testWidgets('a lane cell holding a key opens the key\'s window', (
    tester,
  ) async {
    final (s, se) = await pumpSeLanes(
      tester,
      rowOf: (row) => row.copyWith(
        transformTrack: TransformTrack(
          keyframes: {6: TransformPose(center: CanvasPoint(x: 9, y: 9))},
        ),
      ),
    );
    s.standOnRow(
      LaneRowAddress(se, 'position'),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 6,
    );
    await tester.pumpAndSettle();

    strip(tester, se).laneRange!.onActivateAt!(se, 'position', 6);
    await tester.pumpAndSettle();

    expect(find.text(AppText.strings.renameKeyTitle), findsOneWidget);
  });

  testWidgets('a lane\'s strip shows a key slid in flight where its label '
      'does', (tester) async {
    final (s, se) = await pumpSeLanes(
      tester,
      rowOf: (row) => row.copyWith(
        transformTrack: TransformTrack(
          keyframes: {0: TransformPose(center: CanvasPoint(x: 9, y: 9))},
        ),
      ),
    );
    final lanes = strip(tester, se).laneRange!;
    expect(strip(tester, se).lane.keyMarks.keys, [0], reason: '⛔전제');

    lanes.onSelectUpdate(se, 'position', 0, 0, 0);
    expect(lanes.onMoveBegin(), isTrue, reason: '⛔전제');
    lanes.onMoveUpdate(3);
    await tester.pump();

    expect(strip(tester, se).lane.keyMarks.keys, [3]);
    expect(
      seRow(s, se).transformTrack.keyedFrames,
      {0},
      reason: '⛔전제: in flight, nothing written',
    );
    lanes.onMoveCancel();
    await tester.pump();
    expect(strip(tester, se).lane.keyMarks.keys, [0]);
  });
}
