// The first landing on the engine compiles the executor and its kernels:
// 40 s on a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show SelectionMaskOptions;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/last_stroke_slot.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';
import '../helpers/surface_rgba_in_place.dart';

/// 🚨확정 lays down what LANDED — cut by the selection it landed through,
/// whatever the marquee is when 확정 is pressed (관제 2026-11-14, by 유저
/// 09-17 「보이는 중이랑 결과랑 절대로 다르면 안 되」: the screen shows the
/// drawing as it landed, and 확정 must lay what was seen). Board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`.
///
/// One pin for every drawing verb 확정 lays again: a stamp, a stroke of the
/// brush and a fill, each landed under a feathered marquee A whose right
/// edge runs through it, the marquee moved to B, the next frame stood on and
/// 확정 pressed — the cel there holds the bytes the first one does.
void main() {
  /// Where each verb is aimed: at this harness's render 1.0 a point on the
  /// panel is the canvas point under it.
  const aim = Offset(300, 300);

  /// A's right edge runs through [aim]; B takes what lies right of it.
  final regionA = CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(left: 150, top: 150, right: 300, bottom: 450),
  );
  final regionB = CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(left: 290, top: 150, right: 450, bottom: 450),
  );

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      List<BrushFrameKey> keys,
      CanvasSelectionCommands commands,
      CutPieceSlot slot,
      LastStrokeSlot last,
      Future<void> Function() rebuild,
    })
  >
  pumpPanel(WidgetTester tester, CanvasTool tool) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(frameKeys: keys);
    final history = HistoryManager();
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final brush = ValueNotifier(BrushToolState.defaults.copyWith(tool: tool));
    addTearDown(brush.dispose);
    final mask = ValueNotifier(const SelectionMaskOptions(featherPx: 4));
    addTearDown(mask.dispose);
    final commands = CanvasSelectionCommands();
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    final last = LastStrokeSlot();
    addTearDown(last.dispose);
    final sink = BrushEditCacheInvalidationSink();
    final atRenderOne = seedFromRender(tester, CanvasViewport());
    Future<void> build() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: keys,
              cacheInvalidationSink: sink,
              historyManager: history,
              brushToolState: brush,
              selectionCommands: commands,
              selectionMaskOptions: mask,
              cutPieceSlot: slot,
              lastStroke: last,
              viewport: atRenderOne,
              activeStrokeOverlayModel: overlay,
              // A square sixty-four wide around wherever it is flooded from.
              fillRangeAt: (point, _) {
                const side = 64;
                return FillRange.over(
                  FloodFillRegion(
                    left: point.x.floor() - side ~/ 2,
                    top: point.y.floor() - side ~/ 2,
                    width: side,
                    height: side,
                    mask: Uint8List(side * side)
                      ..fillRange(0, side * side, 255),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await build();
    return (
      coordinator: coordinator,
      keys: keys,
      commands: commands,
      slot: slot,
      last: last,
      rebuild: build,
    );
  }

  Offset onPanel(WidgetTester tester, Offset at) =>
      tester.getTopLeft(find.byType(BrushCanvasPanel)) + at;

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump();
    }
  }

  /// A press at [aim] — a stamp, a fill — or a drag across it, the brush.
  Future<void> draw(WidgetTester tester, CanvasTool tool) async {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: onPanel(tester, aim));
    await tester.pump();
    if (tool == CanvasTool.brush) {
      await pointer.down(onPanel(tester, aim - const Offset(40, 0)));
      for (var step = 1; step <= 8; step += 1) {
        await tester.pump();
        await pointer.moveTo(
          onPanel(tester, aim + Offset(-40 + step * 10.0, 0)),
        );
      }
    } else {
      await pointer.down(onPanel(tester, aim));
    }
    await tester.pump();
    await pointer.up();
    await settle(tester);
  }

  CutPiece square() {
    const side = 32;
    return CutPiece(
      image: BrushStampImage(
        id: 'square',
        width: side,
        height: side,
        rgba: Uint8List(side * side * 4)..fillRange(0, side * side * 4, 200),
      ),
      originLeft: 0,
      originTop: 0,
    );
  }

  for (final tool in [CanvasTool.cutStamp, CanvasTool.brush, CanvasTool.fill]) {
    testWidgets('${tool.name}: landed under A, the marquee moved to B, 확정 '
        'on the next frame lays the bytes that landed', (tester) async {
      final stage = await pumpPanel(tester, tool);
      if (tool == CanvasTool.cutStamp) {
        stage.slot.hold(square());
      }
      stage.commands.setRegion(regionA);
      await tester.pump();
      await draw(tester, tool);
      final landed = stage.coordinator.currentSurfaceOf(stage.keys[0]);
      int alphaAt(int x, int y) => (surfaceRgbaInPlace(landed, x, y) ?? 0) & 255;
      expect(alphaAt(290, 300), isNonZero, reason: '⛔premise: it landed');
      expect(alphaAt(305, 300), 0, reason: '⛔premise: A cut it');

      stage.commands.setRegion(regionB);
      stage.coordinator.selectFrame(stage.keys[1]);
      await stage.rebuild();
      await settle(tester);
      expect(stage.last.canReinput, isTrue, reason: '⛔premise');
      stage.last.reinput();
      await settle(tester);

      final again = stage.coordinator.currentSurfaceOf(stage.keys[1]);
      for (var y = 150; y < 450; y += 1) {
        for (var x = 150; x < 450; x += 1) {
          final want = surfaceRgbaInPlace(landed, x, y);
          final got = surfaceRgbaInPlace(again, x, y);
          if (got != want) {
            fail(
              '$x,$y: 확정 laid ${got?.toRadixString(16)} where '
              '${want?.toRadixString(16)} landed',
            );
          }
        }
      }
    });
  }
}
