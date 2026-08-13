import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';

/// A 2x2 piece whose four pixels are distinguishable by their red channel,
/// so a flip is observable as a permutation rather than as "some bytes
/// changed".
///
///   R=1  R=2
///   R=3  R=4
BrushStampImage _swatch() {
  final rgba = Uint8List(2 * 2 * 4);
  for (var index = 0; index < 4; index += 1) {
    rgba[index * 4] = index + 1;
    rgba[index * 4 + 3] = 255;
  }
  return BrushStampImage(id: 'swatch', width: 2, height: 2, rgba: rgba);
}

List<int> _reds(BrushStampImage image) => [
  for (var index = 0; index < image.width * image.height; index += 1)
    image.rgba[index * 4],
];

CutPiece _piece({
  bool flipHorizontal = false,
  bool flipVertical = false,
  int scalePercent = 100,
}) {
  return CutPiece(
    image: _swatch(),
    originLeft: 12,
    originTop: 34,
    flipHorizontal: flipHorizontal,
    flipVertical: flipVertical,
    scalePercent: scalePercent,
  );
}

void main() {
  group('CutPiece pose', () {
    test('an unposed piece hands back the very same image object', () {
      final piece = _piece();
      expect(piece.isPosed, isFalse);
      // Identity, not equality: an unflipped stamp must not pay for a copy,
      // and the byte-exact round trip depends on the original object.
      expect(identical(piece.flippedImage(), piece.image), isTrue);
    });

    test('horizontal flip swaps columns, vertical flip swaps rows', () {
      expect(_reds(_piece(flipHorizontal: true).flippedImage()), [2, 1, 4, 3]);
      expect(_reds(_piece(flipVertical: true).flippedImage()), [3, 4, 1, 2]);
      expect(
        _reds(
          _piece(flipHorizontal: true, flipVertical: true).flippedImage(),
        ),
        [4, 3, 2, 1],
      );
    });

    test('flipping twice returns the original bytes', () {
      final once = _piece(flipHorizontal: true).flippedImage();
      final twice = CutPiece(
        image: once,
        originLeft: 0,
        originTop: 0,
        flipHorizontal: true,
      ).flippedImage();
      expect(_reds(twice), _reds(_swatch()));
    });

    test('flipping never resamples — size and alpha survive', () {
      final flipped = _piece(flipHorizontal: true, flipVertical: true)
          .flippedImage();
      expect(flipped.width, 2);
      expect(flipped.height, 2);
      expect(flipped.rgba.length, _swatch().rgba.length);
      for (var index = 0; index < 4; index += 1) {
        expect(flipped.rgba[index * 4 + 3], 255);
      }
    });

    test('scale is a percent of the cut size and never rounds to zero', () {
      expect(_piece().stampWidth, 2);
      expect(_piece(scalePercent: 250).stampWidth, 5);
      expect(_piece(scalePercent: 250).stampHeight, 5);
      // 2px * 1% rounds to 0; a zero-sized stamp is a broken tool, not a
      // small one.
      expect(_piece(scalePercent: 1).stampWidth, 1);
    });

    test('scale outside the allowed range is rejected', () {
      expect(() => _piece(scalePercent: 0), throwsArgumentError);
      expect(
        () => _piece(scalePercent: CutPiece.maxScalePercent + 1),
        throwsArgumentError,
      );
    });

    test('reset drops the pose and keeps the pixels and the origin', () {
      final posed = _piece(
        flipHorizontal: true,
        flipVertical: true,
        scalePercent: 300,
      );
      final plain = posed.reset();
      expect(plain.isPosed, isFalse);
      expect(plain.scalePercent, 100);
      expect(plain.flipHorizontal, isFalse);
      expect(plain.flipVertical, isFalse);
      // The Reset button clears BOTH knobs — that is why the panel needs no
      // separate "original size" button.
      expect(identical(plain.image, posed.image), isTrue);
      expect(plain.originLeft, 12);
      expect(plain.originTop, 34);
    });
  });

  group('CutPieceSlot', () {
    test('starts empty', () {
      final slot = CutPieceSlot();
      expect(slot.isEmpty, isTrue);
      expect(slot.piece, isNull);
    });

    test('cutting again REPLACES the held piece', () {
      final slot = CutPieceSlot();
      final first = _piece();
      final second = CutPiece(
        image: BrushStampImage(
          id: 'other',
          width: 1,
          height: 1,
          rgba: Uint8List(4),
        ),
        originLeft: 0,
        originTop: 0,
      );
      slot.hold(first);
      slot.hold(second);
      expect(slot.piece, same(second));
    });

    test('holding a piece notifies', () {
      final slot = CutPieceSlot();
      var notifications = 0;
      slot.addListener(() => notifications += 1);
      slot.hold(_piece());
      expect(notifications, 1);
    });

    test('a pose change that changes nothing does not notify', () {
      final slot = CutPieceSlot()..hold(_piece());
      var notifications = 0;
      slot.addListener(() => notifications += 1);
      slot.updatePose(scalePercent: 100, flipHorizontal: false);
      expect(notifications, 0);
      slot.updatePose(flipHorizontal: true);
      expect(notifications, 1);
      expect(slot.piece!.flipHorizontal, isTrue);
    });

    test('posing an empty slot is a no-op, not a crash', () {
      final slot = CutPieceSlot();
      var notifications = 0;
      slot.addListener(() => notifications += 1);
      slot.updatePose(flipHorizontal: true);
      slot.resetPose();
      expect(notifications, 0);
      expect(slot.isEmpty, isTrue);
    });

    test('resetPose clears both knobs and notifies once', () {
      final slot = CutPieceSlot()
        ..hold(_piece(flipVertical: true, scalePercent: 400));
      var notifications = 0;
      slot.addListener(() => notifications += 1);
      slot.resetPose();
      expect(notifications, 1);
      expect(slot.piece!.isPosed, isFalse);
      // Already-clean pose: nothing to do, nothing to announce.
      slot.resetPose();
      expect(notifications, 1);
    });
  });

  group('cut tool predicates', () {
    test('the grab verb cuts, the stamp verb stamps', () {
      expect(canvasToolCuts(CanvasTool.cut), isTrue);
      expect(canvasToolCuts(CanvasTool.cutStamp), isFalse);
      expect(canvasToolStamps(CanvasTool.cutStamp), isTrue);
      expect(canvasToolStamps(CanvasTool.cut), isFalse);
      for (final tool in CanvasTool.values) {
        expect(
          canvasToolUsesCutPiece(tool),
          canvasToolCuts(tool) || canvasToolStamps(tool),
          reason: '$tool',
        );
      }
    });

    test('the predicates read the VERB, never the shape', () {
      // The shape is a separate axis now: changing which outline the grab
      // traces must not change what the grab IS.
      for (final shape in CanvasShapeKind.values) {
        final state = BrushToolState(tool: CanvasTool.cut, cutShape: shape);
        expect(canvasToolCuts(state.tool), isTrue, reason: '$shape');
        expect(canvasToolSelects(state.tool), isTrue, reason: '$shape');
        expect(canvasToolMarksCel(state.tool), isFalse, reason: '$shape');
        expect(state.activeShapeKind, shape);
      }
    });

    test('the grab verb mounts the selection layer, the stamp does not', () {
      // It needs the same marquee/lasso drag; what differs is what a
      // finished drag does.
      expect(canvasToolSelects(CanvasTool.cut), isTrue);
      expect(canvasToolSelects(CanvasTool.cutStamp), isFalse);
    });

    test('the stamp marks the cel but is not a painting tool', () {
      // It puts pixels down, so the "would this press draw?" guard has to
      // say yes — but it must not be routed through the brush stroke path,
      // which would hand it the current brush's opacity and dynamics.
      expect(canvasToolMarksCel(CanvasTool.cutStamp), isTrue);
      expect(canvasToolPaints(CanvasTool.cutStamp), isFalse);
    });

    test('the grab verb puts no marks on the cel', () {
      expect(canvasToolMarksCel(CanvasTool.cut), isFalse);
    });

    test('only the drag-out verbs wear a shape', () {
      for (final tool in CanvasTool.values) {
        expect(
          BrushToolState(tool: tool).activeShapeKind != null,
          canvasToolDragsShape(tool),
          reason: '$tool',
        );
      }
      // MOVE mounts the selection layer but traces nothing.
      expect(canvasToolSelects(CanvasTool.move), isTrue);
      expect(canvasToolDragsShape(CanvasTool.move), isFalse);
    });
  });

  group('tool library', () {
    Future<void> pumpLibrary(
      WidgetTester tester,
      CanvasTool tool, {
      ValueChanged<CanvasTool>? onToolChanged,
      void Function(CanvasTool verb, CanvasShapeKind kind)? onShapeKindChanged,
      CanvasShapeKind shapeKind = CanvasShapeKind.rect,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolLibraryPanel(
              tool: tool,
              onToolChanged: onToolChanged ?? (_) {},
              shapeKind: shapeKind,
              onShapeKindChanged: onShapeKindChanged ?? (_, _) {},
              brushLibrary: const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    testWidgets('the cut tool lists a tile per shape, plus the stamp', (
      tester,
    ) async {
      await pumpLibrary(tester, CanvasTool.cut);
      expect(find.byKey(const ValueKey<String>('tool-library-cut')), findsOne);
      for (final kind in CanvasShapeKind.values) {
        expect(
          find.byKey(ValueKey<String>('sub-tool-cut-${kind.name}')),
          findsOne,
          reason: '$kind',
        );
      }
      expect(find.byKey(const ValueKey<String>('sub-tool-cut-stamp')), findsOne);
    });

    testWidgets('both cut verbs show the same tiles', (tester) async {
      for (final tool in [CanvasTool.cut, CanvasTool.cutStamp]) {
        await pumpLibrary(tester, tool);
        expect(
          find.byKey(const ValueKey<String>('tool-library-cut')),
          findsOne,
          reason: '$tool',
        );
      }
    });

    testWidgets('tapping a shape tile picks that shape FOR the cut verb', (
      tester,
    ) async {
      // One write, not two: the tile is also how the grab verb is entered,
      // so it must carry the verb with it.
      final picked = <(CanvasTool, CanvasShapeKind)>[];
      await pumpLibrary(
        tester,
        CanvasTool.cutStamp,
        onShapeKindChanged: (verb, kind) => picked.add((verb, kind)),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('sub-tool-cut-lasso')),
      );
      expect(picked, [(CanvasTool.cut, CanvasShapeKind.lasso)]);
    });

    testWidgets('tapping the stamp tile switches the verb', (tester) async {
      final picked = <CanvasTool>[];
      await pumpLibrary(
        tester,
        CanvasTool.cut,
        onToolChanged: picked.add,
      );
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-stamp')));
      expect(picked, [CanvasTool.cutStamp]);
    });

    testWidgets('with the stamp armed no cut SHAPE reads as selected', (
      tester,
    ) async {
      // Nothing is being traced then, so highlighting an outline would be
      // claiming a drag that cannot happen.
      await pumpLibrary(tester, CanvasTool.cutStamp);
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('sub-tool-cut-rect')),
      );
      expect(tile.selected, isFalse);
    });

    testWidgets('the selection tool lists only its own tiles', (tester) async {
      // The cut tiles must not leak into the neighbour that shares the
      // grammar — these are different verbs.
      await pumpLibrary(tester, CanvasTool.select);
      expect(
        find.byKey(const ValueKey<String>('tool-library-selection')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey<String>('sub-tool-cut-rect')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('sub-tool-select-rect')),
        findsOne,
      );
    });
  });
}
