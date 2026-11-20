// Each engine compiles the lift's kernels where it first lifts: tens of
// seconds apiece on a machine this busy, and the test has two.
@Timeout(Duration(minutes: 5))
library;

import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show SelectionMaskOptions;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/selection_lift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — 「잃는 것은 그리던 획 정도다」. What a selection took stays
/// on the engine and has no bytes here till something asks for them
/// (`EngineStampPictures.lifted`, board
/// `lifting-a-cel-goes-gpu-cpu-gpu-and-zero-fills`): so the next engine
/// takes it again off the cel it was taken from — a value, as it stood —
/// and nothing of it is lost with a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugSelectionLiftInDart = false);

  const side = 128;
  BitmapSurface artwork() {
    final bytes = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      bytes
        ..[i * 4] = (i * 31) % 256
        ..[i * 4 + 1] = (i * 17) % 256
        ..[i * 4 + 2] = (i * 13 + 5) % 256
        ..[i * 4 + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 256, height: 256),
      tileSize: side,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: side, pixels: bytes)},
    );
  }

  SelectionPixels? lift(BitmapSurface surface) => liftSelectionPixels(
    region: CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 3, top: 5, right: 70, bottom: 41),
    ),
    surface: surface,
    options: SelectionMaskOptions.none,
    stampId: 'kept',
  );

  test('a lift is taken again off its cel on the next engine, as it was '
      'taken — not handed up, and not read from the engine let go', () {
    final surface = artwork();
    debugSelectionLiftInDart = true;
    final asItWas = lift(surface)!.stamp.rgba;
    debugSelectionLiftInDart = false;
    final lifted = lift(surface)!;
    final first = EngineStampPictures.of(lifted.stamp);
    final handedUp = EngineStampPictures.debugHandedUp;

    theAppsEngineLostAndLetGo();

    expect(identical(EngineStampPictures.of(lifted.stamp), first), isFalse);
    expect(lifted.stamp.rgba, asItWas);
    expect(
      EngineStampPictures.debugHandedUp,
      handedUp,
      reason: 'taken again off the cel, not handed up',
    );
  });
}
