import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart' show GpuSampling;

/// What a show of a canvas's screen asked of the engine: the box round the
/// texels of its target it drew, columns by rows — what the view holds
/// through another camera, or where the frame was made again since the
/// target's last and what the target did not hold once moved
/// (`EngineStackScreen.show`) —, how many texels its walks drew,
/// by how many texels it moved what the target held first (null, none),
/// the display's scale there (`displayScaleOf`) and R1's mode by it.
typedef ScreenAsk = ({
  int columns,
  int rows,
  int texels,
  (int, int)? moved,
  double scale,
  GpuSampling mode,
});

/// [asked] as the readouts write it — the frame statistics' draw line
/// (`FrameStatsReadout`) and the engine's stages' slowest frame
/// (`EngineStages`): the box, how many texels where its walks drew other
/// than all of it, the move, the scale and the mode.
String screenAskWords(ScreenAsk asked) {
  final (:columns, :rows, :texels, :moved, :scale, :mode) = asked;
  final drew = texels == columns * rows ? '' : ' drew ${_counted(texels)}';
  final by = switch (moved) {
    null => '',
    (final dx, final dy) => ' moved $dx,$dy',
  };
  return '${columns}x$rows$drew$by  x${scale.toStringAsFixed(2)}  '
      '${mode.name}';
}

/// [count] in a few figures: millions to a tenth, thousands whole.
String _counted(int count) => switch (count) {
  >= 1000000 => '${(count / 1000000).toStringAsFixed(1)}M',
  >= 1000 => '${(count / 1000).round()}k',
  _ => '$count',
};

/// 🔬What the newest show of a canvas's screen asked of the engine
/// (`EngineStackScreen.show`, where it is told): a show reads every texel
/// it draws in its mode — Blend walks each pixel's reach, Nearest reads
/// one —, so how long a frame took on the GPU says little without how
/// many texels it read and how. The frame statistics read it beside that
/// time (`FrameStats`, the readout's ` draw` line). A show that drew
/// nothing — nothing made again since its target's last — tells none,
/// and the one before it stands.
///
/// 🗣️유저's photographs of a Galaxy Tab out of this machine's reach held
/// the readout alone (2026-11-21, card
/// the-galaxy-tab-canvas-went-slow-on-build-1095): neither the view's
/// scale nor its panel's size was in them, and the scale is what picks
/// the mode.
abstract final class ScreenAsked {
  /// The newest show's ask; null till a screen is shown.
  static ScreenAsk? get last => _last;
  static ScreenAsk? _last;

  /// How many shows told their ask so far: whether one did between two
  /// readings, where [last] alone could be the one before (`StrokeSteps`).
  static int get shows => _shows;
  static int _shows = 0;

  /// A screen was shown as [ask] says.
  static void shown(ScreenAsk ask) {
    _last = ask;
    _shows += 1;
  }

  /// None shown, as before the first.
  @visibleForTesting
  static void debugForget() => _last = null;
}
