import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;

import '../../core/rgba_premultiply.dart';
import '../../core/signed_memo.dart';
import '../../core/sync_image_upload.dart';
import '../../models/bitmap_surface.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer_effect.dart';
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../native/plan_plugins.dart';
import '../../services/brush_stroke_blend.dart' show engineSurfaceRegionPixels;
import '../../services/fx_plugin_values.dart'
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
/// route holds them to let go of. What a step made is KEPT past it where
/// the plan says what its input is made of ([PluginStepSource]) — on that
/// source, the newest only ([_keptSteps]).
final class FxPluginStages implements PluginSteps {
  FxPluginStages._();

  final List<_Stage> _stages = [];
  int _met = 0;
  bool _missed = false;
  int _round = 0;

  /// The stages of the recording running here, if one is.
  static FxPluginStages? get recording {
    final stages = Zone.current[_zoneKey];
    return stages is FxPluginStages ? stages : null;
  }

  /// Whether this round met a step still to be run and another comes after
  /// it: what it draws is no picture.
  bool get aRoundComesAfter => _missed && _round < _rounds;

  static final Object _zoneKey = Object();

  /// What the steps kept past their recordings weigh, made and not yet
  /// collected — the memory census's `pluginSteps`.
  static int get keptBytes => _keptBytes;
  static int _keptBytes = 0;

  /// 🚨★ONE STEP KEPT A SOURCE, the newest (float-warp-resamples-in-the-c-
  /// engine (2) ⓒ, 관제 2026-11-11 「비키는 장치는 필요 없다(수명이 셀 표면에
  /// 묶인다)」): what a plug-in made of a cel's surface — or of what the
  /// plug-in before it made — under the effects run since, as the head of
  /// a chain keeps its plug-in's picture on the surface
  /// (`celPluginSurfaces`). It goes when the source does, or when the same
  /// source is asked under another sample — a value dragged makes a new
  /// one each step. A picture a canvas's size, each ([keptBytes]).
  static final SignedMemo<
    ({_StepAsked step, List<ResolvedLayerEffect> before}),
    _KeptStep
  >
  _keptSteps = SignedMemo(
    'pluginSteps',
    same: (kept, asked) =>
        kept.step == asked.step && listEquals(kept.before, asked.before),
  );

  static final Finalizer<int> _keptGone = Finalizer<int>(
    (bytes) => _keptBytes -= bytes,
  );

  /// [record] recorded with every plugin's step met in it run — recorded
  /// again after each step is ([_resolve]) until none is missed, the
  /// drawing each round made and replaced let go of by [discard]. A
  /// recorded picture holds its own claim on what it draws, so the stages
  /// are let go of as this answers.
  ///
  /// ⚠️At most [_rounds]: a step met anew each round — a sample unequal to
  /// itself — would ask for ever; past them it is drawn as if off.
  ///
  /// A recording that meets kernels still to be compiled
  /// ([FrameKernelsToCome]) is made again, from its first round, once they
  /// are: a route that can wait waits for those as it does for a plugin —
  /// and tells [waitsForKernels] while it does, where one listens.
  ///
  /// [told] hears, once it is recorded, what each of its steps told
  /// ([_told]) — for what keeps the picture to tell again.
  static Future<T> recordedThrough<T>(
    T Function() record, {
    required void Function(T made) discard,
    void Function(bool waits)? waitsForKernels,
    void Function(Map<FxPluginTold, bool> told)? told,
  }) async {
    while (true) {
      try {
        return await _recordedOnce(record, discard, told);
      } on FrameKernelsToCome catch (wait) {
        waitsForKernels?.call(true);
        try {
          await wait.compiled;
        } finally {
          waitsForKernels?.call(false);
        }
      }
    }
  }

  static Future<T> _recordedOnce<T>(
    T Function() record,
    void Function(T made) discard,
    void Function(Map<FxPluginTold, bool> told)? told,
  ) async {
    final stages = FxPluginStages._();
    try {
      var made = stages._recording(record);
      while (stages.aRoundComesAfter) {
        await stages._resolve();
        stages._round += 1;
        discard(made);
        made = stages._recording(record);
      }
      told?.call(stages._told);
      return made;
    } finally {
      stages._dispose();
    }
  }

  static const int _rounds = 16;

