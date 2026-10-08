import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★A PROJECT OPENS WHERE IT WAS SAVED (F-123).
///
/// 유저 2026-09-13: 「… 액티브컷,액티브레이어,인덱스 를 저장해서 열 때
/// 반영되도록. 존재안하는게 있으면 해당 분야만 초기값으로」.
///
/// Through a real save and a real open: the door writes where the work
/// stood beside the project and reads it back. And through BOTH save roads —
/// the second save of a project appends, and an append that forgot the
/// field would reopen on the first cut as if nothing had been saved.
void main() {
  late Directory directory;
  late String projectPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-resume-');
    deleteAfterSessionEnds(directory);
    projectPath = '${directory.path}/scene.anicel';
  });

  /// The default project with a second cut, so "the first cut" and "the cut
  /// that was open" are two different answers.
  Project twoCuts() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            ...track.cuts,
            createDefaultCut(
              cutId: const CutId('c2'),
              name: '2',
              layerId: const LayerId('c2-drawing'),
            ),
          ],
        ),
      ],
    );
  }

  test('the cut, the row and the frame come back — and coming back is not '
      'an edit', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    s.selectCut(const CutId('c2'));
    // Not the top row: the top row is where an open lands anyway.
    final row = s.activeCutOrNull!.layers[1];
    s.selectLayer(row.id);
    s.selectFrameIndex(5);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.activeCutId, const CutId('c2'));
    expect(reopened.activeLayerId, row.id);
    expect(reopened.currentFrameIndex, 5);
    expect(
      reopened.cutUnderPlayhead.listenable.value,
      const CutId('c2'),
      reason: 'what shows the cut under the playhead hears the open — its '
          'settle ends in a notify',
    );
    expect(
      reopened.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'where the work stood is not an edit',
    );
    reopened.dispose();
  });

  test('🚨an APPEND save carries the newer place, not the first one', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.selectCut(const CutId('c2'));
    s.selectFrameIndex(7);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.activeCutId, const CutId('c2'));
    expect(reopened.currentFrameIndex, 7);
    reopened.dispose();
  });

  test('a cut or a row the project no longer has falls back ALONE — the '
      'frame still lands', () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(
        project: twoCuts(),
        cels: const [],
        sessionFields: const AnicelSessionFields(
          resume: {'cutId': 'gone', 'layerId': 'gone-too', 'frameIndex': 3},
        ),
      ),
    );

    final opened = await openedSession(projectPath);
    final firstCut = twoCuts().tracks.first.cuts.first;
    expect(
      opened.activeCutId,
      firstCut.id,
      reason: 'the cut is gone: the first cut, as a file without one opens',
    );
    expect(
      opened.activeLayerId,
      firstCut.layers.first.id,
      reason: 'the row is gone: the top row',
    );
    expect(
      opened.currentFrameIndex,
      3,
      reason: 'the frame is a part of its own and still lands',
    );
    opened.dispose();
  });

  test('🚨a saved row the FILE hides — its folder shut — opens standing on '
      'the folder: the standing law asks at an open too (F-169)', () async {
    const folder = LayerId('f');
    const member = LayerId('m');
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final project = base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                ...cut.layers,
                Layer(
                  id: member,
                  name: 'm',
                  frames: const [],
                  timeline: const {},
                  folderId: folder,
                ),
                createFolderLayer(id: folder, name: 'F').copyWith(
                  collapsed: true,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(
        project: project,
        cels: const [],
        sessionFields: AnicelSessionFields(
          resume: {'cutId': cut.id.value, 'layerId': member.value},
        ),
      ),
    );

    final opened = await openedSession(projectPath);
    expect(
      opened.activeLayerId,
      folder,
      reason: 'the row the file names is off the screen, so the open stands '
          'on the row that stands in for it — the shut folder',
    );
    opened.dispose();
  });

  test('a file saved before the place was kept opens as it always did',
      () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(project: twoCuts(), cels: const []),
    );

    final opened = await openedSession(projectPath);
    final firstCut = twoCuts().tracks.first.cuts.first;
    expect(opened.activeCutId, firstCut.id);
    expect(opened.activeLayerId, firstCut.layers.first.id);
    expect(opened.currentFrameIndex, 0);
    expect(opened.playbackRig.playbackMode, defaultPlaybackMode);
    opened.dispose();
  });

  test('a file that says nothing of the playback mode plays as a new '
      'project does — whatever the session played by before', () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(project: twoCuts(), cels: const []),
    );

    final opened = await openedSession(
      projectPath,
      before: (session) => session.playbackRig.setPlaybackMode(
        PlaybackMode.values.firstWhere((mode) => mode != defaultPlaybackMode),
      ),
    );

    expect(opened.playbackRig.playbackMode, defaultPlaybackMode);
    opened.dispose();
  });

  test('🚨the playback mode comes back with the file — and picking it is no '
      'edit: no undo step, no unsaved mark (유저 답 playback-quality-undo-Q1 '
      '「언두 안 됨 — 보기 설정처럼(저장은 됨)」, of the setting whose seat it '
      'took)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    final picked = PlaybackMode.values.firstWhere(
      (mode) => mode != defaultPlaybackMode,
    );

    s.playbackRig.setPlaybackMode(picked);

    expect(s.historyManager.canUndo, isFalse);
    expect(s.projectFile.hasUnsavedChanges, isFalse);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.playbackRig.playbackMode, picked);
    reopened.dispose();
  });

  test('🚨each cut comes back at the timeline zoom it was left at — through '
      'the append too — and a cut nobody zoomed is handed none (F-253 → '
      'F-267, 유저 2026-10-01: 「프로젝트와 같이 저장되도록」)', () async {
    final s = EditorSessionManager(initialProject: twoCuts());
    final first = s.activeCutId!;
    s.timelineZoom.remember(const CutId('c2'), 37.5);
    // A cut deleted since it was zoomed: the memory keeps no list of cuts.
    s.timelineZoom.remember(const CutId('gone'), 9);
    expect(
      s.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'zooming is no edit — the zoom rides beside the project',
    );
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.timelineZoom.remember(const CutId('c2'), 12);
    await s.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    s.dispose();

    final reopened = await openedSession(projectPath);
    expect(reopened.timelineZoom.zoomOf(const CutId('c2')), 12);
    expect(
      reopened.timelineZoom.zoomOf(first),
      isNull,
      reason: 'it opens at the default, not at another cut\'s zoom',
    );
    expect(
      reopened.timelineZoom.byCut.keys,
      [const CutId('c2')],
      reason: 'a cut the project no longer has falls back alone, as the '
          'cut a resume names does',
    );
    expect(reopened.projectFile.hasUnsavedChanges, isFalse);
    reopened.dispose();
  });
}
