import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
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

    s.undo();
    expect(s.currentFrameIndex, 2, reason: '그곳으로 이동만');
    expect(drawingsOn(s, row), made, reason: '⛔되돌리지는 않았다');

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

  test('a place whose cut is GONE is nowhere to walk to — the undo takes the '
      'edit back at once', () {
    final s = session();
    final cuts = twoCuts(s);
    Iterable<CutId> cutIds() => s.repository
        .requireProject()
        .tracks
        .expand((track) => track.cuts)
        .map((cut) => cut.id);
    s.selectCut(cuts.second);
    final entries = s.historyManager.undoCount;
    s.cutVerbs.deleteActiveCut();
    expect(cutIds(), isNot(contains(cuts.second)), reason: '⛔전제: 컷이 지워졌다');

    s.undo();
    expect(s.historyManager.undoCount, entries, reason: '걷지 않고 바로 되돌렸다');
    expect(cutIds(), contains(cuts.second));
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

  test('a place whose ROW is gone is taken back where its cut and frame '
      'match — a walk to it would arrive nowhere', () {
    final s = session();
    final row = s.activeLayerId!;
    final cut = s.activeCutId!;
    final other = otherRowOf(s);
    s.cutVerbs.renameActiveCut('renamed'); // made standing on [row]
    s.selectLayer(other);
    // The row goes without the history hearing of it.
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
    final entries = s.historyManager.undoCount;

    s.undo();
    expect(
      s.historyManager.undoCount,
      entries - 1,
      reason: '걷지 않고 바로 — 없는 행으로 걸으면 매번 제자리걸음이다',
    );
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
}
