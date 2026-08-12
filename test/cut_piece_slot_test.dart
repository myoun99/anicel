import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
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
    test('the two grab variants cut, the stamp variant stamps', () {
      expect(canvasToolCuts(CanvasTool.cutRect), isTrue);
      expect(canvasToolCuts(CanvasTool.cutLasso), isTrue);
      expect(canvasToolCuts(CanvasTool.cutStamp), isFalse);
      expect(canvasToolStamps(CanvasTool.cutStamp), isTrue);
      expect(canvasToolStamps(CanvasTool.cutRect), isFalse);
      for (final tool in CanvasTool.values) {
        expect(
          canvasToolUsesCutPiece(tool),
          canvasToolCuts(tool) || canvasToolStamps(tool),
          reason: '$tool',
        );
      }
    });

    test('the grab variants mount the selection layer, the stamp does not', () {
      // They need the same marquee/lasso drag; what differs is what a
      // finished drag does.
      expect(canvasToolSelects(CanvasTool.cutRect), isTrue);
      expect(canvasToolSelects(CanvasTool.cutLasso), isTrue);
      expect(canvasToolSelects(CanvasTool.cutStamp), isFalse);
    });

    test('the stamp marks the cel but is not a painting tool', () {
      // It puts pixels down, so the "would this press draw?" guard has to
      // say yes — but it must not be routed through the brush stroke path,
      // which would hand it the current brush's opacity and dynamics.
      expect(canvasToolMarksCel(CanvasTool.cutStamp), isTrue);
      expect(canvasToolPaints(CanvasTool.cutStamp), isFalse);
    });

    test('the grab variants put no marks on the cel', () {
      expect(canvasToolMarksCel(CanvasTool.cutRect), isFalse);
      expect(canvasToolMarksCel(CanvasTool.cutLasso), isFalse);
    });
  });

  group('tool library', () {
    Future<void> pumpLibrary(
      WidgetTester tester,
      CanvasTool tool,
      ValueChanged<CanvasTool> onToolChanged,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolLibraryPanel(
              tool: tool,
              onToolChanged: onToolChanged,
              brushLibrary: const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    testWidgets('the cut tool lists three tiles', (tester) async {
      await pumpLibrary(tester, CanvasTool.cutRect, (_) {});
      expect(find.byKey(const ValueKey<String>('tool-library-cut')), findsOne);
      expect(find.byKey(const ValueKey<String>('sub-tool-cut-rect')), findsOne);
      expect(find.byKey(const ValueKey<String>('sub-tool-cut-lasso')), findsOne);
      expect(find.byKey(const ValueKey<String>('sub-tool-cut-stamp')), findsOne);
    });

    testWidgets('every cut variant shows the same three tiles', (tester) async {
      for (final tool in [
        CanvasTool.cutRect,
        CanvasTool.cutLasso,
        CanvasTool.cutStamp,
      ]) {
        await pumpLibrary(tester, tool, (_) {});
        expect(
          find.byKey(const ValueKey<String>('tool-library-cut')),
          findsOne,
          reason: '$tool',
        );
      }
    });

    testWidgets('tapping a tile switches to that variant', (tester) async {
      final picked = <CanvasTool>[];
      await pumpLibrary(tester, CanvasTool.cutRect, picked.add);
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-stamp')));
      await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-lasso')));
      expect(picked, [CanvasTool.cutStamp, CanvasTool.cutLasso]);
    });

    testWidgets('the selection tool still lists only its own two tiles', (
      tester,
    ) async {
      // The cut tiles must not leak into the neighbour that shares the
      // grammar — these are different tools with different verbs.
      await pumpLibrary(tester, CanvasTool.selectRect, (_) {});
      expect(
        find.byKey(const ValueKey<String>('tool-library-selection')),
        findsOne,
      );
      expect(find.byKey(const ValueKey<String>('sub-tool-cut-rect')), findsNothing);
    });
  });
}
