import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/a_folder_of_two_inked_rows.dart';
import '../../helpers/wait_window.dart' show windowBehind;
import '../../helpers/surface_rgba_in_place.dart';

/// I-37 — A FOLDER IS LIFTED WHOLE.
///
/// 유저 2026-10-02: 「폴더 전체를 하나로 들도록」, after asking on 09-16 for
/// 「폴더에 대한 변형도구 사용가능하게. 폴더 내부 전체 적용. 변형도구 실루엣은
/// 전체를 기준으로」. Stood on a folder, Ctrl+T opens ONE box around every
/// drawing row inside it; each row's cel shows its hole and its own float in
/// its own place in the composite while the box is open; the confirm moves
/// every one of them by the same transform, as one step of undo.
void main() {
  const folder = liftedFolder;
  const a = liftedRowA;
  const b = liftedRowB;


  bool inked(
    EditorSessionManager session,
    LayerId row,
    String cel,
    int x,
    int y,
  ) {
    final surface = session.pixelEditing.coordinator!.currentSurfaceOf(
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        row,
        FrameId('${row.value}-$cel'),
      ),
    );
    return (surfaceRgbaInPlace(surface, x, y) ?? 0) != 0;
  }

  /// A few frames — for a selection's marching ants, which never settle.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('stood on a folder, one box moves every drawing row inside it '
      '— as one step of undo', (tester) async {
    final session = await pumpAFolderOfTwoInkedRows(tester);
    expect(
      (inked(session, a, '0', 25, 25), inked(session, b, '0', 75, 75)),
      (true, true),
      reason: '⛔fixture premise: both rows draw where the test reads',
    );

    // Ctrl+T arms the transform tool; the box opens on the picture.
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
    expect(
      commands.transformActive,
      isTrue,
      reason: 'a box opens on a folder',
    );
    final stack = tester.widget<FramePictureView>(
      find.byType(FramePictureView).first,
    );
    expect(
      {for (final key in stack.live!.liftedRows.keys) key.frameId.value},
      {'${a.value}-0', '${b.value}-0'},
      reason: 'while the box is open, each row shows lifted in its own '
          'place in the composite',
    );
    // Each shows ITS OWN cel with its own hole: lifted whole, nothing of
    // either picture is left in either row.
    for (final MapEntry(:key, value: lifted) in stack.live!.liftedRows.entries) {
      expect(
        (
          surfaceRgbaInPlace(lifted.surface, 25, 25) ?? 0,
          surfaceRgbaInPlace(lifted.surface, 75, 75) ?? 0,
        ),
        (0, 0),
        reason: '${key.frameId.value} is drawn from its own cel, holed',
      );
    }

    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    await windowBehind(tester, () async => commands.applyTransform());
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 25, 25), inked(session, a, '0', 75, 25)),
      (false, true),
      reason: 'A moved right by 20',
    );
    expect(
      (inked(session, b, '0', 75, 75), inked(session, b, '0', 125, 75)),
      (false, true),
      reason: 'B moved right by 20 with it',
    );
    expect(
      (inked(session, a, '1', 25, 25), inked(session, b, '1', 75, 75)),
      (true, true),
      reason: 'the other frame was not in it',
    );

    session.historyManager.undo();
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 25, 25), inked(session, b, '0', 75, 75)),
      (true, true),
      reason: 'one undo brings both rows back',
    );
  });

  /// ⑤ — the two answers to an interruption (`SessionInterruption`), for a
  /// folder's box as for a cel's: a walk CARRIES the edit to the rows there,
  /// a tool change LANDS it.
  Future<CanvasSelectionCommands> openAndMove(WidgetTester tester) async {
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    return commands;
  }

  testWidgets('a box walked to the next frame lifts the folder\'s rows THERE '
      '— the frame it left lands nothing', (tester) async {
    final session = await pumpAFolderOfTwoInkedRows(tester);
    final commands = await openAndMove(tester);

    session.selectFrameIndex(1);
    await tester.pumpAndSettle();

    expect(
      commands.transformActive,
      isTrue,
      reason: 'the box walks with its numbers (유저 확정 2026-09-17)',
    );
    final stack = tester.widget<FramePictureView>(
      find.byType(FramePictureView).first,
    );
    expect(
      {for (final key in stack.live!.liftedRows.keys) key.frameId.value},
      {'${a.value}-1', '${b.value}-1'},
    );

    await windowBehind(tester, () async => commands.applyTransform());
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '1', 25, 25), inked(session, a, '1', 75, 25)),
      (false, true),
    );
    expect(
      (inked(session, b, '1', 75, 75), inked(session, b, '1', 125, 75)),
      (false, true),
    );
    expect(
      (inked(session, a, '0', 25, 25), inked(session, b, '0', 75, 75)),
      (true, true),
      reason: 'the frame the box left was let go, not landed',
    );
  });

  testWidgets('a tool change lands every row the folder\'s box holds', (
    tester,
  ) async {
    final session = await pumpAFolderOfTwoInkedRows(tester);
    await openAndMove(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();

    expect(
      (inked(session, a, '0', 25, 25), inked(session, a, '0', 75, 25)),
      (false, true),
    );
    expect(
      (inked(session, b, '0', 75, 75), inked(session, b, '0', 125, 75)),
      (false, true),
    );
  });

  testWidgets('with a marquee, every row lifts only what lies inside it — '
      'and keeps the rest of ITS OWN picture where it was', (tester) async {
    final session = await pumpAFolderOfTwoInkedRows(tester);
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    // Over all of A (20..60) and only B's left half (70..90 of 70..110).
    commands.applyRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 90, bottom: 100),
      ),
    );
    await pumpFrames(tester);
    commands.beginTransform();
    await pumpFrames(tester);

    final stack = tester.widget<FramePictureView>(
      find.byType(FramePictureView).first,
    );
    bool shows(LayerId row, int x, int y) =>
        (surfaceRgbaInPlace(
              stack.live!.liftedRows[session.brushFrameKeyForCut(
                    session.requireActiveCut,
                    row,
                    FrameId('${row.value}-0'),
                  )]!
                  .surface,
              x,
              y,
            ) ??
            0) !=
        0;
    expect(
      (shows(a, 25, 25), shows(b, 75, 75), shows(b, 100, 75)),
      (false, false, true),
      reason: 'each row is drawn from its own cel: the marquee\'s part lifted '
          'out, the rest of B where it was',
    );

    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await pumpFrames(tester);
    await windowBehind(tester, () async => commands.applyTransform());
    await pumpFrames(tester);

    expect(
      (inked(session, b, '0', 75, 75), inked(session, b, '0', 95, 75)),
      (false, true),
      reason: 'B\'s lifted half moved right by 20',
    );
    expect(
      inked(session, b, '0', 105, 75),
      isTrue,
      reason: 'and the half outside the marquee stayed',
    );
  });

  testWidgets('a frame RANGE over the folder carries every row\'s cels '
      'across it by the same move (I-37-Q1 「변형만」 reaches in)', (
    tester,
  ) async {
    final session = await pumpAFolderOfTwoInkedRows(tester);
    session.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: folder,
      startIndex: 0,
      endIndexExclusive: 2,
    );
    await tester.pumpAndSettle();

    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
    commands.editTransformValues((now) => now.copyWith(tx: 20));
    await tester.pumpAndSettle();
    await windowBehind(tester, () async => commands.applyTransform());
    await tester.pumpAndSettle();

    for (final cel in ['0', '1']) {
      expect(
        (inked(session, a, cel, 25, 25), inked(session, a, cel, 75, 25)),
        (false, true),
        reason: 'A\'s cel $cel moved right by 20',
      );
      expect(
        (inked(session, b, cel, 75, 75), inked(session, b, cel, 125, 75)),
        (false, true),
        reason: 'B\'s cel $cel moved right by 20',
      );
    }
  });
}