  /// What each step the last round met told — its plugin failed or drew,
  /// run or kept ([_Stage.takeKept]): what a picture recorded here tells
  /// again wherever it is shown (`EngineFramePicture.hold`).
  Map<FxPluginTold, bool> get _told => {
    for (final stage in _stages.take(_met))
      if (stage.ran) ?stage.effect.run?.told: stage.output == null,
  };

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
      return null;
    }
    final met = stages._taken(
      effect,
      _ImageInput(input),
      width: input.width,
      height: input.height,
      scale: scale,
      paper: paper,
    );
    // Null where it failed: drawn as if off, as a plugin that fails is
    // ([FxPluginRunner.render]).
    return met?.image?.clone();
  }

  @override
  ({bool ran, Uint8List? straight}) stepOf(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required ui.Rect paper,
    PluginStepSource? from,
  }) {
    final met = _taken(
      effect,
      input,
      width: width,
      height: height,
      scale: 1,
      paper: paper,
      from: from,
    );
    return (ran: met != null, straight: met?.output);
  }

  /// The stage that met this step and has run — run in a recording before
  /// where [from] is what it was run over then ([_keptSteps]); null,
  /// [input] held for the run, where it is still to be.
  _Stage? _taken(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required double scale,
    required ui.Rect paper,
    PluginStepSource? from,
  }) {
    final at = _met++;
    final step = (
      effect: effect,
      width: width,
      height: height,
      scale: scale,
      paper: paper,
    );
    final kept = switch (from) {
      null => null,
      (:final source, :final before) => _keptSteps.resolve(source, (
        step: step,
        before: before,
      ), _KeptStep.new),
    };
    final asked = _Stage(step, input, kept: kept);
    final there = at < _stages.length ? _stages[at] : null;
    if (there != null && there.ran && there.step == step) {
      asked.dispose();
      return there;
    }
    final ranBefore = kept != null && kept.ran;
    if (ranBefore) {
      asked.takeKept();
    }
    // Not run yet, it takes its input as this round met it: the round
    // before may have drawn a step under it as if off.
    if (there == null) {
      _stages.add(asked);
    } else {
      there.dispose();
      _stages[at] = asked;
    }
    if (ranBefore) {
      return asked;
    }
    _missed = true;
    return null;
  }

  /// [bytes] more kept on [step], until it is collected.
  static void _count(_KeptStep step, int bytes) {
    _keptBytes += bytes;
    _keptGone.attach(step, bytes);
  }
}

/// A plugin's step as it is asked for: the same sample of the same effect,
/// over a picture of the same size at the same place, is the same step.
typedef _StepAsked = ({
  ResolvedLayerEffect effect,
  int width,
  int height,
  double scale,
  ui.Rect paper,
});

/// A step kept past its recording ([FxPluginStages._keptSteps]): whether
/// its plugin has run over the source it is kept on, and what it made,
/// straight — null where it failed.
final class _KeptStep {
  bool ran = false;
  Uint8List? output;
}

/// A picture of the walk's as a plugin's step reads it — premultiplied as
/// the picture holds it, straightened for the plugin.
final class _ImageInput implements PluginStepInput {
  _ImageInput(ui.Image image) : _image = image.clone();

  final ui.Image _image;

  @override
  Future<Uint8List?> straight() async {
    final data = await _image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data == null
        ? null
        : straightRgbaFor(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
  }

  @override
  void free() => _image.dispose();
}

/// A plugin's step as a recording met it: its input, held until it is run.
final class _Stage {
  _Stage(this.step, PluginStepInput input, {_KeptStep? kept})
    : _input = input,
      _kept = kept;

  /// The step it is: a recording that meets an equal one meets it again.
  final _StepAsked step;

  ResolvedLayerEffect get effect => step.effect;
  double get scale => step.scale;
  ui.Rect get paper => step.paper;
  int get width => step.width;
  int get height => step.height;

  PluginStepInput? _input;

  /// Where what it makes is kept past its recording, if anywhere.
  final _KeptStep? _kept;

  /// What the plugin made, straight.
  Uint8List? output;

  ui.Image? _image;

  /// [output] as a picture, the step's own until it is let go of.
  ui.Image? get image => _image ??= switch (output) {
    null => null,
    final made => pictureOf(
      PremultipliedRows(premultipliedRgbaCopy(made), width, height),
    ),
  };

  /// Whether it has been run — [output] null after it is a plugin that
  /// failed.
  bool ran = false;

  Future<void> run() async {
    ran = true;
    final input = _input;
    final run = effect.run;
    if (input == null || run == null) {
      return;
    }
    final pixels = await input.straight();
    if (pixels == null || _input == null) {
      return;
    }
    final made = output = _ranThrough(run, pixels);
    if (_kept case final kept? when !kept.ran) {
      kept
        ..ran = true
        ..output = made;
      FxPluginStages._count(kept, made?.length ?? 0);
    }
    run.told?.call(failed: made == null);
  }

  /// This step as it ran in a recording before ([_kept]) — its input let
  /// go of, unread — told again as a step run here is.
  void takeKept() {
    _input?.free();
    _input = null;
    ran = true;
    output = _kept?.output;
    effect.run?.told?.call(failed: output == null);
  }

  /// [straight] — this step's input — through [run]'s plugin, which reads
  /// and draws straight ([FxPluginPicture]); null where the plugin fails.
  Uint8List? _ranThrough(FxPluginRun run, Uint8List straight) {
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
      input: handed(straight),
      values: values,
      layers: [
        for (final row in rows)
          handed(_rowOnTheGrid(run.rows[row], left: left, top: top)),
      ],
      moment: moment,
    );
    // A pixel it leaves clear is clear, whatever colour it gave it — as
    // premultiplying it made it.
    if (output != null) {
      zeroFullyClearPixels(output);
    }
    return output;
  }

  /// [row]'s own picture on this step's grid — its first pixel at ([left],
  /// [top]) from the paper's, [scale] of them a canvas pixel, each read
  /// from the canvas pixel it lies in — straight; clear where no cel is.
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
    final straight = engineSurfaceRegionPixels(
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
    return out;
  }

  void dispose() {
    _input?.free();
    _input = null;
    _image?.dispose();
    _image = null;
    output = null;
  }
}
