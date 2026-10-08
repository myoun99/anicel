import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): the
/// box a layer's transform is edited by frames the layer's PICTURE (R5 #10:
/// 「레이어 그림의 바운드에 걸리는게 알기쉬울거같기도하고」), and a text on the
/// cel is part of that picture — the row's transform moves it with the
/// drawing. So the box takes the letters in.
void main() {
  testWidgets('the layer\'s ink box takes in a text on its cel — one that '
      'stands alone, with nothing drawn', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    Layer layer() => session.activeCutOrNull!.layers.firstWhere(
      (candidate) => candidate.id == layerId,
    );
    final coordinator = session.pixelEditing.coordinator!;
    final key = coordinator.activeFrameKey;
    expect(
      session.renderCaches.layerContentBoundsAt(layer(), 0),
      isNull,
      reason: '⛔premise: nothing is on the cel yet',
    );

    // One letter-pixel at (3, 5) of the tile at (2, 1).
    final bare = coordinator.currentSurfaceOf(key);
    final size = bare.tileSize;
    final pixels = Uint8List(BitmapTile.bytesFor(size));
    pixels.setAll((5 * size + 3) * 4, [0, 0, 0, 255]);
    coordinator.restoreSurfaceSnapshot(
      key,
      bare.withTexts([
        CelText(
          id: 1,
          content: CelTextContent(
            spans: const [CelTextSpan(text: 'a', style: TextLetterStyle())],
            anchor: CanvasPoint(x: 0, y: 0),
          ),
          plate: {
            TileCoord(x: 2, y: 1): BitmapTile(size: size, pixels: pixels),
          },
        ),
      ]),
    );

    final box = session.renderCaches.layerContentBoundsAt(layer(), 0);

    expect(box, isNotNull, reason: 'the cel shows a letter');
    expect(
      (box!.left, box.top, box.rightExclusive, box.bottomExclusive),
      (2 * size + 3, size + 5, 2 * size + 4, size + 6),
    );

    session.playbackRig.prerenderScheduler.cancel();
  });
}
