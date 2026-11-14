import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:gpu_engine/gpu_engine.dart' show GpuPutPicture;

import '../../core/rgba_premultiply.dart';
import '../../core/signed_memo.dart';
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
/// source, the newest only, and by a plan of the frame a pen is on alone
/// ([_keptSteps]).
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
  /// (`celPluginSurfaces`). It goes when the source does, or when the
  /// pen's frame asks the same source under another sample — a value
  /// dragged makes a new one each step. A picture a canvas's size, each
  /// ([keptBytes]).
  ///
  /// 🚨★THE PLACE IS THE PEN'S FRAME'S (card a-stroke-step-reads-back-and-
  /// pictures-each-tile-it-moved, 관제 2026-11-13 09:05; 🗣️유저 2026-10-27,
  /// Q3 = c: 「편집 중인 프레임의 위 폴더만」 — the frames made ahead give way
  /// to what the canvas holds): a plan of the frame a canvas stands on to
  /// draw alone keeps a step here ([stepOf]). Any other — a frame made
  /// ahead, a render — reads the step kept under the very signature it
  /// asks with, and under another runs its own, kept nowhere and the place
  /// left as it was.
  ///
  /// ↩️Every recording took the place (11-11 → 11-13). A step's sample
  /// holds its frame's moment, so the frame made ahead beside the one drawn
  /// on asked the same cel under another, took the place, and the next
  /// stroke's first write ran every plug-in of the frame again — 🔬main PC,
  /// profile, S5_BA cut 352, three steps at 2436×1524: a stroke's first ink
  /// 26–32 ms after the pen with no plug-in, 552–680 ms with them, at
  /// every stroke.
  ///
  /// ⚠️NOT 「비키는 장치」 COME BACK: that word of 11-11 ⓒ was of MEMORY — a
  /// kept step lives as long as its source and nothing lets it go to make
  /// room. It still does, one a source still: this says only WHOSE the one
  /// is.
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
    void Function(FxPluginRunsTold told)? told,
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
    void Function(FxPluginRunsTold told)? told,
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
  FxPluginRunsTold get _told => {
    for (final stage in _stages.take(_met))
      if (stage.effect.run case final run? when stage.ran)
        ?run.told: (run: run, failed: stage.output == null),
  };

  /// [record], each plugin's step met in it drawing what its plugin made
  /// where these stages hold it ([stepOf]).
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

  @override
  ({bool ran, GpuPutPicture? made}) stepOf(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required ui.Rect paper,
    required bool ofThePensFrame,
    PluginStepSource? from,
  }) {
    final met = _taken(
      effect,
      input,
      width: width,
      height: height,
      paper: paper,
      from: from,
      ofThePensFrame: ofThePensFrame,
    );
    return (ran: met != null, made: met?.output);
  }

  /// The stage that met this step and has run — run in a recording before
  /// where [from] is what it was run over then ([_keptSteps]); null,
  /// [input] held for the run, where it is still to be. What it makes
  /// takes [from]'s place where the plan is [ofThePensFrame].
  _Stage? _taken(
    ResolvedLayerEffect effect,
    PluginStepInput input, {
    required int width,
    required int height,
    required ui.Rect paper,
    PluginStepSource? from,
    bool ofThePensFrame = false,
  }) {
    if (effect.run?.runner.toCome case final toCome?) {
      // Not met while its plug-in's build is still to come: the recording
      // is made again once it is, as for a chain's kernels — with its
      // reach, which is not known till then.
      input.free();
      throw FrameKernelsToCome.forAPlugin(toCome);
    }
    final at = _met++;
    final step = (
      effect: effect,
      width: width,
      height: height,
      paper: paper,
    );
    final kept = switch (from) {
      null => null,
      (:final source, :final before) when ofThePensFrame =>
        _keptSteps.resolve(source, (
          step: step,
          before: before,
        ), _KeptStep.new),
      (:final source, :final before) => _keptSteps.keptUnder(source, (
        step: step,
        before: before,
      )),
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
  ui.Rect paper,
});

/// A step kept past its recording ([FxPluginStages._keptSteps]): whether
/// its plugin has run over the source it is kept on, and what it made,
/// on the engine — null where it failed.
final class _KeptStep {
  bool ran = false;
  GpuPutPicture? output;
}

/// A plugin's step as a recording met it: its input, held until it is run.
final class _Stage {
  _Stage(this.step, PluginStepInput input, {_KeptStep? kept})
    : _input = input,
      _kept = kept;

  /// The step it is: a recording that meets an equal one meets it again.
  final _StepAsked step;

  ResolvedLayerEffect get effect => step.effect;
  ui.Rect get paper => step.paper;
  int get width => step.width;
  int get height => step.height;

  PluginStepInput? _input;

  /// Where what it makes is kept past its recording, if anywhere.
  final _KeptStep? _kept;

  /// What the plugin made, moved to the engine once: every plan that puts
  /// it names it there ([GpuPutPicture]).
  GpuPutPicture? output;

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
    final made = output = switch (await _ranThrough(run, pixels)) {
      null => null,
      final straight => GpuPutPicture(straight),
    };
    if (_kept case final kept? when !kept.ran) {
      kept
        ..ran = true
        ..output = made;
      FxPluginStages._count(kept, made?.straight.length ?? 0);
    }
    run.tell(failed: made == null);
  }

  /// This step as it ran in a recording before ([_kept]) — its input let
  /// go of, unread — told again as a step run here is.
  void takeKept() {
    _input?.free();
    _input = null;
    ran = true;
    output = _kept?.output;
    effect.run?.tell(failed: output == null);
  }

  /// [straight] — this step's input — through [run]'s plugin, which reads
  /// and draws straight ([FxPluginPicture]); null where the plugin fails.
  Future<Uint8List?> _ranThrough(FxPluginRun run, Uint8List straight) async {
    final canvas = CanvasSize(
      width: paper.width.round(),
      height: paper.height.round(),
    );
    final rows = fxPluginRowsOf(effect, run);
    final values = fxPluginValuesOf(effect, paper: canvas, rows: rows);
    final moment = (
      frameIndex: run.moment.frameIndex,
      time: run.moment.time,
      frameRate: run.moment.frameRate,
      // A canvas pixel a pixel: the engine runs a chain in canvas pixels
      // (composite_effect_paint.dart's `_paintPartOf`).
      scale: 1.0,
    );
    // Where the picture's first pixel lies from the paper's, in its pixels.
    final left = (-paper.left).round();
    final top = (-paper.top).round();
    FxPluginPicture handed(Uint8List pixels) =>
        (pixels: pixels, width: width, height: height, left: left, top: top);
    final output = await run.runner.render(
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
  /// [top]) from the paper's, a canvas pixel a pixel — straight; clear where
  /// no cel is.
  Uint8List _rowOnTheGrid(
    BitmapSurface? row, {
    required int left,
    required int top,
  }) => row == null
      ? Uint8List(width * height * 4)
      : engineSurfaceRegionPixels(
          celSurfaceWithTextsLaid(row),
          DirtyRegion(
            left: left,
            top: top,
            rightExclusive: left + width,
            bottomExclusive: top + height,
          ),
        );

  void dispose() {
    _input?.free();
    _input = null;
    output = null;
  }
}
