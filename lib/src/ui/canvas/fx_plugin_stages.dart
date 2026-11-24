import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;

import '../../core/signed_memo.dart';
import '../../models/canvas_size.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/layer_effect.dart';
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../native/plan_plugins.dart';
import '../../services/fx_plugin_values.dart'
    show fxPluginRowsOf, fxPluginValuesOf;
import '../../services/cel_text_laying.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「머문다 — 어디에 걸어도 돌고, 결과가
/// 올 때까지 그 프레임의 직전 완성 그림에 머문다」 — a plugin anywhere in a
/// chain runs over the picture the chain made before it, where the engine
/// holds it (`PluginEffect`).
///
/// 🚨THE RUN CANNOT BE WAITED FOR WHERE A PICTURE IS RECORDED: recording is
/// synchronous, and a plug-in's run is a worker's wait for the GPU
/// (`GpuFxPlugin.render`) — ↩️its input read back first till 2026-11-15,
/// the engine's one read a future too (`toByteData` — 🔬on the Surface Pro
/// 11, p50 24 ms at 1280×720, 45 at 1920×1080, 170 at 3840×2160,
/// 2026-10-30). So a recording that meets a plugin's step here leaves the
/// step's input with these stages and goes on as if the step were off; the
/// route that asked for the picture sees it [_missed], waits for the
/// plugin ([_resolve]), and records the same picture
/// again — each step met then draws what its plugin made, in the order the
/// steps were met ([_recording]).
///
/// ⛔ONE STAGE A ROUND — AND EVERY STEP FED BY NONE WITH IT. A plugin
/// over another's picture meets its input only once the inner one has
/// run, and nothing here can tell which steps a missed one feeds: so the
/// first step missed in a round is run, and of the later ones only a
/// step whose input the plan says is made of a row's own surface
/// ([PluginStepSource] — no step's picture in it but one that has run)
/// runs with it; every other is met again in the next.
/// ↩️The first alone till 11-17: a plugin worn by several rows ran a
/// round a row, the frame recorded and composited again at each —
/// 🔬main PC, the measuring scene, a plugin on a row others wear: 36
/// of 85 pictures made ahead took 2–7 rounds, 264 composites for the
/// 85, the band filled in 10.6–12.2 s against 6.9–7.5 s with it off
/// (검증/서피스 saw the plug-in row cost +6.5 s of CPU, 11-17).
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

  /// 🚨★ONE STEP KEPT A SOURCE, the newest (float-warp-resamples-in-the-c-
  /// engine (2) ⓒ, 관제 2026-11-11 「비키는 장치는 필요 없다(수명이 셀 표면에
  /// 묶인다)」): what a plug-in made of a cel's surface — or of what the
  /// plug-in before it made — under the effects run since, as the head of
  /// a chain keeps its plug-in's picture on the surface
  /// (`celPluginSurfaces`). It goes when the source does, or when the
  /// pen's frame asks the same source under another sample — a value
  /// dragged makes a new one each step. Its tiles lie in the engine's pool,
  /// counted with every tile landed there (the memory census's
  /// `tileImages`) — ↩️till 2026-11-15 a picture a canvas's size in the
  /// app's memory, a census row of its own (`pluginSteps`).
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
  /// again wherever it is shown (`EngineFramePicture.tellAs`).
  FxPluginRunsTold get _told => {
    for (final stage in _stages.take(_met))
      if (stage.effect case ResolvedLayerEffect(
        :final worn?,
        run: _?,
      ) when stage.ran)
        worn: stage.output == null,
  };

  /// [record], each plugin's step met in it drawing what its plugin made
  /// where these stages hold it ([stepOf]).
  T _recording<T>(T Function() record) {
    _met = 0;
    _missed = false;
    return runZoned(record, zoneValues: {_zoneKey: this});
  }

  /// Runs the step the last [_recording] missed first — every step before
  /// it was met again and had run: its input through its plugin, and the
  /// picture it made held for the next — and every later one it met fed
  /// by none ([_Stage.fedByNone]).
  Future<void> _resolve() async {
    var first = true;
    for (final stage in _stages.take(_met)) {
      if (!stage.ran && (first || stage.fedByNone)) {
        first = false;
        await stage.run();
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
  List<PluginStepRow> rowsOf(ResolvedLayerEffect effect) =>
      switch (effect.run) {
        null => const [],
        final run => [
          for (final row in fxPluginRowsOf(effect, run))
            (
              lineage: row,
              tiles: switch (run.rows[row]) {
                null => const {},
                // The row's own picture, its texts laid as the cel shows
                // them (🗣️I-132-Q32 b 「그 행의 자기 픽셀을 용지 그대로」).
                final surface => celSurfaceWithTextsLaid(surface).tiles,
              },
            ),
        ],
      };

  @override
  ({bool ran, FxPluginTiles? made}) stepOf(
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
    final asked = _Stage(step, input, kept: kept, fedByNone: from != null);
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
  FxPluginTiles? output;
}

/// A plugin's step as a recording met it: its input, held until it is run.
final class _Stage {
  _Stage(
    this.step,
    PluginStepInput input, {
    _KeptStep? kept,
    this.fedByNone = false,
  }) : _input = input,
       _kept = kept;

  /// The step it is: a recording that meets an equal one meets it again.
  final _StepAsked step;

  /// Whether what it reads is made of a row's own surface, as the plan
  /// said ([PluginStepSource]) — no step's picture in it but one that
  /// has run: its input is whole in the round it is met, whatever was
  /// missed before it.
  final bool fedByNone;

  ResolvedLayerEffect get effect => step.effect;
  ui.Rect get paper => step.paper;

  PluginStepInput? _input;

  /// Where what it makes is kept past its recording, if anywhere.
  final _KeptStep? _kept;

  /// What the plugin made, its tiles in the engine's pool: every plan that
  /// puts it names them there.
  FxPluginTiles? output;

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
    final made = output = await _ranThrough(run, input);
    if (_kept case final kept? when !kept.ran) {
      kept
        ..ran = true
        ..output = made;
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

  /// [input] — this step's — through [run]'s plugin, over the rows its
  /// layer values name as the plan kept them with it
  /// ([FxPluginStages.rowsOf]); null where the plugin fails.
  Future<FxPluginTiles?> _ranThrough(FxPluginRun run, FxPluginInput input) {
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
    return run.runner.render(input: input, values: values, moment: moment);
  }

  void dispose() {
    _input?.free();
    _input = null;
    output = null;
  }
}
