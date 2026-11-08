import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import '../models/app_gpu_settings.dart';
import '../models/effect_parameter_spec.dart';
import '../models/fx_plugin_description.dart';
import '../models/fx_plugin_run.dart';
import 'app_gpu_engine.dart';

/// What opening a plugin's WGSL came to: the plugin, or the engine's words
/// of why not.
typedef GpuFxPluginOpened = ({GpuFxPlugin? plugin, String? refusal});

/// A GPU fx plugin (fx spec 2) opened on the app's engine: its reach run
/// on the CPU, its picture on the GPU, each cut once it spends its share
/// of this machine's limit ([AppGpuSettings.pluginLimit]).
///
/// ⚠️Asked by one thread at a time; [close] lets it go.
final class GpuFxPlugin implements FxPluginRunner {
  GpuFxPlugin._(this._plugin, this._kinds);

  /// [source] checked, counted and compiled on the app's engine, its
  /// values read as [description]'s parameters say — or why not.
  static GpuFxPluginOpened open(
    String source,
    FxPluginDescription description,
  ) {
    try {
      final plugin = GpuPlugin.open(appGpuEngine, source);
      final kinds = [
        for (final spec in description.parameters) _kindOf(spec.unit),
      ];
      return (plugin: GpuFxPlugin._(plugin, kinds), refusal: null);
    } on StateError catch (error) {
      return (plugin: null, refusal: error.message);
    }
  }

  GpuPlugin? _plugin;
  final List<GpuPluginValue> _kinds;

  static int get _limit => AppGpu.settings.value.pluginLimit;

  GpuPluginAsked _asked(Float64List values, FxPluginMoment moment) => (
    values: values,
    kinds: _kinds,
    frame: moment.frameIndex,
    time: moment.time,
    rate: moment.frameRate,
    scale: moment.scale,
  );

  @override
  int? reach(Float64List values, FxPluginMoment moment) {
    final plugin = _plugin;
    if (plugin == null) {
      return null;
    }
    try {
      // ⏳Of how many pixels the reach spends one's share is
      // an-endless-plugin-stalls-the-app-Q12's to say; one, the whole
      // limit, until it does.
      return plugin.reach(_asked(values, moment), limit: _limit, pixels: 1);
    } on StateError {
      return null;
    }
  }

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    final plugin = _plugin;
    if (plugin == null) {
      return null;
    }
    try {
      final drawn = plugin.render(
        _pictureOf(input),
        [for (final layer in layers) _pictureOf(layer)],
        _asked(values, moment),
        limit: _limit,
      );
      return drawn.buffer.asUint8List(
        drawn.offsetInBytes,
        drawn.lengthInBytes,
      );
    } on StateError {
      return null;
    }
  }

  @override
  void close() {
    _plugin?.free();
    _plugin = null;
  }
}

/// How a value of [unit] reaches the plugin — the doubles
/// `fxPluginValuesOf` gives it, as the engine makes them its integers
/// (prelude.wgsl's `AnicelFrame`).
GpuPluginValue _kindOf(EffectParameterUnit unit) => switch (unit) {
  EffectParameterUnit.number ||
  EffectParameterUnit.degrees ||
  EffectParameterUnit.pixels ||
  EffectParameterUnit.point => GpuPluginValue.fixed,
  EffectParameterUnit.color => GpuPluginValue.channels,
  EffectParameterUnit.choice ||
  EffectParameterUnit.flag ||
  EffectParameterUnit.layer => GpuPluginValue.whole,
};

/// [picture] as the engine reads it: a word a pixel, its bytes R, G, B, A
/// in the word's order from its low end (every device the app runs on is
/// little-endian) — a view where its bytes start on a word, else a copy.
GpuPluginPicture _pictureOf(FxPluginPicture picture) {
  final bytes = picture.pixels;
  final words = bytes.offsetInBytes % 4 == 0
      ? bytes.buffer.asUint32List(bytes.offsetInBytes, bytes.length ~/ 4)
      : Uint8List.fromList(bytes).buffer.asUint32List();
  return (
    pixels: words,
    left: picture.left,
    top: picture.top,
    width: picture.width,
    height: picture.height,
  );
}
