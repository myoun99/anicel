import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/viewer_ink_keys.dart';

import '../../helpers/carried_media_fixture.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';

/// The ink a viewer writes on a carried file (I-114) rides the .anicel
/// archive as the sheets' does. What it is keyed to is the CARRY — so load
/// prunes the ink of a file the pool no longer carries, and keeps every
/// page of one it does.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-viewer-ink');
  });

  tearDown(() => deleteTempQuietly(directory));

  BitmapSurface inkSurface({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 13 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 12),
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  testWidgets('a carried file\'s ink round-trips through save and open, '
      'every page of it; a carry the pool no longer holds prunes at LOAD; '
      'the main cel store never sees the namespace', (tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final carry = session.repository
        .requireProject()
        .mediaAssetByPath(path)!
        .carriedAs!;
    final store = session.renderCaches.viewerInkStore;
    final first = viewerInkPageKey(carry, 0);
    final second = viewerInkPageKey(carry, 1);
    final gone = viewerInkPageKey(mintMediaCarry(path), 0);
    store.storeBakedSurface(first, inkSurface(seed: 3));
    store.storeBakedSurface(second, inkSurface(seed: 4));
    store.storeBakedSurface(gone, inkSurface(seed: 5));
    expect(gone, isNot(first), reason: 'the premise: another carry');

    await saveProject(tester, session, directory);
    final loaded = (await tester.runAsync(
      () => openedSession(
        normalizedMediaPath('${directory.path}/project.anicel'),
      ),
    ))!;
    addTearDown(loaded.dispose);
    final reopened = loaded.renderCaches.viewerInkStore;

    expect(
      reopened.celHasRenderableContent(first),
      isTrue,
      reason: 'what was written on the file reopens with the project',
    );
    expect(
      reopened.celHasRenderableContent(second),
      isTrue,
      reason: 'every page of it, not just the first',
    );
    expect(
      reopened.celHasRenderableContent(gone),
      isFalse,
      reason: 'a file carried no more takes its ink with it',
    );
    expect(
      loaded.renderCaches.brushFrameStore.fileCelKeys.where(isViewerInkKey),
      isEmpty,
      reason: 'viewer ink can never leak into a cel',
    );
  });
}
