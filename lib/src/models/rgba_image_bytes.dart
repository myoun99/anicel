import 'bitmap_tile.dart' show BitmapTile;

/// Estimated resident bytes of an RGBA image of the given dimensions.
///
/// Every cache in this app that holds `ui.Image`s bills them through here
/// — the playback composites, the layer frames, and the media viewer's
/// pages. It moved out of `playback_cache_budget.dart` when the viewer
/// became the fourth: a second copy of `width * height * 4` would have
/// been the app's third way of saying one thing.
///
/// ⚠️An ESTIMATE. Skia is free to keep a texture in some other form; what
/// the budgets need is a number that is proportional and consistent
/// across the caches comparing themselves to one budget, and this is
/// exactly the number [BitmapTile] uses for the pixels we own outright.
int estimatedImageBytes(int width, int height) =>
    width * height * BitmapTile.bytesPerPixel;
