import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart' show GpuSampling;

/// What a show of a canvas's screen asked of the engine: the texels of
/// its target it drew, columns by rows — all of them, or where the frame
/// was made again since the target's last (`EngineStackScreen.show`) —,
/// the display's scale there (`displayScaleOf`) and R1's mode by it.
typedef ScreenAsk = ({int columns, int rows, double scale, GpuSampling mode});

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

  /// A screen was shown as [ask] says.
  static void shown(ScreenAsk ask) => _last = ask;

  /// None shown, as before the first.
  @visibleForTesting
  static void debugForget() => _last = null;
}
