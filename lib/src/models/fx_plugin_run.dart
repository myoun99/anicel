import 'dart:typed_data';

import '../core/frozen_collections.dart';
import 'bitmap_surface.dart';
import 'bitmap_tile.dart';
import 'layer_id.dart';
import 'tile_coord.dart';

/// What a plug-in's step runs over, where the engine holds it: the picture
/// a chain had come to at the step — [picture], its first pixel from the
/// paper's and its size, a canvas pixel a pixel — and the rows its layer
/// parameters name, by slot ([FxPluginRun.rows]), each as its cel holds
/// it over the chain's tiles.
///
/// Straight, as the engine's pool holds a pixel and a GPU plugin reads one
/// (fx spec 2, an-endless-plugin-stalls-the-app 19:27): ↩️spec 1's host
/// took them premultiplied, so a cel's straight pixels were premultiplied
/// on the way in and undone on the way out — a rounding each way, which at
/// a low alpha would have told the seam's picture from the engine chain's.
///
/// ↩️Till 2026-11-15 its pixels were read back to the CPU for the plug-in,
/// each row's read there too, and what the plug-in made came back as bytes
/// to be moved to the engine again (a-plugin-step-goes-through-the-cpu-and-
/// back): its pixels stay where they lie (`EngineFxPluginInput`).
abstract interface class FxPluginInput {
  /// Its first pixel from the paper's, and its size, in its pixels.
  ({int left, int top, int width, int height}) get picture;

  /// Where the paper's first pixel lies on the canvas's tile grid: a pixel
  /// of [picture] at (x, y) lies at (x + dx, y + dy) on the tiles.
  (int, int) get paperOnTheGrid;
}

/// What a plug-in made of its step's input: tiles of the canvas's grid
/// where the input lies, clear past what it drew.
typedef FxPluginTiles = Map<TileCoord, BitmapTile>;

/// When a plugin is asked: the frame's index from the cut's first, its
/// time in seconds, the frames a second, and the output pixels a canvas
/// pixel is drawn at (below 1 in a draft).
typedef FxPluginMoment = ({
  int frameIndex,
  double time,
  double frameRate,
  double scale,
});

/// What a plugin's effect is run through (fx spec 2): how far it reaches,
/// and the picture it makes — the engine's device for a plugin this device
/// has opened (`GpuFxPlugin`).
abstract interface class FxPluginRunner {
  /// The open of its build under way off the isolate that asks — null once
  /// it is open, or would not open. Its reach and its picture are not
  /// asked meanwhile: a step of it is not run till then, as a chain whose
  /// kernels are still to be compiled is not (`FrameKernelsToCome`), and
  /// how far it reaches is not known (`resolveCompositeEffectPlan`).
  Future<void>? get toCome;

  /// Whether its picture may be another at another frame of the same
  /// values — its plugin reads the moment's frame or time (fx_wgsl's
  /// `Kernel::reads_the_moment`). A run of one that does not is signed
  /// alike at every frame ([FxPluginRun.==]).
  bool get readsTheMoment;

  /// How far past its input the effect reaches for [values] (four doubles
  /// a parameter, anicel_fx_value) at [moment], in output pixels — or null
  /// where the plugin failed to say.
  int? reach(Float64List values, FxPluginMoment moment);

  /// [input] as the effect draws it, over the rows its layer parameters
  /// name in the places [values] give them — or null where the plugin
  /// failed (the row is then drawn as if the effect were off). A future: a
  /// device's run is a worker's wait for the GPU, not the asker's
  /// (`GpuFxPlugin.render`).
  Future<FxPluginTiles?> render({
    required FxPluginInput input,
    required Float64List values,
    required FxPluginMoment moment,
  });

  /// Lets the build go; asked after, it answers nothing — null, the effect
  /// off — as a picture still holding it may ask.
  void close();

  /// Whether it has been let go ([close]) — a run of it on its way then
  /// still to end: what a run of it comes to from here tells nobody
  /// ([FxPluginRun.tell]).
  bool get closed;
}

/// Who hears how a plugin's run went — failed or drew ([FxPluginRun.told]).
typedef FxPluginTold = void Function({required bool failed});

