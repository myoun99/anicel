// GPU ENGINE PROBE — stage 0 of the GPU engine (gpu-engine-skeleton): a
// wgpu compute pass fills a texture that Flutter shows without a copy.
// Measures on THIS device: whether Flutter takes the texture as it is
// (Windows: whether ANGLE does; Android: whether the window's images take
// compute stores), the round trip of a frame, memory, and whether the
// screen shows the very bytes the GPU wrote. Whether the GPU wrote the
// pinned bytes is the crate's `cargo test`, against
// test/fixtures/fingerprints.json.
//
//   flutter run -d windows --release --dart-define=GPU_OUT=<dir>
//   flutter run -d <android device> --release
//
// Writes `report.txt` into GPU_OUT (default: gpu_probe_out in the system
// temp folder — the app's own cache on Android), prints it, and exits. On
// Windows the window opens behind everything without taking focus.
// Measurement, not a feature.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:gpu_engine/gpu_engine.dart';

const _outDir = String.fromEnvironment('GPU_OUT', defaultValue: '');

/// The surface the round trip is measured on.
const _side = 1024;

/// The surface read back off the screen, shown one texel per pixel.
const _shotSide = 256;

const _frames = 240;
const _seed = 1;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  final _boundary = GlobalKey();
  int? _textureId;
  double _textureSide = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final out = Directory(
      _outDir.isEmpty ? '${Directory.systemTemp.path}/gpu_probe_out' : _outDir,
    );
    await out.create(recursive: true);
    final report = StringBuffer();
    try {
      await _measure(report);
      report.writeln('DONE');
    } on Object catch (e, st) {
      report.writeln('FAILED: $e\n$st');
    }
    await File('${out.path}/report.txt').writeAsString(report.toString());
    print('${out.path}/report.txt\n$report');
    exit(0);
  }

  Future<void> _show(int? textureId, double side) async {
    setState(() {
      _textureId = textureId;
      _textureSide = side;
    });
    for (var i = 0; i < 3; i++) {
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  Future<void> _measure(StringBuffer report) async {
    final engine = GpuEngine.onFlutterAdapter();
    final luid = engine.adapterLuid;
    report
      ..writeln('adapter: ${engine.adapterName}'
          '${luid == null ? '' : ' (LUID ${_hex(luid, digits: 16)})'}')
      ..writeln('video memory at open: ${_videoMemory(engine)}')
      ..writeln('process RSS at open: ${_mib(ProcessInfo.currentRss)}');
    if (Platform.isAndroid) {
      await _measureWindow(report, engine);
    } else {
      for (final bgra in [true, false]) {
        await _measureOrder(report, engine, bgra: bgra);
      }
    }
    engine.close();
  }

  Future<void> _measureOrder(
    StringBuffer report,
    GpuEngine engine, {
    required bool bgra,
  }) async {
    final label = bgra ? 'BGRA' : 'RGBA';
    report.writeln('\n== $label ==');
    final GpuSurface front;
    try {
      front = engine.surface(_side, _side, bgra: bgra);
    } on StateError catch (e) {
      report.writeln('no surface: ${e.message}');
      return;
    }
    report.writeln('video memory with one $_side² surface: '
        '${_videoMemory(engine)}');

    _reportWhatAngleSees(report, front);
    if (!await _checkScreen(report, engine, bgra: bgra)) {
      // Timing a texture Flutter does not draw would measure nothing.
      report.writeln('not on screen: round trip not measured');
      front.free();
      return;
    }

    final single = SharedTexture.register(front);
    await _roundTrip(
      report,
      '$label single',
      single.id,
      fill: (i) => front.fill(_seed + i),
      show: (_) => single.show(0),
    );
    await _unregister([single]);
    // Two surfaces alternate: through one texture's two slots, so Flutter
    // reopens a handle every frame — or as two textures the widget
    // switches between, each opened once, since Flutter reopens only when
    // a texture's handle changes (external_texture_d3d.cc:84;
    // gpu-engine-feasibility ⑤).
    final back = engine.surface(_side, _side, bgra: bgra);
    GpuSurface slot(int i) => i.isOdd ? back : front;
    final slots = SharedTexture.register(front, back: back);
    await _roundTrip(
      report,
      '$label double',
      slots.id,
      fill: (i) => slot(i).fill(_seed + i),
      show: (i) => slots.show(i & 1),
    );
    await _unregister([slots]);
    final apart = [SharedTexture.register(front), SharedTexture.register(back)];
    await _roundTrip(
      report,
      '$label two textures',
      apart.first.id,
      fill: (i) => slot(i).fill(_seed + i),
      show: (i) {
        final texture = apart[i & 1];
        setState(() => _textureId = texture.id);
        texture.show(0);
      },
    );
    await _unregister(apart);
    report.writeln('video memory with two surfaces: ${_videoMemory(engine)}');
    back.free();
    front.free();
  }

  /// Android's way to the screen: the engine presents into a window
  /// Flutter made.
  Future<void> _measureWindow(StringBuffer report, GpuEngine engine) async {
    report.writeln('\n== window ==');
    final written = _written(engine);
    final shot = await engine.window(_shotSide, _shotSide);
    report.writeln(shot.direct
        ? "the window's images take compute stores: no copy"
        : "the window's images take no stores: one GPU copy a frame");
    shot
      ..fill(_seed)
      ..present();
    final shown = await _screenShows(report, shot.textureId, written);
    await shot.free();
    if (!shown) {
      report.writeln('not on screen: round trip not measured');
      return;
    }
    final window = await engine.window(_side, _side);
    await _roundTrip(
      report,
      'window',
      window.textureId,
      fill: (i) => window.fill(_seed + i),
      show: (_) => window.present(),
    );
    report.writeln('process RSS with one $_side² window: '
        '${_mib(ProcessInfo.currentRss)}');
    await window.free();
  }

  // ANGLE takes a client texture as it is only when it is renderable and
  // readable; otherwise it refuses it or reads through a copy of its own
  // (Flutter's pinned ANGLE, SwapChain11.cpp:251-257, 343-360).
  void _reportWhatAngleSees(StringBuffer report, GpuSurface surface) {
    final seen = surface.inspect();
    if (seen == null) {
      report.writeln('D3D11 could not open the shared handle');
      return;
    }
    const shaderResource = 0x8, renderTarget = 0x20, unordered = 0x80;
    const shared = 0x2, keyedMutex = 0x100, ntHandle = 0x800;
    String flags(int bits, Map<int, String> names) => [
      for (final MapEntry(key: flag, value: name) in names.entries)
        if (bits & flag != 0) name,
    ].join('|');
    final bind = flags(seen.bindFlags, {
      shaderResource: 'SHADER_RESOURCE',
      renderTarget: 'RENDER_TARGET',
      unordered: 'UNORDERED_ACCESS',
    });
    final misc = flags(seen.miscFlags, {
      shared: 'SHARED',
      keyedMutex: 'SHARED_KEYEDMUTEX',
      ntHandle: 'SHARED_NTHANDLE',
    });
    final direct = seen.bindFlags & renderTarget != 0 &&
        seen.bindFlags & shaderResource != 0;
    report
      ..writeln('D3D11 sees DXGI format ${seen.format}, bind $bind, '
          'misc $misc')
      ..writeln(direct
          ? 'renderable and readable: ANGLE needs no copy of its own '
              '(the format must still be its config\'s)'
          : 'not renderable or not readable: ANGLE refuses it or copies it');
  }

  /// The fingerprint of what the fill pass writes for [_seed] on a
  /// [_shotSide]² RGBA surface. The screen is read as RGBA, and the
  /// crate's tests pin that the two orders hold the same texels.
  int _written(GpuEngine engine) {
    final reference = engine.surface(_shotSide, _shotSide, bgra: false);
    reference.fill(_seed);
    final written = reference.fingerprint();
    reference.free();
    return written;
  }

  /// Whether the screen shows exactly the bytes the GPU wrote, through a
  /// shared texture.
  Future<bool> _checkScreen(
    StringBuffer report,
    GpuEngine engine, {
    required bool bgra,
  }) async {
    final written = _written(engine);
    final shot = engine.surface(_shotSide, _shotSide, bgra: bgra);
    shot.fill(_seed);
    final texture = SharedTexture.register(shot)..show(0);
    final shown = await _screenShows(report, texture.id, written);
    await _unregister([texture]);
    shot.free();
    return shown;
  }

  /// Whether texture [textureId], shown one texel per pixel, puts exactly
  /// the bytes whose fingerprint is [written] on the screen.
  Future<bool> _screenShows(
    StringBuffer report,
    int textureId,
    int written,
  ) async {
    final ratio = View.of(context).devicePixelRatio;
    await _show(textureId, _shotSide / ratio);
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final size = '${image.width}×${image.height}';
    image.dispose();
    await _show(null, 0);
    if (bytes == null || size != '$_shotSide×$_shotSide') {
      report.writeln('screen: captured $size, not $_shotSide², not compared');
      return false;
    }
    final seen = fingerprintBytes(bytes.buffer.asUint8List());
    report.writeln('screen bytes ${_hex(seen)} vs GPU ${_hex(written)}: '
        '${seen == written ? 'MATCH' : 'MISMATCH'}');
    return seen == written;
  }

  Future<void> _unregister(List<SharedTexture> textures) async {
    for (final texture in textures) {
      texture.unregister();
    }
    await SchedulerBinding.instance.endOfFrame;
  }

  /// Fill → show → the frame that shows it, [_frames] times, with texture
  /// [textureId] on screen: [fill] fills frame i and returns its
  /// submit-to-done time, [show] hands it to Flutter. One frame more is
  /// shown first, untimed, so the texture is on screen before the clock
  /// starts.
  Future<void> _roundTrip(
    StringBuffer report,
    String label,
    int textureId, {
    required Duration Function(int i) fill,
    required void Function(int i) show,
  }) async {
    fill(-1);
    show(-1);
    await _show(textureId, 512);
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final fills = <int>[];
    final periods = <int>[];
    final shownAt = <int>[];
    for (var i = 0; i < _frames; i++) {
      final start = Timeline.now;
      fills.add(fill(i).inMicroseconds);
      shownAt.add(Timeline.now);
      show(i);
      await SchedulerBinding.instance.endOfFrame;
      periods.add(Timeline.now - start);
    }
    // Timings arrive in batches; give the last one time to land.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    await _show(null, 0);

    final raster = [for (final t in timings) t.rasterDuration.inMicroseconds];
    // The frame that shows a fill is the first whose raster STARTS after
    // it, because Flutter reads the texture while rastering; a raster
    // already running when the fill landed shows the one before.
    // Timeline.now and FrameTiming both read the monotonic clock; the
    // latency is trusted only if every match lands within a second.
    final latencies = <int>[];
    for (final shown in shownAt) {
      for (final t in timings) {
        if (t.timestampInMicroseconds(ui.FramePhase.rasterStart) >= shown) {
          latencies.add(
            t.timestampInMicroseconds(ui.FramePhase.rasterFinish) - shown,
          );
          break;
        }
      }
    }
    final trusted = latencies.length == shownAt.length &&
        latencies.every((us) => us < 1000000);
    report
      ..writeln('[$label] $_frames frames, ${timings.length} timings')
      ..writeln('  fill submit→done   ${_stats(fills)}')
      ..writeln('  fill→frame end     ${_stats(periods)}')
      ..writeln('  raster             ${_stats(raster)}')
      ..writeln(trusted
          ? '  shown→raster done  ${_stats(latencies)}'
          : '  shown→raster done  clocks did not line up '
              '(${latencies.length}/${shownAt.length} matched)');
  }

  @override
  Widget build(BuildContext context) {
    final id = _textureId;
    return MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundary,
          child: SizedBox.square(
            dimension: _textureSide,
            child: id == null
                ? null
                : Texture(textureId: id, filterQuality: FilterQuality.none),
          ),
        ),
      ),
    );
  }
}

String _hex(int value, {int digits = 8}) =>
    value.toUnsigned(digits * 4).toRadixString(16).padLeft(digits, '0');

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

/// The engine's video memory — which Android has no call to read.
String _videoMemory(GpuEngine engine) {
  final bytes = engine.videoMemoryBytes;
  return bytes == 0 ? 'not readable here' : _mib(bytes);
}

/// p50 / p95 / max, in milliseconds.
String _stats(List<int> micros) {
  if (micros.isEmpty) {
    return 'none';
  }
  final sorted = [...micros]..sort();
  String at(double q) =>
      (sorted[((sorted.length - 1) * q).round()] / 1000).toStringAsFixed(2);
  return 'p50 ${at(0.5)} · p95 ${at(0.95)} · max ${at(1)} ms';
}
