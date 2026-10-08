import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/psd_expand_import.dart';

import '../../helpers/psd_fixture.dart';

/// F-307 (유저 2026-10-06): 「포토샵으로 열면 문제없는데 … 黒枠라는 레이어가
/// 캔버스크기보다 더 위아래로 그림이 더 많은 상태로 임포트됬음」 — the pixel
/// half: a layer that runs past the document's edges lands as only its part
/// inside, where Photoshop shows it, and nothing of it reaches the
/// pasteboard.
void main() {
  testWidgets('🎯a layer past the document\'s top and bottom lands as its '
      'part inside the document, and no more', (tester) async {
    var layers = 0;
    var frames = 0;
    final bytes = buildPsd(
      width: 100,
      height: 60,
      layers: [
        // 20 above the document and 20 below it.
        PsdTestLayer(
          name: 'frame',
          left: 0,
          top: -20,
          right: 100,
          bottom: 80,
          planes: psdSolidPlanes(100, 100, [200, 0, 0]),
        ),
      ],
    );

    final expansion = await tester.runAsync(
      () => readPsdExpansion(
        bytes: bytes,
        displayName: 'frame.psd',
        cutId: const CutId('c'),
        duration: 12,
        canvas: const CanvasSize(width: 1, height: 1),
        fit: MediaFitMode.none,
        mint: ImportIdMint(
          nextLayerId: () => LayerId('L${layers += 1}'),
          nextFrameId: (_) => FrameId('F${frames += 1}'),
          nextCutId: () => const CutId('C1'),
        ),
        canvasFromDocument: true,
      ),
    );
    final surface = expansion!.cels.single.surface;

    expect(
      surface.tiles.keys,
      [TileCoord(x: 0, y: 0)],
      reason: 'nothing above the document, on the pasteboard',
    );
    final pixels = surface.tiles[TileCoord(x: 0, y: 0)]!.pixels;
    int alphaAt(int x, int y) => pixels[(y * 128 + x) * 4 + 3];
    expect(alphaAt(5, 0), 255, reason: 'the document\'s top row');
    expect(alphaAt(5, 59), 255, reason: 'its bottom row');
    expect(alphaAt(5, 60), 0, reason: 'below the document, nothing');
  });
}
