import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

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

  /// A session that has not been anywhere yet: whatever it stands on after
  /// an open, the file put it there.
  EditorSessionManager fresh() =>
      EditorSessionManager(initialProject: createDefaultProject());

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

    final reopened = fresh();
    await reopened.projectDoor.openProjectFromFile(projectPath);
    expect(reopened.activeCutId, const CutId('c2'));
    expect(reopened.activeLayerId, row.id);
    expect(reopened.currentFrameIndex, 5);
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

    final reopened = fresh();
    await reopened.projectDoor.openProjectFromFile(projectPath);
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

    final opened = fresh();
    await opened.projectDoor.openProjectFromFile(projectPath);
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

  test('a file saved before the place was kept opens as it always did',
      () async {
    File(projectPath).writeAsBytesSync(
      buildAnicelArchiveBytes(project: twoCuts(), cels: const []),
    );

    final opened = fresh();
    await opened.projectDoor.openProjectFromFile(projectPath);
    final firstCut = twoCuts().tracks.first.cuts.first;
    expect(opened.activeCutId, firstCut.id);
    expect(opened.activeLayerId, firstCut.layers.first.id);
    expect(opened.currentFrameIndex, 0);
    opened.dispose();
  });
}