/// What the runs a picture's plug-in steps were told — the last run of each
/// teller, and whether it failed — kept to be told again, by that run
/// ([FxPluginRun.tell]), each time the picture is shown
/// (`EngineFramePicture.hold`).
typedef FxPluginRunsTold = Map<FxPluginTold, ({FxPluginRun run, bool failed})>;

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
    this.told,
  }) : rows = frozenMap(rows),
       _signedMoment = runner.readsTheMoment
           ? moment
           : (frameRate: moment.frameRate, scale: moment.scale);

  final FxPluginRunner runner;
  final FxPluginMoment moment;

  /// 🚨WHAT OF [moment] A RUN IS SIGNED WITH IS WHAT ITS PLUGIN READS (card
  /// a-plugin-step-is-keyed-by-a-moment-it-may-not-read, 브러시/렌더링
  /// 2026-11-13, a card of its own after the round — 관제 09:05): all of
  /// it where the plugin reads the frame or the time
  /// ([FxPluginRunner.readsTheMoment]), else the rate and the scale alone,
  /// alike at every frame of a cut. So the step a canvas keeps at the
  /// pen's frame is the step of every frame its cel stands at with those
  /// values (`FxPluginStages`), and a frame made ahead reads it rather
  /// than run its own. Asked of the runner as the run is made — a build
  /// still to come signs with all of it ([FxPluginRunner.toCome]) — so
  /// what a run is equal to never changes under a key that holds it.
  /// ↩️Signed with the moment whatever the plugin read, a frame made
  /// ahead ran every plug-in of its frame again: 🔬main PC, profile,
  /// S5_BA cut 352, three steps — about 0.4 s a frame; the Surface Pro 11
  /// came quiet after a file opened at 40–42 s with the plug-in row on,
  /// 20 s with it off (검증/서피스, 11-13).
  final Object _signedMoment;

  /// The rows the effect's layer parameters name that are in its cut.
  final Map<LayerId, BitmapSurface?> rows;

  /// Where every route that runs this tells how it went — failed or drew —
  /// each time it shows the picture, kept or made: the device's record
  /// its fx row's header reads (`FxPluginOutcomes`). Null tells nobody.
  /// ⛔Told through [tell] alone.
  ///
  /// 🚨A picture nobody is shown tells nothing — card
  /// a-cached-failed-picture-loses-its-mark (2026-11-08): the redo's cel,
  /// made ahead after an undo, had told last that it drew. ↩️The history's
  /// read-ahead (`ShownCels.warm`) and the cel as it stood beside a live
  /// stroke ran a cel's head plugin telling nobody (`effectsTellingNobody`)
  /// while that plugin ran on the cel; they run none since it is a step of
  /// the chain the engine runs over what is shown
  /// (float-warp-resamples-in-the-c-engine (2), 2026-11-11).
  final FxPluginTold? told;

  /// Tells [told] how this run went — [failed], or drew — where its runner
  /// is still open: every route that shows a plug-in's picture tells it
  /// here — a step run or kept (`FxPluginStages`), a picture shown again
  /// (`EngineFramePicture.hold`), a reach the plugin failed to say
  /// (`resolveCompositeEffectPlan`).
  ///
  /// 🚨★A CLOSED RUNNER'S RUN TELLS NOBODY (card a-closed-plugin-runners-
  /// run-tells-no-one, 관제 2026-11-13 10:38): a list of plug-ins lets a
  /// build go as the app lets its engine go — its device lost —, as one is
  /// replaced or taken off, and as the choice to cut its runs changes; a run
  /// on its way then ends after, failed, and its effect's header showed ⚠
  /// till the frame was made again on the next build (⛔없다가 생기는 UI).
  /// ⛔NOT STOPPED IN THE RECORD (`FxPluginOutcomes.forget`): a plug-in that
  /// would not open is one const runner, the same before it is let go and
  /// after, so a record deaf to the old one is deaf to the next — and its
  /// ⚠ never shows (브러시 10:37). The runner says it is closed; one that
  /// never opened is never closed, and fails as it did.
  void tell({required bool failed}) {
    if (!runner.closed) {
      told?.call(failed: failed);
    }
  }

  /// ⛔A row's picture is the SAME OBJECT, not an equal one: a picture is
  /// immutable, so an edited row is another object — and a deep compare of
  /// every tile per frame is what the identity is there to spare.
  /// ⛔[told] is not compared: it is who hears the outcome, not what the
  /// plugin runs with — two runs equal in that make one picture and fail
  /// alike, so a picture kept from either is told to the one that asks.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FxPluginRun &&
          identical(other.runner, runner) &&
          other._signedMoment == _signedMoment &&
          other.rows.length == rows.length &&
          rows.entries.every(
            (row) =>
                other.rows.containsKey(row.key) &&
                identical(other.rows[row.key], row.value),
          );

  @override
  int get hashCode => Object.hash(
    identityHashCode(runner),
    _signedMoment,
    Object.hashAllUnordered([
      for (final row in rows.entries)
        Object.hash(row.key, identityHashCode(row.value)),
    ]),
  );
}
