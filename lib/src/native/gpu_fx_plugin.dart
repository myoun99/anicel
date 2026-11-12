import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../core/on_a_worker.dart';
import '../models/app_gpu_settings.dart';
import '../models/effect_parameter_spec.dart';
import '../models/fx_plugin_description.dart';
import '../models/fx_plugin_run.dart';
import 'app_gpu_engine.dart';

/// What opening a plugin's WGSL came to: the plugin, or the engine's words
/// of why not.
typedef GpuFxPluginOpened = ({GpuFxPlugin? plugin, String? refusal});

/// A GPU fx plugin (fx spec 2) opened on the app's engine: its reach run
/// on the CPU, its picture on the GPU, each pixel of a run cut once it
/// spends this machine's share ([AppGpuSettings.pluginShare]) — or, opened
/// not to be cut, no run cut on the device.
///
/// ⚠️Asked by one isolate at a time — its runs go on a worker each
/// ([render]); [close] lets it go once none is on its way.
final class GpuFxPlugin implements FxPluginRunner {
  GpuFxPlugin._(this._plugin, this._kinds);

  /// [source] checked, counted and compiled on the app's engine — with no
  /// count for the device where [cut] is false — its values read as
  /// [description]'s parameters say; or why not.
  static GpuFxPluginOpened open(
    String source,
    FxPluginDescription description, {
    required bool cut,
  }) {
    try {
      return _opened(
        GpuPlugin.open(appGpuEngine, source, cut: cut),
        description,
      );
    } on StateError catch (error) {
      return (plugin: null, refusal: error.message);
    }
  }

  /// [open] off this isolate, which goes on meanwhile ([GpuPlugin.opening]).
  static Future<GpuFxPluginOpened> opening(
    String source,
    FxPluginDescription description, {
    required bool cut,
  }) async {
    try {
      return _opened(
        await GpuPlugin.opening(appGpuEngine, source, cut: cut),
        description,
      );
    } on StateError catch (error) {
      return (plugin: null, refusal: error.message);
    }
  }

  static GpuFxPluginOpened _opened(
    GpuPlugin plugin,
    FxPluginDescription description,
  ) => (
    plugin: GpuFxPlugin._(plugin, [
      for (final spec in description.parameters) _kindOf(spec.unit),
    ]),
    refusal: null,
  );

  GpuPlugin? _plugin;
  final List<GpuPluginValue> _kinds;

  static FxPluginShare get _share => AppGpu.settings.value.pluginShare;

  /// None: it is open as it is made ([open], [opening]).
  @override
  Future<void>? get toCome => null;

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
      return plugin.reach(
        _asked(values, moment),
        share: _share.reachShare,
      );
    } on StateError {
      return null;
    }
  }

  /// The runs on their way ([render]): [close] frees the plugin once the
  /// last of them has ended, never under one.
  int _running = 0;

  /// Run on a worker ([onAWorker]), the waits for the GPU — a chunk at a
  /// time — that worker's, so the isolate that asks goes on meanwhile.
  ///
  /// 🧭관제 2026-11-12 08:5x (float-warp-resamples-in-the-c-engine): 「그
  /// 142–158 ms 동안 UI 스레드(또는 래스터 스레드)가 붙잡히는가 … 붙잡으면 이
  /// 레인 안에서 그 통과를 UI 밖으로 내고」. 🔬Surface Pro 11, profile,
  /// S5_BA cut 352, a box dragged over a row under a device plugin, a step
  /// 4,061,184 pixels: this run 72–94 ms p50 on the UI thread each time
  /// the box moved, and the read of its input 56–60 ms (`_ChainPicture`).
  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) async {
    final plugin = _plugin;
    if (plugin == null) {
      return null;
    }
    _running += 1;
    try {
      final drawn = await _renderedOnAWorker(plugin.renderer, (
        input: _pictureOf(input),
        layers: [for (final layer in layers) _pictureOf(layer)],
        asked: _asked(values, moment),
        share: _share.share,
      ));
      return drawn?.buffer.asUint8List(
        drawn.offsetInBytes,
        drawn.lengthInBytes,
      );
    } finally {
      _running -= 1;
      if (_running == 0 && _plugin == null) {
        _free(plugin);
      }
    }
  }

  @override
  void close() {
    final plugin = _plugin;
    _plugin = null;
    if (plugin != null && _running == 0) {
      _free(plugin);
    }
  }

  void _free(GpuPlugin plugin) {
    plugin.free();
    _letGo = true;
  }

  bool _letGo = false;

  /// Test seam: whether the device's build has been let go of ([close]).
  @visibleForTesting
  bool get debugLetGo => _letGo;
}

/// What a run of a plugin is asked with: its input over its layers, its
/// values and moment, and each pixel's share — plain values, as a worker
/// is handed them.
typedef _Run = ({
  GpuPluginPicture input,
  List<GpuPluginPicture> layers,
  GpuPluginAsked asked,
  int share,
});

/// [renderer]'s picture of [run] on a worker ([onAWorker]) — null where
/// it refused. Made here, of plain values, so the job crosses with them
/// alone.
Future<Uint32List?> _renderedOnAWorker(
  GpuPluginRenderer renderer,
  _Run run,
) => onAWorker(() {
  try {
    return renderer.render(run.input, run.layers, run.asked, share: run.share);
  } on StateError {
    return null;
  }
});

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
