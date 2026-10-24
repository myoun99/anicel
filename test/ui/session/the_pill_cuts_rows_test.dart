import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🚨I-123 — THE SHARED PILL'S 잘라내기 SERVES ROWS.
///
/// 유저 2026-10-22: 「레이어도 타임라인 공용알약의 잘라내기 버튼 사용가능.
/// 여러레이어 선택해서 사용한다던가 다른 규칙 참고해서 법 통일」.
///
/// The rules it is unified with, pinned below:
///
/// * 복사 and 잘라내기 are ONE pair (「복사=원본 남기고 클립 저장 · 잘라내기=원본
///   지우고 클립 저장」): the cut asks the copy's ladder, so where the copy
///   takes the selected rows the cut takes them too — never the frame axis
///   under them;
/// * 결정 14 ②ⓐ: a cut banks exactly what it lifts. A row whose delete
///   would take rows the board does not hold — a base's attach rows — is
///   not lifted, and a row the delete refuses is not banked;
/// * the rows go as ONE undo step, and a paste puts them down as the copy's
///   rows land (I-77).
///
/// The collaborators are held BY THEIR OWN TYPES so the mutation runner
/// names this file as their witness (it picks witnesses by import).
void main() {
  LayerClipboard rowsOf(EditorSessionManager s) => s.layerClipboard;
  FrameClipboard framesOf(EditorSessionManager s) => s.clipboard;
  LayerVerbs layersOf(EditorSessionManager s) => s.layerVerbs;

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
  ({EditorSessionManager s, LayerId a, LayerId b, LayerId c}) threeRows() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
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

  group('the cut takes the selected rows', () {
    test('one row: it goes as ONE step, the hand holds it, and the paste '
        'puts it back', () {
      final r = threeRows();
      select(r.s, [r.b]);
      final steps = r.s.historyManager.undoCount;

      expect(pill(r.s).canCutRun, isTrue);
      expect(pill(r.s).cutPress, isNotNull, reason: 'Ctrl+X presses it too');
      pill(r.s).cutRun();

      expect(names(r.s), ['A', 'C']);
      expect(r.s.historyManager.undoCount, steps + 1, reason: 'ONE step');
      expect(rowsOf(r.s).hasLayerClipboard, isTrue);
      expect(r.s.rowSelection.value, isEmpty, reason: 'its rows are gone');

      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();
      expect(names(r.s), ['A', 'C', 'B']);
    });

    test('several rows go together and land in the order they stood', () {
      final r = threeRows();
      // Selected top first: what lands is the cut's order.
      select(r.s, [r.c, r.a]);
      final steps = r.s.historyManager.undoCount;

      pill(r.s).cutRun();

      expect(names(r.s), ['B']);
      expect(r.s.historyManager.undoCount, steps + 1, reason: 'ONE step');
      pill(r.s).pasteIndependentFrame();
      expect(names(r.s), ['B', 'A', 'C']);

      r.s.undo();
      r.s.undo();
      expect(names(r.s), ['A', 'B', 'C'], reason: 'one undo for the cut');
    });

    test('it takes the rows, never the frame under them — the copy\'s '
        'subject', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      final drawn = drawingRows(r.s).first.timeline.length;
      expect(drawn, isPositive, reason: '⛔전제: A holds a drawing here');
      // Selected without being stood on: the frame axis still reads row A.
      r.s.rowSelectionVerbs.rowSelection.value = [LayerRowAddress(r.b)];

      pill(r.s).cutRun();

      expect(names(r.s), ['A', 'C']);
      expect(drawingRows(r.s).first.timeline, hasLength(drawn));
      expect(holdsFrames(r.s), isFalse);
    });

    test('with a row of the cut gone, the linked paste is dark and the '
        'independent one lands it', () {
      final r = threeRows();
      select(r.s, [r.b]);

      pill(r.s).cutRun();

      expect(pill(r.s).canPasteLinkedFrame, isFalse);
      expect(pill(r.s).canPasteIndependentFrame, isTrue);
    });

    test('rows no board holds leave the cut to the frame axis, as they '
        'leave the copy', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      final camera = r.s.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;
      r.s.rowSelectionVerbs.rowSelection.value = [LayerRowAddress(camera)];
      expect(rowsOf(r.s).canCopySelectedRows, isFalse, reason: '⛔전제');

      expect(pill(r.s).canCutRun, framesOf(r.s).canCutAt(
        framesOf(r.s).timelinePlace,
      ));
      pill(r.s).cutRun();

      expect(holdsFrames(r.s), isTrue);
      expect(rowsOf(r.s).hasLayerClipboard, isFalse);
    });

    test('the STORYBOARD\'s cut is never the rows', () {
      final r = threeRows();
      select(r.s, [r.a]);

      StoryboardToolbarPanelContext(r.s).cutRun();

      expect(names(r.s), ['A', 'B', 'C']);
      expect(rowsOf(r.s).hasLayerClipboard, isFalse);
    });
  });

  group('a cut banks exactly what it lifts (결정 14 ②ⓐ)', () {
    test('a base with an attach row stays — its delete would take a row the '
        'board does not hold — and the plain row beside it goes alone', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      r.s.folders.addAttachedLayer(AttachedPlacement.above);
      final rider = r.s.activeLayerId!;
      expect(drawingRows(r.s)[1].attachedToLayerId, r.a, reason: '⛔전제');
      select(r.s, [r.a, r.b]);

      pill(r.s).cutRun();

      expect(names(r.s), ['A', drawingRows(r.s)[1].name, 'C']);
      expect(drawingRows(r.s)[1].id, rider);
      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();
      expect(
        names(r.s).where((name) => name == 'A'),
        hasLength(1),
        reason: 'A was not lifted, so it is not in hand either',
      );
      expect(names(r.s).last, 'B');
    });

    test('with only such a base selected the cut is dark: the rows claim '
        'the press, and the drawing under it is not cut instead', () {
      final r = threeRows();
      r.s.createDrawingAtCurrentFrame();
      r.s.folders.addAttachedLayer(AttachedPlacement.above);
      r.s.selectLayer(r.a);
      select(r.s, [r.a]);
      final drawn = drawingRows(r.s).first.timeline.length;
      final steps = r.s.historyManager.undoCount;

      expect(pill(r.s).canCutRun, isFalse);
      expect(pill(r.s).cutPress, isNull);
      pill(r.s).cutRun();

      expect(drawingRows(r.s), hasLength(4));
      expect(drawingRows(r.s).first.timeline, hasLength(drawn));
      expect(r.s.historyManager.undoCount, steps, reason: 'no step at all');
      expect(holdsFrames(r.s) || rowsOf(r.s).hasLayerClipboard, isFalse);
    });

    test('a row the delete refuses at its floor is not banked', () {
      final r = threeRows();
      List<Layer> instructionRows() => [
        for (final layer in r.s.requireActiveCut.layers)
          if (layer.kind == LayerKind.instruction) layer,
      ];
      if (instructionRows().length < 2) {
        r.s.layerStack.addLayerOfKind(LayerKind.instruction);
      }
      final before = instructionRows().length;
      expect(before, greaterThanOrEqualTo(2), reason: '⛔전제');
      select(r.s, [for (final row in instructionRows()) row.id]);
      expect(
        layersOf(r.s).deletableSelectedLayerIds(),
        hasLength(before),
        reason: '⛔전제: each one alone may go — not all of them',
      );

      pill(r.s).cutRun();

      expect(instructionRows(), hasLength(1), reason: 'the floor is one');
      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();
      expect(
        instructionRows(),
        hasLength(before),
        reason: 'what lands is what went — not the row that stayed',
      );
    });
  });
}
