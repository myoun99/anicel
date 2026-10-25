import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/track_se_display.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// UI-R20 #4 (the "selecting a layer got slow" regression): the sparse
/// rows (camera, SE) must reuse their cached row INSTANCES across
/// unrelated session notifies — their display identities are cached
/// upstream and their external inputs ride the memo token now.
/// The collaborator that caches the display clones — named so
/// `tool/mutation_run.dart` has a suite to run for it.
TrackSeDisplay trackSeDisplayOf(EditorSessionManager session) =>
    session.trackSe;

void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) =>
      pumpTimelineHost(tester, createDefaultProject(), pixelsPerFrame: 24);

  testWidgets('camera and SE rows keep their widget INSTANCES across an '
      'unrelated layer selection (memo hit)', (tester) async {
    final manager = await pumpHost(tester);
    final cameraLayer = manager.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    final trackSe = trackSeDisplayOf(manager);
    final seLayer = trackSe.trackSeDisplayLayers.first;

    // 🚨THE CLONE CACHE IS WHAT THE ROW MEMO STANDS ON. The display clones
    // used to be rebuilt on EVERY read, so every session notify handed the
    // grids fresh `Layer` identities and defeated every identity-keyed row
    // memo below — the 「selecting a layer got slow after adding
    // dialogue」 regression. Same source layer + same window = the SAME
    // instance back, and nothing said so: mutating the window key away
    // left this file green while the memo it exists for could never hit.
    expect(
      identical(trackSe.trackSeDisplayLayers.first, seLayer),
      isTrue,
      reason: 'a second read with nothing edited is a cache HIT',
    );

    // Sparse rows (camera/SE) render through the widget path — their
    // stable key is the frame-row area.
    final cameraRow = find.named(
      'timeline-frame-row-area-${cameraLayer.id.value}',
    );
    final seRow = find.named('timeline-frame-row-area-${seLayer.id.value}');
    expect(cameraRow, findsOneWidget);
    expect(seRow, findsOneWidget);
    final cameraBefore = tester.widget(cameraRow);
    final seBefore = tester.widget(seRow);

    // An unrelated notify: select the (already?) first drawing layer —
    // force a real notify by toggling to another anim layer if present,
    // else re-selecting still notifies through selectLayer.
    final animLayer = manager.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    manager.selectLayer(animLayer.id);
    await tester.pump();

    expect(
      identical(tester.widget(cameraRow), cameraBefore),
      isTrue,
      reason: 'the camera row must ride its memo across notifies',
    );
    expect(
      identical(tester.widget(seRow), seBefore),
      isTrue,
      reason:
          'the SE row must ride its memo across notifies '
          '(display-clone identity is cached now)',
    );
  });

  // 🚨I-57 (10-13): the row is kept by its shape, and the camera track
  // reaches it as its world — the picture is drawn again, the row is not.
  testWidgets('a camera KEY edit reaches the camera row\'s picture', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    final cameraLayer = manager.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    final cameraRow = find.named(
      'timeline-frame-row-area-${cameraLayer.id.value}',
    );
    TimelineRowCellsPainter picture() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<TimelineRowCellsPainter>()
        .singleWhere((painter) => painter.layer.id == cameraLayer.id);
    final before = tester.widget(cameraRow);
    final drawn = picture();

    manager.camera.setCameraKeyframeAtCurrentFrame(
      manager.camera.cameraPoseAtCurrentFrame,
    );
    await tester.pump();

    final track = manager.activeCutOrNull?.camera.track;
    expect(
      identical(drawn.coverageIdentity, track),
      isFalse,
      reason: 'premise: the key made a new camera track',
    );
    expect(
      identical(picture().coverageIdentity, track),
      isTrue,
      reason: 'the camera track is what the camera row\'s cells follow (㉘)',
    );
    expect(
      identical(tester.widget(cameraRow), before),
      isTrue,
      reason: 'the row\'s shape is the same',
    );
    // Drain the edit's prerender warm-up before teardown.
    await tester.pumpAndSettle();
  });
}
