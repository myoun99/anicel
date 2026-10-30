import 'dart:typed_data';

import 'bitmap_surface.dart';
import 'layer_id.dart';

/// A picture a plugin is handed or gives back: premultiplied RGBA8, rows
/// [width] × 4 bytes apart, its first pixel at ([left], [top]) on the
/// canvas.
typedef FxPluginPicture = ({
  Uint8List pixels,
  int width,
  int height,
  int left,
  int top,
});

/// When a plugin is asked: the frame's index from the cut's first, its
/// time in seconds, the frames a second, and the output pixels a canvas
/// pixel is drawn at (below 1 in a draft).
typedef FxPluginMoment = ({
  int frameIndex,
  double time,
  double frameRate,
  double scale,
});

/// What a plugin's effect is run through (anicel_fx_plugin.h): how far it
/// reaches, and the picture it makes — the engine's host for a plugin this
/// device has opened (`QaFxPlugin`), whatever its build.
abstract interface class FxPluginRunner {
  /// How far past its input the effect reaches for [values] (four doubles
  /// a parameter, anicel_fx_value) at [moment], in output pixels — or null
  /// where the plugin failed to say.
  int? reach(Float64List values, FxPluginMoment moment);

  /// [input] as the effect draws it, its size and place — or null where the
  /// plugin failed (the row is then drawn as if the effect were off).
  /// [layers] are the rows its layer parameters name, in the places the
  /// values give them.
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  });

  /// Lets the build go; asked after, it answers nothing — null, the effect
  /// off — as a picture still holding it may ask.
  void close();
}

/// What a plugin's effect is RUN WITH at one frame of one cut: this
/// device's build of it, the moment, and the picture of each row its layer
/// parameters name — that row's own, as its cel holds it at that frame
/// (🗣️I-132-Q32 b 「레이어 칸은 고른 셀 행의 자기 픽셀을 용지 그대로 읽는다(그
/// 행의 변형 · fx 없이)」), null for a row with no cel there.
///
/// ★BOUND WHERE THE CUT IS KNOWN, CARRIED WITH THE EFFECT. Every route that
/// shows a cel hands the seam its chain and nothing else — the stack, the
/// live stroke, a float, playback, export — so the plugin's run rides the
/// chain to all of them, and none is told a frame rate or a store.
final class FxPluginRun {
  FxPluginRun({
    required this.runner,
    required this.moment,
    required Map<LayerId, BitmapSurface?> rows,
  }) : rows = Map.unmodifiable(rows);

  final FxPluginRunner runner;
  final FxPluginMoment moment;

  /// The rows the effect's layer parameters name that are in its cut.
  final Map<LayerId, BitmapSurface?> rows;

  /// ⛔A row's picture is the SAME OBJECT, not an equal one: a picture is
  /// immutable, so an edited row is another object — and a deep compare of
  /// every tile per frame is what the identity is there to spare.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxPluginRun &&
          identical(other.runner, runner) &&
          other.moment == moment &&
          other.rows.length == rows.length &&
          rows.entries.every(
            (row) =>
                other.rows.containsKey(row.key) &&
                identical(other.rows[row.key], row.value),
          );

  @override
  int get hashCode => Object.hash(
    identityHashCode(runner),
    moment,
    Object.hashAllUnordered([
      for (final row in rows.entries)
        Object.hash(row.key, identityHashCode(row.value)),
    ]),
  );
}
