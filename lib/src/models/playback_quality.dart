import 'dart:math' as math;

import 'canvas_size.dart';

/// Playback preview resolution presets, like the Premiere/AE monitor
/// quality selector. The scale applies to the cached raster size; the view
/// upscales back to canvas size on screen.
///
/// Since 2026-09-16 each preset is also a LEVEL of the display's pyramid
/// ([level]): the editing canvas below 100% asks for the other layers'
/// images at the level it composes at, so one cache serves both.
enum PlaybackQuality {
  full(1.0),
  half(0.5),
  quarter(0.25);

  const PlaybackQuality(this.scale);

  final double scale;

  /// How many times the artwork is halved for this preset.
  int get level => switch (this) {
    PlaybackQuality.full => 0,
    PlaybackQuality.half => 1,
    PlaybackQuality.quarter => 2,
  };

  /// How many halvings the deepest preset takes — the pyramid's depth.
  static final int deepestLevel = PlaybackQuality.values
      .map((quality) => quality.level)
      .reduce(math.max);

  /// The preset that is the display's [level] — the deepest preset for a
  /// level past it, reduced the rest of the way by the blit.
  static PlaybackQuality forLevel(int level) => switch (level) {
    0 => PlaybackQuality.full,
    1 => PlaybackQuality.half,
    _ => PlaybackQuality.quarter,
  };
}

/// The raster size cached for [quality]; never collapses below 1×1.
CanvasSize scaledCanvasSize(CanvasSize size, PlaybackQuality quality) {
  return CanvasSize(
    width: math.max(1, (size.width * quality.scale).round()),
    height: math.max(1, (size.height * quality.scale).round()),
  );
}
