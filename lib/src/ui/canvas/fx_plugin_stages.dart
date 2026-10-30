import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/rgba_premultiply.dart';
import '../../core/sync_image_upload.dart';
import '../../models/bitmap_surface.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer_effect.dart';
import '../../services/brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import '../../services/cel_plugin_pass.dart'
    show fxPluginRowsOf, fxPluginValuesOf;
import '../../services/cel_text_laying.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「머문다 — 어디에 걸어도 돌고, 결과가
/// 올 때까지 그 프레임의 직전 완성 그림에 머문다」 — a plugin anywhere in a
/// chain runs over the picture the chain made before it, read back from
/// the GPU (`PluginEffect`).
///
/// 🚨THE READ CANNOT BE WAITED FOR WHERE A PICTURE IS RECORDED: recording is
/// synchronous, and the engine's one read is a future (`toByteData` —
/// 🔬on the Surface Pro 11, p50 24 ms at 1280×720, 45 at 1920×1080, 170 at
/// 3840×2160, 2026-10-30). So a recording that meets a plugin's step here
/// leaves the step's input with these stages and goes on as if the step
/// were off; the route that asked for the picture sees it [_missed], waits
/// for the read and the plugin ([_resolve]), and records the same picture
/// again — each step met then draws what its plugin made, in the order the
/// steps were met ([_recording]).
///
/// ⛔ONE STAGE A ROUND. A plugin over another's picture meets its input
/// only once the inner one has run, and nothing here can tell which steps
/// a missed one feeds: so the first step missed in a round is the one run,
/// every later one met again in the next.
///
/// ⛔Only a route that can wait asks through these ([recordedThrough]); any
/// other that meets a plugin's step draws it as if off — so a screen that
/// would show such a frame stands on the picture it showed before.
///
/// 🚨STAGES LIVE FOR ONE RECORDING: [recordedThrough] makes them and lets
/// them go — what they hold is the working set of one picture, and no
/// route holds them to let go of.
final class FxPluginStages {
  FxPluginStages._();

  final List<_Stage> _stages = [];
  int _met = 0;
  bool _missed = false;

  static final Object _zoneKey = Object();

  /// How many plugin steps were drawn as if off for want of their picture
  /// — met where no route waits, or still to be run — since the app began.
  ///
  /// 🚨A PICTURE DRAWN WHILE THIS MOVED IS NO PICTURE TO KEEP: a node's
  /// raster held for the next draw ([HeldSubtreeRasters]) with a step drawn
  /// as if off in it would be cut from by the next round of the very
  /// recording that missed it, which then never meets the step again.
  static int get unrun => _unrun;
  static int _unrun = 0;

  /// [record] recorded with every plugin's step met in it run — recorded
  /// again after each step is ([_resolve]) until none is missed, the
  /// drawing each round made and replaced let go of by [discard]. A
  /// recorded picture holds its own claim on what it draws, so the stages
  /// are let go of as this answers.
  ///
  /// ⚠️At most [_rounds]: a step met anew each round — a sample unequal to
  /// itself — would ask for ever; past them it is drawn as if off.
  static Future<T> recordedThrough<T>(
    T Function() record, {
    required void Function(T made) discard,
  }) async {
    final stages = FxPluginStages._();
    try {
      var made = stages._recording(record);
      for (var round = 0; stages._missed && round < _rounds; round += 1) {
        await stages._resolve();
        discard(made);
        made = stages._recording(record);
      }
      return made;
    } finally {
      stages._dispose();
    }
  }

  static const int _rounds = 16;

  /// [record], each plugin's step met in it drawing what its plugin made
  /// where these stages hold it ([ranOver]).
  T _recording<T>(T Function() record) {
    _met = 0;
    _missed = false;
    return runZoned(record, zoneValues: {_zoneKey: this});
  }

  /// Runs the step the last [_recording] missed first — every step before
  /// it was met again and had run: its input read back, through its
  /// plugin, and the picture it made held for the next.
  Future<void> _resolve() async {
    for (final stage in _stages) {
      if (!stage.ran) {
        await stage.run();
        return;
      }
    }
  }

  void _dispose() {
    for (final stage in _stages) {
      stage.dispose();
    }
    _stages.clear();
  }

  /// [input] — the picture a chain made before [effect], [scale] of its
  /// pixels a canvas pixel, with [paper] where the paper lies in them —
  /// through [effect]'s plugin, a picture the caller owns: what the
  /// recording these stages run met at this step ([_recording]); null where
  /// no recording that can wait is running, or where this step is still to
  /// be run.
  static ui.Image? ranOver(
    ui.Image input,
    ResolvedLayerEffect effect, {
    required double scale,
    required ui.Rect paper,
  }) {
    final stages = Zone.current[_zoneKey];
    if (stages is! FxPluginStages) {
      _unrun += 1;
      return null;
    }
    return stages._take(input, effect, scale: scale, paper: paper);
  }

