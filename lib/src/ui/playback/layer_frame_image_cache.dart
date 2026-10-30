import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../services/brush_frame_display_cache_service.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cel_content_notes.dart';

/// The cels' stored pixels as a frame's one picture reads them
/// (`FramePictures`): each cel's preview surface, prepared from the brush
/// store's display cache ([BrushFrameDisplayCacheService]), and the one
/// record of the cels that could not be read ([unreadable]).
///
/// ↩️It kept one GPU image per (cel, quality) — a half and a quarter of each
/// row beside the whole, asked by the zoom — for every screen that stacked a
/// frame from its rows' images, until the onion ghosts, the last of them,
/// were a picture of their own (one-picture-per-frame ②-5b-1, 유저
/// 2026-10-25 「원본기준으로 해서 쓸데없는 소재 없애고 거기서 극한 최적화 해야지」).
class LayerFrameImageCache {
  LayerFrameImageCache({required this.frameStore});

  final BrushFrameStore frameStore;

  /// The cels whose pixels could not be read ([UnreadableCels]) — noted by
  /// every reading, the one record every maker and reader asks.
  late final UnreadableCels unreadable = UnreadableCels(frameStore);

  /// Brings [key]'s cel in hand ahead of [storedSurfaceOrNull]: thawed off
  /// the UI thread ([BrushFrameStore.thawAhead]), then its preview prepared.
  ///
  /// ⛔ONLY A HOT CEL'S PREVIEW IS PREPARED HERE: any other is read from
  /// storage on this thread by [storedSurfaceOrNull] — a cel whose thaw
  /// failed is read there, which says why it will not.
  Future<void> readIn(BrushFrameKey key, {required CanvasSize canvasSize}) async {
    await frameStore.thawAhead(key, canvasSize: canvasSize);
    if (frameStore.hotBakedSurfaceOrNull(key) != null) {
      _previews(canvasSize).prepareFramePreview(key);
    }
  }

  /// [key]'s cel's stored pixels at [canvasSize] — what every picture of it
  /// is made of (`FramePictures`), before its texts and colour keys are laid
  /// (`celSurfaceAsShown`) — or null where they are held at ANOTHER canvas
  /// size: a picture made of the blank stand-in would bank the cel blank
  /// under a revision no heal moves. Throws where the cel cannot be read,
  /// and notes it ([unreadable]).
  ///
  /// ⚠️Ask [BrushFrameStore.celHasRenderableContent] first: an empty cel
  /// answers a blank surface, made for it here.
  BitmapSurface? storedSurfaceOrNull(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) => unreadable.notingNow(key, () {
    final preview = _previews(canvasSize).prepareFramePreview(key);
    return preview.isValid ? preview.previewSurface : null;
  });

  /// Whether [storedSurfaceOrNull] would read nothing for [key]: its stored
  /// pixels at [canvasSize] are read and laid out already — or it is a
  /// movie's, decoded at [canvasSize].
  ///
  /// 🐞A DECODED MOVIE IS IN HAND, though banked nowhere: its picture is
  /// the movie tier's (`BrushFrameStore.storeRebuiltDisplayCache` keeps no
  /// copy), and [storedSurfaceOrNull] hands it over at once. ↩️Asked of the
  /// bank alone until 2026-10-30, a movie was never in hand — and left out
  /// of the frame as it stands (`FramePictures.frameAsItStands`), the body
  /// a step on a row above it is patched into the frame's picture by
  /// (저장's hand-over on the 23.976 `.mov` card, read in the code).
  bool storedSurfaceIsInHand(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) =>
      _previews(canvasSize).preparedFramePreviewOrNull(key) != null ||
      frameStore.hasMovieCel(key, canvasSize);

  BrushFrameDisplayCacheService _previews(CanvasSize canvasSize) =>
      BrushFrameDisplayCacheService(
        frameStore: frameStore,
        canvasSize: canvasSize,
      );

  void dispose() => unreadable.dispose();
}
