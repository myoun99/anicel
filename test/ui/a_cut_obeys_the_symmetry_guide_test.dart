import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// 🗣️the-cut-preview-shows-copies-it-does-not-cut-Q1 (유저 2026-10-09):
/// 「잘라내기도 대칭을 따른다」. Under a symmetry guide the cut's drag shows
/// every copy's outline — the selection layer draws them for every verb —
/// and the release lifts what it showed: ONE piece holding every side, so a
/// stamp lays them together. ↩️It lifted the original alone.
///
/// Driven through the real panel, so the wiring from the drag's copies to
/// the one piece is part of what is pinned.
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');
  const canvasSize = CanvasSize(width: 200, height: 120);

  /// A vertical mirror down the middle of the canvas: x → 200 − x.
  CutGuides mirrorGuides() {
    final guide = DrawingGuide(
      id: const GuideId('mirror'),
      name: 'Mirror',
      shape: SymmetryShape(
        axis: GuideAxis(origin: CanvasPoint(x: 100, y: 60), angleDegrees: 90),
        lineCount: 2,
      ),
    );
    return CutGuides(guides: [guide], activeSymmetryId: guide.id);
  }

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 8,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  /// A bar of ink on each side of the mirror, then a rectangle cut around
  /// the LEFT bar alone — the piece the slot holds after.
  Future<CutPiece?> cutTheLeftBar(
    WidgetTester tester, {
    required CutGuides? guides,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: canvasSize,
    );
    coordinator.commitSourceStroke(
      sourceDabs: [for (var x = 20; x <= 60; x += 2) dab(x.toDouble(), 40)],
    );
    coordinator.commitSourceStroke(
      sourceDabs: [for (var x = 140; x <= 180; x += 2) dab(x.toDouble(), 40)],
    );
    final slot = CutPieceSlot();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: canvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: HistoryManager(),
            brushToolState: ValueNotifier(
              BrushToolState.defaults.copyWith(
                tool: CanvasTool.cut,
                cutShape: CanvasShapeKind.rect,
              ),
            ),
            selectionCommands: CanvasSelectionCommands(),
            cutPieceSlot: slot,
            guides: guides,
            // One screen pixel is one canvas pixel, so the drag numbers
            // below are canvas coordinates.
            viewport: seedFromRender(tester, CanvasViewport()),
          ),
        ),
      ),
    );
    await tester.pump();
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + const Offset(10, 25));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(70, 55));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    return slot.piece;
  }

  /// Whether [piece] holds ink at the canvas point ([x], [y]).
  bool inkAt(CutPiece piece, int x, int y) {
    final column = x - piece.originLeft;
    final row = y - piece.originTop;
    if (column < 0 ||
        row < 0 ||
        column >= piece.image.width ||
        row >= piece.image.height) {
      return false;
    }
    return piece.image.rgba[(row * piece.image.width + column) * 4 + 3] > 0;
  }

  testWidgets('fixture premise: with no guide the cut lifts the left bar '
      'alone', (tester) async {
    final piece = await cutTheLeftBar(tester, guides: null);
    expect(piece, isNotNull);
    expect(inkAt(piece!, 40, 40), isTrue);
    expect(inkAt(piece, 160, 40), isFalse, reason: 'outside the outline');
  });

  testWidgets('under a mirror the cut lifts BOTH sides into ONE piece — what '
      'its outline showed', (tester) async {
    final piece = await cutTheLeftBar(tester, guides: mirrorGuides());
    expect(piece, isNotNull);
    expect(inkAt(piece!, 40, 40), isTrue, reason: 'the side it was drawn on');
    expect(
      inkAt(piece, 160, 40),
      isTrue,
      reason: 'the mirror\'s side, in the same piece',
    );
  });
}