  ui.Image? _take(
    ui.Image input,
    ResolvedLayerEffect effect, {
    required double scale,
    required ui.Rect paper,
  }) {
    final at = _met++;
    final asked = _Stage(effect, input, scale: scale, paper: paper);
    final there = at < _stages.length ? _stages[at] : null;
    if (there != null && there.ran && there.isAskedAs(asked)) {
      asked.dispose();
      // Null where it failed: drawn as if off, as a plugin that fails is
      // ([FxPluginRunner.render]).
      return there.made?.clone();
    }
    // Not run yet, it takes its input as this round met it: the round
    // before may have drawn a step under it as if off.
    if (there == null) {
      _stages.add(asked);
    } else {
      there.dispose();
      _stages[at] = asked;
    }
    _missed = true;
    _unrun += 1;
    return null;
  }
}

/// A plugin's step as a recording met it: its input, held until it is run.
final class _Stage {
  _Stage(
    this.effect,
    ui.Image input, {
    required this.scale,
    required this.paper,
  }) : _input = input.clone(),
       width = input.width,
       height = input.height;

  final ResolvedLayerEffect effect;
  final double scale;
  final ui.Rect paper;
  final int width;
  final int height;

  ui.Image? _input;

  /// What the plugin made, the step's own until it is let go of.
  ui.Image? made;

  /// Whether it has been run — [made] null after it is a plugin that
  /// failed.
  bool ran = false;

  /// Whether [other] is this step met again: the same sample of the same
  /// effect, over a picture of the same size at the same place.
  bool isAskedAs(_Stage other) =>
      other.effect == effect &&
      other.width == width &&
      other.height == height &&
      other.scale == scale &&
      other.paper == paper;

  Future<void> run() async {
    ran = true;
    final input = _input;
    final run = effect.run;
    if (input == null || run == null) {
      return;
    }
    final data = await input.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null || _input == null) {
      return;
    }
    final pixels = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    made = _ranThrough(run, pixels);
  }

  /// [premultiplied] — this step's input — through [run]'s plugin, as a
  /// picture; null where the plugin fails.
  ui.Image? _ranThrough(FxPluginRun run, Uint8List premultiplied) {
    final canvas = CanvasSize(
      width: (paper.width / scale).round(),
      height: (paper.height / scale).round(),
    );
    final rows = fxPluginRowsOf(effect, run);
    final values = fxPluginValuesOf(effect, paper: canvas, rows: rows);
    final moment = (
      frameIndex: run.moment.frameIndex,
      time: run.moment.time,
      frameRate: run.moment.frameRate,
      scale: scale,
    );
    // Where the picture's first pixel lies from the paper's, in its pixels.
    final left = (-paper.left).round();
    final top = (-paper.top).round();
    FxPluginPicture handed(Uint8List pixels) =>
        (pixels: pixels, width: width, height: height, left: left, top: top);
    final output = run.runner.render(
      input: handed(premultiplied),
      values: values,
      layers: [
        for (final row in rows)
          handed(_rowOnTheGrid(run.rows[row], left: left, top: top)),
      ],
      moment: moment,
    );
    if (output == null) {
      return null;
    }
    zeroFullyClearPixels(output);
    return pictureOf(_PremultipliedRows(output, width, height));
  }

  /// [row]'s own picture on this step's grid — its first pixel at ([left],
  /// [top]) from the paper's, [scale] of them a canvas pixel, each read
  /// from the canvas pixel it lies in — premultiplied; clear where no cel
  /// is.
  Uint8List _rowOnTheGrid(
    BitmapSurface? row, {
    required int left,
    required int top,
  }) {
    final out = Uint8List(width * height * 4);
    if (row == null) {
      return out;
    }
    final region = DirtyRegion(
      left: (left / scale).floor(),
      top: (top / scale).floor(),
      rightExclusive: ((left + width) / scale).ceil(),
      bottomExclusive: ((top + height) / scale).ceil(),
    );
    final straight = bitmapSurfaceRegionPixels(
      celSurfaceWithTextsLaid(row),
      region,
    );
    for (var y = 0; y < height; y += 1) {
      final from = (((top + y) / scale).floor() - region.top) * region.width;
      for (var x = 0; x < width; x += 1) {
        final at = (from + ((left + x) / scale).floor() - region.left) * 4;
        final to = (y * width + x) * 4;
        out.setRange(to, to + 4, straight, at);
      }
    }
    premultiplyRgbaInPlace(out);
    return out;
  }

  void dispose() {
    _input?.dispose();
    _input = null;
    made?.dispose();
    made = null;
  }
}

/// Premultiplied rgba rows held in a list, as the picture door reads them
/// ([pictureOf]).
final class _PremultipliedRows implements PictureBytes {
  _PremultipliedRows(this._premultiplied, this.width, this.height);

  final Uint8List _premultiplied;

  @override
  final int width;

  @override
  final int height;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) =>
      use(straightRgbaFor(_premultiplied));

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(_premultiplied);
}
