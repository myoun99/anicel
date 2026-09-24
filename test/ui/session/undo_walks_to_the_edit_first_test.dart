import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;

/// 🚨★★★I-41 — UNDO WALKS TO THE EDIT FIRST, AND REDO IS ITS MIRROR.
///
/// 🗣️유저 2026-09-24: 「그렇게 하자 … 아무튼 그곳으로 이동해서
/// 편집되돌리고 리두대칭」. The history keeps where the user stood for every
/// edit (the cut, the row, the frame); standing anywhere else, the first
/// undo only walks there and the next one takes the edit back. Redo brings
/// the edit back, and the redo after it walks back to where the undo began.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  int drawingsOn(EditorSessionManager s, LayerId row) =>
      s.layers.firstWhere((layer) => layer.id == row).frames.length;

  /// A drawing row to stand on besides the active one.
  LayerId otherRowOf(EditorSessionManager s) => s.layers
      .firstWhere(
        (layer) =>
            layer.id != s.activeLayerId &&
            layer.kind != LayerKind.camera &&
            !layer.kind.groupsLayers,
      )
      .id;

  test('standing on another FRAME, the first undo walks there and the '
      'second takes the edit back', () {
    final s = session();
    final row = s.activeLayerId!;
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    s.selectFrameIndex(7);
    final reveals = s.revealSelectionTick.value;

    s.undo();
    expect(s.currentFrameIndex, 2, reason: '그곳으로 이동만');
    expect(drawingsOn(s, row), made, reason: '⛔되돌리지는 않았다');
    expect(
      s.revealSelectionTick.value,
      greaterThan(reveals),
      reason: 'F-169 ③ 「스크롤밖이면 스크롤 조정」 — the rails are asked to '
          'bring the place into view, a row on screen or not',
    );

    s.undo();
    expect(drawingsOn(s, row), made - 1, reason: '다음 언두가 편집을 되돌린다');
    expect(s.currentFrameIndex, 2);
  });

  test('standing where the edit was made, the undo takes it back at once', () {
    final s = session();
    final row = s.activeLayerId!;
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);

    s.undo();
    expect(drawingsOn(s, row), made - 1);
  });

  test('redo is the mirror: the edit comes back, then the next redo walks '
      'back to where the undo began', () {
    final s = session();
    final row = s.activeLayerId!;
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    s.selectFrameIndex(7);
    s
      ..undo()
      ..undo();
    expect(drawingsOn(s, row), made - 1, reason: '⛔전제: 걸어가서 되돌렸다');

    s.redo();
    expect(drawingsOn(s, row), made, reason: '리두가 편집을 되살린다');
    expect(s.currentFrameIndex, 2);

    s.redo();
    expect(s.currentFrameIndex, 7, reason: '다음 리두가 언두 전 자리로 돌아간다');
    expect(drawingsOn(s, row), made);
    expect(s.historyManager.canRedo, isFalse, reason: '돌아가는 걸음은 한 번 쓰면 끝');
  });

  test('a redo right after the walk walks straight back — and the next undo '
      'walks again', () {
    final s = session();
    final row = s.activeLayerId!;
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    s.selectFrameIndex(7);

    s.undo();
    expect(s.currentFrameIndex, 2, reason: '⛔전제: 걸어갔다');
    s.redo();
    expect(s.currentFrameIndex, 7, reason: '되돌아왔다');
    expect(drawingsOn(s, row), made, reason: '편집은 그대로');

    s.undo();
    expect(s.currentFrameIndex, 2, reason: '다시 걸어간다 — 같은 법');
    expect(drawingsOn(s, row), made);
  });

  test('standing on another ROW, the walk stands on the row the edit was '
      'made on', () {
    final s = session();
    final row = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    final other = otherRowOf(s);
    s.selectLayer(other);
    expect(s.activeLayerId, other, reason: '⛔전제: 다른 행에 섰다');

    s.undo();
    expect(s.activeLayerId, row, reason: '그 편집의 행으로');
    expect(drawingsOn(s, row), made);

    s.undo();
    expect(drawingsOn(s, row), made - 1);
  });

  /// A second cut, and a history that has not heard about making it.
  ({CutId first, CutId second}) twoCuts(EditorSessionManager s) {
    final first = s.activeCutId!;
    s.cutVerbs.createCut();
    final second = s.repository
        .requireProject()
        .tracks
        .expand((track) => track.cuts)
        .firstWhere((cut) => cut.id != first)
        .id;
    s.historyManager.clear();
    return (first: first, second: second);
  }

  test('standing in another CUT, the walk goes to the cut the edit was made '
      'in', () {
    final s = session();
    final cuts = twoCuts(s);
    s.selectCut(cuts.first);
    final row = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    s.selectCut(cuts.second);
    expect(s.activeCutId, cuts.second, reason: '⛔전제: 다른 컷에 섰다');

    s.undo();
    expect(s.activeCutId, cuts.first, reason: '그 편집의 컷으로');
    expect(s.activeLayerId, row);
    expect(drawingsOn(s, row), made, reason: '⛔되돌리지는 않았다');

    s.undo();
    expect(drawingsOn(s, row), made - 1);
  });

  /// Takes [cut] away without the history hearing of it.
  ///
  /// ⚠️The only way an entry's place can be gone by the time the entry is on
  /// top again: through history, everything done after it has been taken
  /// back first — its cut and its row with it. 🧪A cut deleted THROUGH
  /// history never reached the check: the delete is looked at from the cut
  /// it handed the user to, so its undo was never a walk to begin with.
  void dropCutOutsideHistory(EditorSessionManager s, CutId cut) {
    s.repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(
              cuts: [
                for (final each in track.cuts)
                  if (each.id != cut) each,
              ],
            ),
        ],
      ),
    );
    s.refreshAfterCutCommand();
  }

  /// Takes [row] out of [cut] without the history hearing of it (see
  /// [dropCutOutsideHistory]).
  void dropRowOutsideHistory(EditorSessionManager s, CutId cut, LayerId row) {
    s.repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(
              cuts: [
                for (final each in track.cuts)
                  if (each.id == cut)
                    each.copyWith(
                      layers: [
                        for (final layer in each.layers)
                          if (layer.id != row) layer,
                      ],
                    )
                  else
                    each,
              ],
            ),
        ],
      ),
    );
    s.refreshAfterCutCommand();
  }

  test('a place whose cut is GONE is nowhere to walk to — the undo takes the '
      'edit back at once', () {
    final s = session();
    final cuts = twoCuts(s);
    s.selectCut(cuts.second);
    final fps = s.projectSettings.projectFps;
    // A project edit, so taking it back needs nothing of the cut.
    s.projectSettings.setProjectFps(fps + 1);
    s.selectCut(cuts.first);
    dropCutOutsideHistory(s, cuts.second);
    final entries = s.historyManager.undoCount;

    s.undo();
    expect(
      s.historyManager.undoCount,
      entries - 1,
      reason: '걷지 않고 바로 — 없는 컷으로 걸으면 매번 제자리걸음이다',
    );
    expect(s.projectSettings.projectFps, fps);
  });

  test('the way back to a cut that has gone since walks nowhere', () {
    final s = session();
    final cuts = twoCuts(s);
    s.selectCut(cuts.first);
    s.createDrawingAtCurrentFrame();
    s.selectCut(cuts.second);
    s.undo();
    expect(s.activeCutId, cuts.first, reason: '⛔전제: 첫 컷으로 걸어갔다');
    dropCutOutsideHistory(s, cuts.second);

    s.redo();
    expect(s.activeCutId, cuts.first, reason: '돌아갈 컷이 없으니 그 자리에');
    expect(s.historyManager.canRedo, isFalse, reason: '돌아가는 걸음은 쓰였다');
  });

  /// What the app does between two inputs: the action settles.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// A row inside a folder, and a drawing made on it.
  ({LayerId row, LayerId folder, int made}) drawingInAFolder(
    EditorSessionManager s,
  ) {
    final row = s.activeLayerId!;
    s.folders.groupActiveLayerIntoFolder();
    final folder = s.layers.firstWhere((layer) => layer.kind.groupsLayers).id;
    s
      ..selectLayer(row)
      ..createDrawingAtCurrentFrame();
    return (row: row, folder: folder, made: drawingsOn(s, row));
  }

  bool shut(EditorSessionManager s, LayerId folder) =>
      s.layers.firstWhere((layer) => layer.id == folder).collapsed;

  test('a FOLD is undone where it left the user — on the folder row it '
      'handed them to — so the first undo takes it back', () async {
    // ⚠️Where the action LEFT the user: the fold seats them on the folder
    // row, and that is the row they look at the fold from.
    final s = session();
    final made = drawingInAFolder(s);
    await settle();
    s.folders.toggleLayerCollapsed(made.folder);
    await settle();
    expect(shut(s, made.folder), isTrue, reason: '⛔전제: 폴더가 접혔다');
    expect(s.activeLayerId, made.folder, reason: '⛔전제: 폴더 행이 받았다');
    final entries = s.historyManager.undoCount;

    s.undo();
    expect(shut(s, made.folder), isFalse, reason: '접기를 되돌렸다');
    expect(s.historyManager.undoCount, entries - 1, reason: '걷지 않고 바로');
  });

  test('a row inside a folder shut OUTSIDE history: the walk opens it — '
      'outside history too, so the next undo is still the edit\'s', () async {
    // 🗣️F-169 ②: 「언두시에 접혀있는 레이어로 이동하면 펼치고 해당 레이어에
    // 서게」. Written into history, the unfolding would clear the redo side
    // and make the next undo the folder's instead of the edit's.
    final s = session();
    final made = drawingInAFolder(s);
    await settle();
    s.repository.updateLayer(
      layerId: made.folder,
      update: (layer) => layer.copyWith(collapsed: true),
    );
    s.refreshAfterCutCommand();
    expect(shut(s, made.folder), isTrue, reason: '⛔전제: 폴더가 접혔다');
    expect(s.activeLayerId, made.folder, reason: '⛔전제: 폴더 행이 받았다');
    final entries = s.historyManager.undoCount;

    s.undo();
    expect(s.activeLayerId, made.row, reason: '편집한 행에 섰다');
    expect(shut(s, made.folder), isFalse, reason: '그러려고 폴더를 폈다');
    expect(
      s.historyManager.undoCount,
      entries,
      reason: '⛔편 것은 히스토리에 없다',
    );

    s.undo();
    expect(drawingsOn(s, made.row), made.made - 1, reason: '다음 언두가 그림');
  });

  test('a row a folded ATTACH group hides: the walk opens the group — the '
      'rail\'s view, the same door every landing uses', () async {
    // 🗣️F-169 ②: 「언두시에 접혀있는 레이어로 이동하면 펼치고 해당 레이어에
    // 서게」. Walked without it, the row would be handed straight back to a
    // shown one (①) and the walk would arrive nowhere.
    final s = session();
    final base = s.activeLayerId!;
    s.folders.addAttachedLayer(AttachedPlacement.below);
    final attached = s.activeLayerId!;
    expect(attached, isNot(base), reason: '⛔전제: 붙인 행에 섰다');
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, attached);
    await settle();
    s.selectLayer(base);
    s.railView.collapsedAttachBaseIds.value = {base};

    s.undo();
    expect(s.activeLayerId, attached, reason: '그 편집의 행에 섰다');
    expect(
      s.railView.collapsedAttachBaseIds.value,
      isEmpty,
      reason: '그러려고 그룹을 폈다',
    );
    expect(drawingsOn(s, attached), made, reason: '⛔되돌리지는 않았다');
  });

  test('a place whose ROW is gone is taken back where its cut and frame '
      'match — a walk to it would arrive nowhere', () {
    final s = session();
    final row = s.activeLayerId!;
    final cut = s.activeCutId!;
    final other = otherRowOf(s);
    s.cutVerbs.renameActiveCut('renamed'); // made standing on [row]
    s.selectLayer(other);
    dropRowOutsideHistory(s, cut, row);
    final entries = s.historyManager.undoCount;

    s.undo();
    expect(
      s.historyManager.undoCount,
      entries - 1,
      reason: '걷지 않고 바로 — 없는 행으로 걸으면 매번 제자리걸음이다',
    );
  });

  test('a walk to a place whose row has gone still arrives at its frame', () {
    final s = session();
    final row = s.activeLayerId!;
    final cut = s.activeCutId!;
    final other = otherRowOf(s);
    s.selectFrameIndex(2);
    s.cutVerbs.renameActiveCut('renamed'); // made on [row], at frame 2
    s
      ..selectLayer(other)
      ..selectFrameIndex(7);
    dropRowOutsideHistory(s, cut, row);

    s.undo();
    expect(s.currentFrameIndex, 2, reason: '프레임까지는 간다');
    expect(s.activeLayerId, other, reason: '없는 행에는 설 수 없다');
  });

  test('the next edit settles the one before it — a new row and a drawing '
      'on it undo in two presses', () {
    // ⚠️No pause between them: the drawing's own push is the moment the
    // new row's action is over, wherever it left the user.
    final s = session();
    final rows = s.layers.length;
    s.layerStack.addLayer();
    s.createDrawingAtCurrentFrame();

    s
      ..undo()
      ..undo();
    expect(s.layers.length, rows, reason: '새 행은 그 자리에서 바로 되돌렸다');
  });

  test('an edit settles by itself — playback carrying the playhead off '
      'afterwards does not move where it was made', () async {
    final s = session();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    await settle();
    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    s.playbackRig.playback.seekToGlobalFrame(9);
    s.playbackRig.playback.stop();
    expect(s.currentFrameIndex, isNot(2), reason: '⛔전제: 재생이 옮겼다');

    s.undo();
    expect(s.currentFrameIndex, 2, reason: '편집한 자리로 걸어간다');
  });

  test('a new row seats the user on it, and its undo takes it back at once '
      '— not a walk back to the row it replaced', () async {
    final s = session();
    final rows = s.layers.length;
    s.layerStack.addLayer();
    await settle();
    expect(s.layers.length, rows + 1, reason: '⛔전제: 새 행');

    s.undo();
    expect(s.layers.length, rows, reason: '첫 언두가 바로 되돌린다');
  });

  test('a redo made from elsewhere walks to the edit first', () {
    final s = session();
    final row = s.activeLayerId!;
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    s.undo();
    expect(drawingsOn(s, row), made - 1, reason: '⛔전제: 그 자리에서 되돌렸다');
    s.selectFrameIndex(9);

    s.redo();
    expect(s.currentFrameIndex, 2, reason: '먼저 그곳으로');
    expect(drawingsOn(s, row), made - 1, reason: '⛔아직 되살리지 않았다');

    s.redo();
    expect(drawingsOn(s, row), made);
  });

  test('an undo that MOVES the user is redone from where it left them, at '
      'once — a deleted row comes back and is stood on', () async {
    // ⚠️A step is stamped where it leaves the user, like a push: the redo
    // side is looked at from there. Kept at the delete's own place, the
    // redo would walk off the row the undo had just stood the user on.
    final s = session();
    bool present(LayerId row) => s.layers.any((layer) => layer.id == row);
    s.layerStack.addLayer();
    final doomed = s.activeLayerId!;
    await settle();
    s.layerVerbs.deleteActiveLayer();
    await settle();
    expect(present(doomed), isFalse, reason: '⛔전제: 지웠다');

    s.undo();
    expect(s.activeLayerId, doomed, reason: '⛔전제: 돌아온 행에 섰다');

    s.redo();
    expect(present(doomed), isFalse, reason: '걷지 않고 바로 다시 지운다');
  });

  test('the rail\'s own door settles the edit first — a row stood on in the '
      'same breath as the edit is still a move of the user\'s', () {
    final s = session();
    final row = s.activeLayerId!;
    s.createDrawingAtCurrentFrame();
    final made = drawingsOn(s, row);
    s.standOnRow(LayerRowAddress(otherRowOf(s)));

    s.undo();
    expect(s.activeLayerId, row, reason: '그 편집의 행으로 걸어간다');
    expect(drawingsOn(s, row), made, reason: '⛔되돌리지는 않았다');
  });

  test('parking in the runway settles the edit first — the new row it seated '
      'the user on is where its undo is taken back', () {
    final s = session();
    final cut = s.activeCutId!;
    final rows = s.layers.length;
    s.layerStack.addLayer();
    final made = s.activeLayerId!;
    s.selectGlobalFrame(9999);
    expect(s.activeCutId, isNull, reason: '⛔전제: 컷 밖에 주차했다');
    s.selectCut(cut);
    expect(s.activeLayerId, made, reason: '⛔전제: 새 행으로 돌아왔다');

    s.undo();
    expect(s.layers.length, rows, reason: '걷지 않고 바로 되돌린다');
  });
}
