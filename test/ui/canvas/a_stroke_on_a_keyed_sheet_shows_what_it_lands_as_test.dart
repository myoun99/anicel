import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cel_text_tool_harness.dart';

/// card a-stroke-on-a-keyed-row-shows-its-tiles-unkeyed — A STROKE DRAWN
/// ON A ROW THAT KEYS A SHEET'S PAPER AWAY SHOWS WHAT IT LANDS AS, WHILE
/// THE PEN IS DOWN (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로
/// 다르면 안 되」).
///
/// 🔬공통 measured it in the whole app (10-16): on the keyed row the canvas
/// drew the paper bare in every tile the stroke had touched until the pen
/// came up — 2,868 pixels apart from the landing, 0 on a bare row. This
/// draws with the pen and reads what the canvas draws for the cel under it
/// while the stroke is live and once it has landed, over the same sheet.
void main() {
  const paper = [64, 192, 96, 255];
  const rule = [30, 30, 30, 255];

  /// [paper] taken away.
  LayerEffect paperKey() => LayerEffect(
    id: const EffectId('paper-key'),
    kind: EffectKind.colorKey,
    colors: {
      'keyColor': PropertyTrack<int>.empty().withKey(
        0,
        0xFF000000 | paper[0] << 16 | paper[1] << 8 | paper[2],
      ),
    },
    parameters: {
      'tolerance': EffectParameter(value: 10),
      'amount': EffectParameter(value: 100),
    },
  );

  /// [cel] with [page] covered in [paper], a [rule] every 16 rows from its
  /// top.
  BitmapSurface pageOn(BitmapSurface cel, Rect page) {
    final size = cel.tileSize;
    final placed = <({TileCoord coord, BitmapTile tile})>[];
    for (var ty = page.top ~/ size; ty * size < page.bottom; ty += 1) {
      for (var tx = page.left ~/ size; tx * size < page.right; tx += 1) {
        final pixels = Uint8List(size * size * 4);
        for (var i = 0; i < size * size; i += 1) {
          final x = tx * size + i % size;
          final y = ty * size + i ~/ size;
          if (page.contains(Offset(x + 0.5, y + 0.5))) {
            pixels.setAll(i * 4, (y - page.top) % 16 == 0 ? rule : paper);
          }
        }
        placed.add((
          coord: TileCoord(x: tx, y: ty),
          tile: BitmapTile(size: size, pixels: pixels),
        ));
      }
    }
    return cel.putTiles(placed);
  }

  /// The canvas over a page laid on the cel, before a pen stroke over it,
  /// while it is drawn and once it has landed.
  Future<({Uint8List before, Uint8List drawing, Uint8List landed})>
  strokeOverPage(WidgetTester tester) async {
    // The text tool's layer says where the canvas is on the screen.
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    final page = Rect.fromLTWH(c.dx - 96, c.dy - 96, 192, 192);
    final from = onScreen(tester, c.dx, c.dy);
    coordinatorOf(
      tester,
    ).restoreSurfaceSnapshot(textToolKey, pageOn(celOf(tester), page));
    await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
    await pumpFrames(tester, 12);
    final stored = celOf(tester);
    final before = await canvasRaster(tester, page);

    final pen = await tester.startGesture(
      from,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    for (var i = 1; i <= 6; i += 1) {
      await pen.moveTo(from + Offset(6.0 * i, 4.0 * i));
      await tester.pump();
    }
    await pumpFrames(tester, 12);
    final drawing = await canvasRaster(tester, page);
    await pen.up();
    await pumpFrames(tester, 12);
    final landed = await canvasRaster(tester, page);

    expect(drawing, isNot(before), reason: '⛔CONTROL: the stroke shows');
    expect(
      identical(celOf(tester), stored),
      isFalse,
      reason: '⛔CONTROL: the stroke landed on the cel',
    );
    return (before: before, drawing: drawing, landed: landed);
  }

  for (final keyed in [true, false]) {
    testWidgets('🚨a stroke on a page whose paper the row keys away shows '
        'what it lands as while the pen is down — keyed $keyed', (
      tester,
    ) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(effects: [if (keyed) paperKey()]),
      );

      final (:before, :drawing, :landed) = await strokeOverPage(tester);

      expect(before.sublist(0, 4), rule, reason: '⛔fixture: the page shows');
      expect(
        before.sublist(4 * 192, 4 * 192 + 4),
        keyed ? isNot(paper) : paper,
        reason: '⛔fixture: the row keys its paper away, or does not',
      );
      expect(drawing, landed, reason: 'what is drawn is what lands');
    });
  }

  testWidgets('🚨a stroke on a row whose chain runs a PLUGIN shows what it '
      'lands as while the pen is down — the whole cel the plugin makes, from '
      'the plugin this device has installed (🗣️I-132-Q32 b)', (tester) async {
    await pumpTextToolApp(
      tester,
      project: textToolProject(effects: [shiftingFxPluginLayerEffect()]),
      fxPlugins: await installedShiftingFxPlugin(tester),
    );

    final (:before, :drawing, :landed) = await strokeOverPage(tester);

    expect(
      [before.sublist(0, 4), before.sublist(4, 8)],
      [isNot(rule), rule],
      reason: '⛔fixture: the plugin runs on the canvas — the page shows one '
          'pixel to the right',
    );
    expect(drawing, landed, reason: 'what is drawn is what lands');
  });
}
