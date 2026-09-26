import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🔎clipboard-held-pictures-uncounted (2026-09-26): a copy holds its cels'
/// pictures by value, and a picture the clipboard alone holds — its source
/// drawn over since — was in no row of the census, so the panel read it out
/// as the engine's.
void main() {
  // The census reads the image cache, and that needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  late EditorSessionManager session;
  late BrushFrameKey drawn;
  late BitmapSurface picture;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    drawOnCurrentFrame(session);
    final selection = session.editingCanvas.activeBrushEditorSelection!;
    drawn = session.brushFrameKeyForCut(
      session.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    picture = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(drawn)!;
  });

  int drawingsRow(List<EditorSessionManager> sessions) => collectMemoryCensus(
    sessions,
  ).items.firstWhere((item) => item.id == 'drawings').bytes;

  int storesHold(EditorSessionManager session) =>
      session.renderCaches.brushFrameStore.hotBakedBytes +
      session.renderCaches.brushFrameStore.reclaimableViewBytes;

  /// The source drawn over: every tile of [picture] replaced by one the
  /// clipboard does not hold.
  BitmapSurface drawOver() {
    final over = BitmapSurface(
      canvasSize: picture.canvasSize,
      tileSize: picture.tileSize,
      tiles: {
        for (final coord in picture.tiles.keys)
          coord: BitmapTile(
            size: picture.tileSize,
            pixels: Uint8List(picture.tileSize * picture.tileSize * 4)
              ..fillRange(0, 4, 0xFF),
          ),
      },
    );
    session.renderCaches.brushFrameStore.storeBakedSurface(drawn, over);
    return over;
  }

  test('a copy whose source stands untouched adds nothing — it shares every '
      'tile with it', () {
    session.layerClipboard.copyActiveLayer();
    expect(
      session.appClipboard.heldPictures,
      contains(same(picture)),
      reason: 'fixture premise: the copy holds the picture',
    );

    expect(drawingsRow([session]), storesHold(session));
  });

  test('drawn over, the source lets go and the copy alone holds what it '
      'took — counted', () {
    session.layerClipboard.copyActiveLayer();
    final over = drawOver();
    final kept = picture.bytesNotSharedWith(over);
    expect(kept, greaterThan(0), reason: 'fixture premise');

    expect(drawingsRow([session]), storesHold(session) + kept);
  });

  test('what both boards hold, and what the app\'s one board holds for two '
      'open projects, is counted once', () {
    final other = EditorSessionManager(
      initialProject: createDefaultProject(),
      appClipboard: session.appClipboard,
    );
    addTearDown(other.dispose);
    session.layerClipboard.copyActiveLayer();
    session.clipboard.copyFrameAtCurrentFrame();
    expect(
      session.appClipboard.heldPictures.where((held) => identical(
        held,
        picture,
      )),
      hasLength(2),
      reason: 'fixture premise: both boards hold the one picture',
    );
    final over = drawOver();

    expect(
      drawingsRow([session, other]),
      storesHold(session) + storesHold(other) + picture.bytesNotSharedWith(over),
    );
  });
}
