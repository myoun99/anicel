import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/commands/brush_lift_move_history_command.dart';

import '../helpers/brush_canvas_fixture.dart';

/// F-38c — 유저 2026-08-27: 「선택 후 변형툴 확정하고, 언두하면 그림만
/// 돌리는게아니라 **선택도 이전 선택으로 되돌리기**. 그에 따라 결과적으로
/// 변형툴ui도 바뀌는게 정상적인 구조겠지」.
///
/// A transform moves two things — the pixels and the outline around them —
/// and this entry only ever carried the pixels. So an undo put the drawing
/// back while the selection stayed in the shape the transform had given it,
/// and the box on screen followed the selection rather than the drawing.
///
/// ⛔ONE entry, not two: a separate selection command would cost two undos
/// for one confirm.
void main() {
  CanvasSelectionRegion regionAt(double left) => CanvasSelectionRegion.shape(
    CanvasSelectionShape([
      CanvasPoint(x: left, y: 0),
      CanvasPoint(x: left + 8, y: 0),
      CanvasPoint(x: left + 8, y: 8),
      CanvasPoint(x: left, y: 8),
    ]),
  );

  BrushDab stampAt(double x) {
    final pixels = Uint8List(4 * 4 * 4);
    for (var i = 3; i < pixels.length; i += 4) {
      pixels[i] = 0xFF;
    }
    return BrushDab(
      center: CanvasPoint(x: x, y: 4),
      color: 0xFF000000,
      size: 4,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
    );
  }

  test('undo puts the SELECTION back where the session found it, and redo '
      'puts back the one the confirm produced', () {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final before = regionAt(0);
    final after = regionAt(40);

    // The channel this test stands in for is the UI's; the command only ever
    // sees these two functions, which is what keeps it out of `ui/`.
    CanvasSelectionRegion? live = after;
    final command = BrushLiftMoveHistoryCommand(
      coordinator: coordinator,
      frameKey: coordinator.activeFrameKey,
      preLiftSurface: coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      landingDabs: [stampAt(20)],
      regionBefore: before,
      readRegion: () => live,
      restoreRegion: (region) => live = region,
    );

    command.execute();
    expect(
      live,
      same(after),
      reason: 'the confirm itself changes nothing about the selection',
    );

    command.undo();
    expect(
      live,
      same(before),
      reason: '유저: 「언두하면 그림만 돌리는게아니라 선택도 이전 선택으로」',
    );

    command.execute();
    expect(
      live,
      same(after),
      reason: 'and a redo is the confirm again — the shape it produced comes '
          'back with the pixels it produced',
    );
  });

  test('a command given no selection channel still undoes the pixels', () {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final pre = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final command = BrushLiftMoveHistoryCommand(
      coordinator: coordinator,
      frameKey: coordinator.activeFrameKey,
      preLiftSurface: pre,
      landingDabs: [stampAt(20)],
    );

    // ⛔The hooks are optional on purpose — headless hosts (focused tests,
    // the conte and timesheet shells) build this command with no selection
    // channel at all, and a null there must not take the undo down with it.
    command.execute();
    expect(command.undo, returnsNormally);
    expect(
      coordinator.currentSurfaceOf(coordinator.activeFrameKey).tiles.length,
      pre.tiles.length,
    );
  });

  test('the entry weighs the tiles it holds, never the stamp', () {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final pre = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final command = BrushLiftMoveHistoryCommand(
      coordinator: coordinator,
      frameKey: coordinator.activeFrameKey,
      preLiftSurface: pre,
      landingDabs: [stampAt(20)],
    );

    // Nothing landed yet, so nothing is uniquely held: the erase was
    // committed before this command existed and `pre` still shares every
    // tile with the live surface.
    expect(command.estimatedRetainedBytes(undone: false), 0);

    command.execute();

    // 🚨THE STAMP IS NOT WHAT THIS HOLDS. Until 2026-09-07 the weight was
    // `2 * 4 * stamp.width * stamp.height` — a 64×64 stamp reported 32 KB
    // while the command held a full-canvas surface (2048× out), and a
    // null stamp reported ZERO. The budget therefore never fired on the
    // entries that killed the app.
    final post = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    expect(
      command.estimatedRetainedBytes(undone: false),
      pre.bytesNotSharedWith(post),
    );
  });

  test('the anchored region is the one the session FOUND, not a later one', () {
    // ⚠️`regionBefore` is captured at the lift, beside the pixel anchor. A
    // command that read it at undo time would read whatever the transform
    // had just written, which is the bug this fixes.
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final found = regionAt(0);
    CanvasSelectionRegion? live = found;
    final command = BrushLiftMoveHistoryCommand(
      coordinator: coordinator,
      frameKey: coordinator.activeFrameKey,
      preLiftSurface: coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      landingDabs: [stampAt(20)],
      regionBefore: found,
      readRegion: () => live,
      restoreRegion: (region) => live = region,
    );
    command.execute();
    // The user drags the box again after the confirm — the selection moves.
    live = regionAt(99);
    command.undo();
    expect(
      live,
      same(found),
      reason: 'the anchor is what the session found, and nothing that '
          'happened afterwards can move it',
    );
  });

}
