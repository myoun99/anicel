import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cut_piece_stamp.dart';
import 'package:anicel/src/services/piece_landing.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/surface_rgba_in_place.dart';

/// 🗣️a-stamp-drag-undoes-a-stamp-at-a-time-Q1 (유저 2026-11-19): 「한 끌기 =
/// 한 되돌리기(획처럼)」 — recorded as a stroke is (관제 2026-11-19): a drag's
/// stamps land on each cel as ONE landing, every stamp in it, through the
/// piece door ([pieceLandings]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cels = BrushCanvasFixture.createFrameKeys();

  /// A 12x12 piece at half alpha, so stamps laid over each other show the
  /// order they were laid in.
  final piece = CutPiece(
    image: BrushStampImage(
      id: 'p',
      width: 12,
      height: 12,
      rgba: Uint8List.fromList([
        for (var index = 0; index < 144; index += 1) ...[
          40 + index,
          200 - index,
          90,
          128,
        ],
      ]),
    ),
    originLeft: 0,
    originTop: 0,
  );

  /// Three stamps along a line, each overlapping the one before.
  final laid = <PieceOnTheRow>[
    for (final x in [50.0, 56.0, 62.0])
      (_) => buildCutStampDab(piece: piece, center: CanvasPoint(x: x, y: 60)),
  ];

  /// A coordinator whose cels hold a bar of ink under the trail, so that
  /// BEHIND and ERASE have something to land against.
  BrushFrameEditingCoordinator inked() {
    final coordinator = BrushCanvasFixture.createCoordinator(frameKeys: cels);
    coordinator.commitSourceStroke(
      sourceDabs: [
        for (var x = 40; x <= 80; x += 2)
          BrushDab(
            center: CanvasPoint(x: x.toDouble(), y: 60),
            color: 0xFF2040C0,
            size: 6,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
          ),
      ],
    );
    return coordinator;
  }

  PieceGround standingOn(BrushFrameEditingCoordinator coordinator) =>
      PieceGround(
        cels: [coordinator.activeFrameKey],
        placementOf: (_) => null,
      );

  List<int> trailOf(BrushFrameEditingCoordinator coordinator) => [
    for (var y = 50; y <= 70; y += 1)
      for (var x = 40; x <= 72; x += 1)
        surfaceRgbaInPlace(
              coordinator.currentSurfaceOf(coordinator.activeFrameKey),
              x,
              y,
            ) ??
            0,
  ];

  test('a ground on one cel keeps the keys of the ladder that name it, in '
      "the ladder's order, and no other — what a drag shows of the cel on "
      'screen reads no other row', () {
    final ground = PieceGround(
      cels: [cels[0], cels[1], cels[2], cels[1]],
      placementOf: (_) => null,
    );
    // cels[2] reads as cels[0]: a linked row is a window onto another's cel.
    BrushFrameKey canonical(BrushFrameKey key) =>
        key == cels[2] ? cels[0] : key;

    expect(ground.on(cels[0], canonical).cels, [cels[0], cels[2]]);
    expect(ground.on(cels[1], canonical).cels, [cels[1], cels[1]]);
  });

  test('🚨a cel takes the drag as ONE landing — one derive, every stamp in '
      'it', () {
    final coordinator = inked();
    final landed = pieceLandings(
      coordinator: coordinator,
      ground: PieceGround(
        cels: cels.take(2).toList(),
        placementOf: (_) => null,
      ),
      stamp: PieceStamp.along(
        laid: laid,
        blend: BrushBlendMode.color,
        description: 'Stamp',
      ),
    );

    expect(landed.keys, cels.take(2), reason: 'one landing per cel');
    for (final cel in landed.values) {
      expect(cel.dabs, hasLength(3), reason: 'every stamp of the drag');
      final landing = cel.landing;
      landing.execute();
      expect(landing.derivesHere, 1, reason: 'one derive, not one a stamp');
    }
  });

  for (final blend in [
    BrushBlendMode.color,
    BrushBlendMode.behind,
    BrushBlendMode.erase,
  ]) {
    test('🚨…the very picture its stamps land one at a time — ${blend.name}',
        () {
      final oneByOne = inked();
      for (final onTheRow in laid) {
        for (final cel in pieceLandings(
          coordinator: oneByOne,
          ground: standingOn(oneByOne),
          stamp: PieceStamp(
            onTheRow: onTheRow,
            blend: blend,
            description: 'Stamp',
          ),
        ).values) {
          cel.landing.execute();
        }
      }
      final atOnce = inked();
      for (final cel in pieceLandings(
        coordinator: atOnce,
        ground: standingOn(atOnce),
        stamp: PieceStamp.along(
          laid: laid,
          blend: blend,
          description: 'Stamp',
        ),
      ).values) {
        cel.landing.execute();
      }

      final before = trailOf(inked());
      expect(
        trailOf(oneByOne),
        isNot(before),
        reason: 'LIVENESS: the stamps changed the cel',
      );
      expect(trailOf(atOnce), trailOf(oneByOne));
    });
  }
}
