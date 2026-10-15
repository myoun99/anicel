import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-363 (유저 2026-10-15): 「카메라 불투명도가 파일에 저장이 안되는건지 …
/// 파일 열때, 카메라 불투명도가 열기 전 열려있던 프로젝트의 카메라
/// 불투명도랑 같은상태로 열림」 → 「카메라 불투명도는 레이어랑 통일. 레이어가
/// 눈이랑 불투명도 바꾸면 언두 저장되니까. 기본적으로 레이어 버튼은 그게
/// 기준」.
///
/// The camera view is the camera row's eye and opacity (`CameraViewMode`),
/// and those are ONE head for the cameras of a track (I-73: 「눈 불투명도는
/// 물론 통일」). ↩️They were two notifiers the window held.
void main() {
  EditorSessionManager sessionOn(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  /// A track of two cuts — the second made the way a new cut is.
  EditorSessionManager twoCuts() {
    final session = sessionOn(createDefaultProject());
    session.cutVerbs.createCut();
    expect(
      session.repository.requireProject().tracks.single.cuts,
      hasLength(2),
      reason: '⛔전제',
    );
    return session;
  }

  List<Layer> camerasOf(EditorSessionManager session) => [
    for (final cut in session.repository.requireProject().tracks.single.cuts)
      cut.layers.cameraLayer!,
  ];

  Layer stoodCamera(EditorSessionManager session) =>
      session.activeCutOrNull!.layers.cameraLayer!;

  ({bool enabled, double dim}) viewOf(EditorSessionManager session) => (
    enabled: session.cameraViewMode.enabled.value,
    dim: session.cameraViewMode.dim.value,
  );

  test('the view is the camera row of the cut stood in, and its switch is '
      'that row\'s eye', () {
    final session = twoCuts();
    final camera = stoodCamera(session);
    expect(viewOf(session), (enabled: camera.isVisible, dim: camera.opacity));

    session.cameraViewMode.toggle();

    expect(stoodCamera(session).isVisible, !camera.isVisible);
    expect(viewOf(session).enabled, !camera.isVisible);
  });

  test('🚨one camera\'s eye and opacity are every camera\'s of its track — '
      'one undo each', () {
    final session = twoCuts();
    final was = camerasOf(session).first;
    final camera = stoodCamera(session).id;

    session.layerSwitches.toggleLayerVisibility(camera);
    session.opacityVerbs.commitLayerOpacity(camera, 0.3);

    expect(
      [for (final each in camerasOf(session)) (each.isVisible, each.opacity)],
      [(!was.isVisible, 0.3), (!was.isVisible, 0.3)],
    );

    session.undo();
    expect(
      [for (final each in camerasOf(session)) each.opacity],
      [was.opacity, was.opacity],
    );
    session.undo();
    expect(
      [for (final each in camerasOf(session)) each.isVisible],
      [was.isVisible, was.isVisible],
    );
  });

  test('a cut joining the track wears its cameras\' eye and opacity', () {
    final session = sessionOn(createDefaultProject());
    final camera = stoodCamera(session);
    session.layerSwitches.toggleLayerVisibility(camera.id);
    session.opacityVerbs.commitLayerOpacity(camera.id, 0.3);

    session.cutVerbs.createCut();

    final born = camerasOf(session).last;
    expect(born.id, isNot(camera.id), reason: '⛔전제: the new cut\'s');
    expect((born.isVisible, born.opacity), (!camera.isVisible, 0.3));
  });

  test('in a gap the view is the head the track\'s cameras wear, and its '
      'switch reaches every one of them', () {
    final session = twoCuts();
    final track = session.repository.requireProject().tracks.single;
    session.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    session.selectCut(track.cuts[0].id);
    session.selectGlobalFrame(track.cuts[0].duration + 1);
    expect(session.activeCutOrNull, isNull, reason: '⛔전제: a gap');
    final was = camerasOf(session).first.isVisible;
    expect(viewOf(session).enabled, was);

    session.cameraViewMode.toggle();

    expect([for (final each in camerasOf(session)) each.isVisible], [
      !was,
      !was,
    ]);
    expect(viewOf(session).enabled, !was);
  });

  test('🚨a project opened comes up in ITS camera view — the one its file '
      'keeps, not the last project\'s', () {
    final first = sessionOn(createDefaultProject());
    final camera = stoodCamera(first);
    first.layerSwitches.toggleLayerVisibility(camera.id);
    first.opacityVerbs.commitLayerOpacity(camera.id, 0.3);
    final file = buildAnicelArchiveBytes(
      project: first.repository.requireProject(),
      cels: const [],
    );

    final other = sessionOn(createDefaultProject());
    final reopened = sessionOn(parseAnicelArchiveBytes(file).project);

    expect(viewOf(reopened), (enabled: !camera.isVisible, dim: 0.3));
    expect(
      viewOf(other),
      (enabled: camera.isVisible, dim: camera.opacity),
      reason: 'each project its own',
    );
  });
}
