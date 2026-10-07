import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/app_clipboard.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🚨I-77 — THE SHARED PILL'S COPY AND ITS TWO PASTES SERVE ROWS.
///
/// 유저 2026-10-06: 「복사/붙여넣기버튼 레이어도 연결. 레이어 선택,다중선택
/// 등에서 복사 붙여넣기버튼 가능하게. 그러고 레이어버튼의 레이어복사/
/// 붙여넣기는 필요없으니 삭제」 · 「타임라인의 공용 복사/독립붙여넣기/
/// 링크붙여넣기를 말한거였음. 링크해서 복제도 필요없어지니 삭제」.
///
/// Three sentences, pinned below in that order:
///
/// * the COPY asks the pill's one ladder — the selected rows, else the frame
///   axis (「선택안하면 현재프레임, 선택하면 해당 선택한 소재가 기준임」);
/// * ONE copy is in hand (F-161: 「복사는 언제나 하나 들고있음. 보통
///   프로그램이 그러니까」), so a paste asks nothing: it puts down what the
///   hand holds, above the row you stand on;
/// * the LINKED paste is what the layer menu's 「링크해서 복제」 was, of
///   every row the hand holds.
///
/// The collaborators are held BY THEIR OWN TYPES so the mutation runner
/// names this file as their witness (it picks witnesses by import).
void main() {
  LayerClipboard rowsOf(EditorSessionManager s) => s.layerClipboard;
  FrameClipboard framesOf(EditorSessionManager s) => s.clipboard;
  LayerVerbs layersOf(EditorSessionManager s) => s.layerVerbs;

  EditorSessionManager session({AppClipboard? board}) {
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      appClipboard: board,
    );
    addTearDown(s.dispose);
    return s;
  }

  TimelineToolbarPanelContext pill(EditorSessionManager s) =>
      TimelineToolbarPanelContext(s);

  /// The cut's drawing rows, bottom → top.
  List<Layer> drawingRows(EditorSessionManager s) => [
    for (final layer in s.requireActiveCut.layers)
      if (layer.kind == LayerKind.animation) layer,
  ];

  List<String> names(EditorSessionManager s) => [
    for (final layer in drawingRows(s)) layer.name,
  ];

  /// A cut of three drawing rows — A, B, C from the bottom — standing on A.
  ({EditorSessionManager s, LayerId a, LayerId b, LayerId c}) threeRows({
    AppClipboard? board,
  }) {
    final s = session(board: board);
    final a = s.activeLayerId!;
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final b = s.activeLayerId!;
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final c = s.activeLayerId!;
    expect(names(s), ['A', 'B', 'C'], reason: '⛔전제');
    s.selectLayer(a);
    return (s: s, a: a, b: b, c: c);
  }

  /// The rows named, selected the way a rail press selects them.
  void select(EditorSessionManager s, List<LayerId> ids) {
    s.rowSelectionVerbs.beginRowSelection(LayerRowAddress(ids.first));
    s.rowSelectionVerbs.rowSelection.value = [
      for (final id in ids) LayerRowAddress(id),
    ];
  }

  bool holdsFrames(EditorSessionManager s) =>
      framesOf(s).copiedFrameStatusText != 'Copy: -';

  group('the copy asks the pill\'s one ladder', () {
    test('with no row selected it is the frame axis\'s', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();

      pill(r.s).copyFrame();

      expect(holdsFrames(r.s), isTrue);
      expect(rowsOf(r.s).hasLayerClipboard, isFalse);
    });

    test('selected rows outrank it: the copy takes the ROWS, and the frame '
        'copy is let go', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      pill(r.s).copyFrame();
      expect(holdsFrames(r.s), isTrue, reason: '⛔전제: frames were in hand');

      select(r.s, [r.b]);
      expect(pill(r.s).canCopyFrame, isTrue);
      pill(r.s).copyFrame();

      expect(rowsOf(r.s).hasLayerClipboard, isTrue);
      expect(
        holdsFrames(r.s),
        isFalse,
        reason: 'ONE copy in hand — the pastes put down the rows now',
      );
    });

    test('and a frame copy lets the rows go', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      select(r.s, [r.a]);
      pill(r.s).copyFrame();
      expect(rowsOf(r.s).hasLayerClipboard, isTrue, reason: '⛔전제');

      r.s.clearRowSelection();
      pill(r.s).copyFrame();

      expect(holdsFrames(r.s), isTrue);
      expect(rowsOf(r.s).hasLayerClipboard, isFalse);
    });

    test('a selection of rows no board holds leaves the copy to the frame '
        'axis', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      final camera = r.s.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;
      // Selected without being stood on: the frame axis still reads row A.
      r.s.rowSelectionVerbs.rowSelection.value = [LayerRowAddress(camera)];
      expect(rowsOf(r.s).canCopySelectedRows, isFalse);

      pill(r.s).copyFrame();

      expect(rowsOf(r.s).hasLayerClipboard, isFalse);
      expect(holdsFrames(r.s), isTrue);
    });

    test('an attach row is no row a board holds either', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      r.s.folders.addAttachedLayer(AttachedPlacement.above);
      final rider = r.s.activeLayerId!;
      select(r.s, [rider]);

      expect(rowsOf(r.s).canCopySelectedRows, isFalse);
      // …but beside a row that is, the copy takes that one alone.
      select(r.s, [rider, r.b]);
      pill(r.s).copyFrame();
      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();
      expect(names(r.s).where((name) => name == 'B'), hasLength(2));
      expect(drawingRows(r.s), hasLength(5), reason: 'A, its rider, B, B, C');
    });

    test('the STORYBOARD\'s copy is never the rows, and rows in hand are '
        'nothing its pastes put down', () {
      final r = threeRows();
      select(r.s, [r.a]);

      StoryboardToolbarPanelContext(r.s).copyFrame();
      expect(
        rowsOf(r.s).hasLayerClipboard,
        isFalse,
        reason: '「타임라인의 공용 복사」 — its rows are tracks and fixtures',
      );

      pill(r.s).copyFrame();
      expect(rowsOf(r.s).hasLayerClipboard, isTrue, reason: '⛔전제');
      expect(pill(r.s).canPasteIndependentFrame, isTrue, reason: '⛔전제');
      final storyboard = StoryboardToolbarPanelContext(r.s);
      expect(storyboard.canPasteIndependentFrame, isFalse);
      expect(storyboard.canPasteLinkedFrame, isFalse);
    });
  });

  group('the independent paste puts down what is in hand', () {
    test('the rows land above the row you stand on, in the order they '
        'stood, as ONE step — and no row need be selected', () {
      final r = threeRows();
      // Selected top first: the order they are PUT DOWN in is the cut's.
      select(r.s, [r.c, r.a]);
      pill(r.s).copyFrame();
      r.s.clearRowSelection();
      r.s.selectLayer(r.b);
      final steps = r.s.historyManager.undoCount;

      expect(pill(r.s).canPasteIndependentFrame, isTrue);
      pill(r.s).pasteIndependentFrame();

      expect(names(r.s), ['A', 'B', 'A', 'C', 'C']);
      expect(r.s.historyManager.undoCount, steps + 1, reason: 'ONE step');
      expect(
        r.s.activeLayerId,
        drawingRows(r.s)[3].id,
        reason: 'standing on the top row it put down',
      );
      final ids = {for (final row in drawingRows(r.s)) row.id};
      expect(ids, hasLength(5), reason: 'rows of their own, ids and all');

      r.s.undo();
      expect(names(r.s), ['A', 'B', 'C'], reason: 'one undo takes both back');
    });

    test('pasted again, the rows stack above the ones just put down', () {
      final r = threeRows();
      select(r.s, [r.a]);
      pill(r.s).copyFrame();
      r.s.selectLayer(r.c);

      pill(r.s).pasteIndependentFrame();
      pill(r.s).pasteIndependentFrame();

      expect(names(r.s), ['A', 'B', 'C', 'A', 'A']);
    });

    test('in another cut the rows arrive too — and there the linked paste '
        'is dark', () {
      final r = threeRows();
      select(r.s, [r.a, r.b]);
      pill(r.s).copyFrame();
      r.s.cutVerbs.createCut();
      final before = drawingRows(r.s).length;

      expect(
        pill(r.s).canPasteLinkedFrame,
        isFalse,
        reason: 'a link is made in the cut the rows were copied in',
      );
      expect(pill(r.s).canPasteIndependentFrame, isTrue);
      pill(r.s).pasteIndependentFrame();

      expect(drawingRows(r.s), hasLength(before + 2));
      expect(names(r.s).sublist(names(r.s).length - 2), ['A', 'B']);
    });

    test('in another PROJECT they paste independent only', () {
      final a = threeRows();
      final b = threeRows(board: a.s.appClipboard);
      select(a.s, [a.a]);
      pill(a.s).copyFrame();

      expect(pill(b.s).canPasteIndependentFrame, isTrue);
      expect(
        pill(b.s).canPasteLinkedFrame,
        isFalse,
        reason: 'I-7: no cel of one project is a cel of another — though '
            'this project has a row under the very same id',
      );
      expect(
        b.s.requireActiveCut.layers.any((layer) => layer.id == a.a),
        isTrue,
        reason: '⛔전제: the id is one this project holds too',
      );
    });

    test('with nothing in hand both pastes are dark', () {
      final r = threeRows();
      expect(pill(r.s).canPasteIndependentFrame, isFalse);
      expect(pill(r.s).canPasteLinkedFrame, isFalse);
    });

    test('a row the cut cannot take a second of is passed over, and the '
        'rest land', () {
      final r = threeRows();
      r.s.layerStack.addLayerOfKind(LayerKind.storyboard);
      final conte = r.s.activeLayerId!;
      int conteRows() => r.s.requireActiveCut.layers
          .where((layer) => layer.kind == LayerKind.storyboard)
          .length;
      expect(conteRows(), 1, reason: '⛔전제');
      select(r.s, [conte, r.a]);
      pill(r.s).copyFrame();
      r.s.selectLayer(r.c);

      expect(pill(r.s).canPasteIndependentFrame, isTrue);
      pill(r.s).pasteIndependentFrame();

      expect(conteRows(), 1, reason: 'R9 #7: a cut holds ONE');
      expect(names(r.s), ['A', 'B', 'C', 'A']);
    });

    test('rows in hand that cannot land here leave both pastes dark, and a '
        'press of either writes nothing', () {
      final r = threeRows();
      r.s.layerStack.addLayerOfKind(LayerKind.storyboard);
      select(r.s, [r.s.activeLayerId!]);
      pill(r.s).copyFrame();
      expect(rowsOf(r.s).hasLayerClipboard, isTrue, reason: '⛔전제');
      final rows = r.s.requireActiveCut.layers.length;
      final steps = r.s.historyManager.undoCount;

      expect(pill(r.s).canPasteIndependentFrame, isFalse);
      expect(pill(r.s).canPasteLinkedFrame, isFalse);
      expect(pill(r.s).pasteIndependentFrame, returnsNormally);
      expect(pill(r.s).pasteLinkedFrame, returnsNormally);

      expect(r.s.requireActiveCut.layers, hasLength(rows));
      expect(r.s.historyManager.undoCount, steps, reason: 'no step at all');
    });

    test('standing on a row that is not the cut\'s — an S row — the rows '
        'land at the top of the stack', () {
      final r = threeRows();
      select(r.s, [r.b]);
      pill(r.s).copyFrame();
      r.s.selectLayer(r.s.activeTrack.seLayers.first.id);
      expect(
        r.s.requireActiveCut.layers.any(
          (layer) => layer.id == r.s.activeLayerId,
        ),
        isFalse,
        reason: '⛔전제: the S row is the track\'s',
      );

      pill(r.s).pasteIndependentFrame();

      expect(names(r.s), ['A', 'B', 'C', 'B']);
    });

    test('the board a paste must hold the media of is the one in hand', () {
      // What the wait window is told to wait for (`pasteWithItsMedia`): a
      // row copy's media, asked of the frame board, would never be held.
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      pill(r.s).copyFrame();
      expect(
        identical(pill(r.s).independentPasteBoard, framesOf(r.s)),
        isTrue,
      );

      select(r.s, [r.a]);
      pill(r.s).copyFrame();
      expect(identical(pill(r.s).independentPasteBoard, rowsOf(r.s)), isTrue);
      expect(
        identical(
          StoryboardToolbarPanelContext(r.s).independentPasteBoard,
          framesOf(r.s),
        ),
        isTrue,
        reason: 'rows are not that panel\'s to put down',
      );
    });
  });

  group('the linked paste is 「링크해서 복제」, of every row in hand', () {
    test('a row is copied linked WITH its attach group, above the row you '
        'stand on, as ONE step', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      r.s.folders.addAttachedLayer(AttachedPlacement.above);
      final rider = drawingRows(r.s)[1];
      expect(rider.attachedToLayerId, r.a, reason: '⛔전제');
      select(r.s, [r.a]);
      pill(r.s).copyFrame();
      r.s.clearRowSelection();
      r.s.selectLayer(r.c);
      final steps = r.s.historyManager.undoCount;

      expect(pill(r.s).canPasteLinkedFrame, isTrue);
      pill(r.s).pasteLinkedFrame();

      final rows = drawingRows(r.s);
      expect(
        [for (final row in rows) row.name],
        ['A', rider.name, 'B', 'C', 'A', rider.name],
        reason: '↩️the menu\'s entry put the copy above its SOURCE; a paste '
            'lands where it is pressed',
      );
      expect(rows[5].attachedToLayerId, rows[4].id, reason: 'its own group');
      expect(layersOf(r.s).isLayerLinked(r.a), isTrue);
      expect(layersOf(r.s).isLayerLinked(rows[4].id), isTrue);
      expect(layersOf(r.s).isLayerLinked(rows[5].id), isTrue);
      expect(rows[4].frames.single.id, rows[0].frames.single.id);
      expect(r.s.activeLayerId, rows[4].id, reason: 'standing on the copy');
      expect(r.s.historyManager.undoCount, steps + 1, reason: 'ONE step');

      r.s.undo();
      expect(drawingRows(r.s), hasLength(4));
      expect(layersOf(r.s).isLayerLinked(r.a), isFalse);
    });

    test('two rows keep the order they stood in', () {
      final r = threeRows();
      select(r.s, [r.b, r.a]);
      pill(r.s).copyFrame();
      r.s.selectLayer(r.c);

      pill(r.s).pasteLinkedFrame();

      final rows = drawingRows(r.s);
      expect([for (final row in rows) row.name], ['A', 'B', 'C', 'A', 'B']);
      expect(layersOf(r.s).isLayerLinked(rows[3].id), isTrue);
      expect(layersOf(r.s).isLayerLinked(rows[4].id), isTrue);
      expect(r.s.activeLayerId, rows[4].id, reason: 'the top one put down');
    });

    test('a row that is gone has nothing to share: the linked paste goes '
        'dark, and the independent one still lands it', () {
      final r = threeRows();
      select(r.s, [r.b]);
      pill(r.s).copyFrame();
      expect(pill(r.s).canPasteLinkedFrame, isTrue, reason: '⛔전제');

      layersOf(r.s).deleteSelectedLayers();
      expect(names(r.s), ['A', 'C'], reason: '⛔전제: B is gone');

      expect(pill(r.s).canPasteLinkedFrame, isFalse);
      expect(pill(r.s).canPasteIndependentFrame, isTrue);
      pill(r.s).pasteLinkedFrame();
      expect(names(r.s), ['A', 'C'], reason: 'a dark press does nothing');
      pill(r.s).pasteIndependentFrame();
      expect(names(r.s), contains('B'));
    });
  });
}
