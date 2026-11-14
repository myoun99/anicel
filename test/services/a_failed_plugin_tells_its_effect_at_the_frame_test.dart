@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/string_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/services/fx_plugins/device_fx_plugin_binding.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_outcomes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/a_row_laid_on_the_engine.dart';

/// 🗣️a-failed-plugin-shows-the-cel-silently-Q1 (유저 2026-11-08): 「원래 셀
/// + 머리를 회색으로, 이름 뒤 ⚠ 칸은 늘 잡아 둔다」 — a plugin that cannot
/// draw a cel leaves the cel as it is, and its effect is told it failed at
/// that frame, which its fx row's header reads.
///
/// The plugin is a stand-in that fails once a picture is past 200 pixels
/// across, as one a picture outgrows does: what a run the GPU cuts comes
/// to is `a_gpu_plugin_opens_and_runs_on_the_engine_test`'s.
///
/// A cel is shown here as a route that waits for its plug-ins lays it on
/// the engine, its chain's steps run (`aRowLaidOnTheEngine`) — where a
/// plug-in is run, at the head of a cel's chain as anywhere in it.
/// ↩️It was the CPU's seam (`celSurfaceAsShown`) while a plugin at the head
/// ran there (float-warp-resamples-in-the-c-engine (2), 2026-11-11).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  /// A cel [side] across, a pixel of ink a tile of the engine's along its
  /// top — so what a plug-in is handed of it spans it.
  BitmapSurface inked(int side) => BitmapSurface(
    canvasSize: CanvasSize(width: side, height: side),
    pasteboardReach: PasteboardReach.none,
    tileSize: 128,
    tiles: {
      for (var x = 0; x * 128 < side; x += 1)
        TileCoord(x: x, y: 0): BitmapTile(
          size: 128,
          pixels: Uint8List(128 * 128 * 4)
            ..setAll(0, const [200, 10, 20, 255]),
        ),
    },
  );

  test('a plugin that cannot draw tells its effect so at that frame, each '
      'time the cel is shown — and one that draws clears it', () async {
    final outgrown = _FailsPast(200);
    final effect = LayerEffect.defaults(
      id: const EffectId('fx'),
      kind: EffectKind.plugin,
      plugin: shiftingFxPluginDescription,
    );
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final binding = deviceFxPluginBinding(
      runnerFor: (_) => outgrown,
      frameRate: ProjectFrameRate.fps24,
      surfaceOf: (_, _) => null,
      outcomes: outcomes,
    );
    final row = Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: LayerKind.animation,
      frames: const [],
      effects: [effect],
    );
    final place = (owner: row.id, effect: effect.id);
    Future<void> shown(BitmapSurface cel, int frame) =>
        aRowLaidOnTheEngine(
          composite,
          letters,
          cel,
          binding(
            resolveLayerEffectsAt(
              effects: [effect],
              frameIndex: frame,
              blocks: null,
              worn: (owner: row.id, wearer: row.id),
            ),
            cut: Cut(
              id: const CutId('c'),
              name: 'c',
              duration: 8,
              canvasSize: cel.canvasSize,
              layers: [row],
            ),
            frameIndex: frame,
          ),
        );
    final big = inked(512);
    final small = inked(8);

    await shown(big, 3);
    expect(outcomes.failedAt(place, 3), isTrue);
    expect(outcomes.failedAt(place, 4), isFalse,
        reason: 'the frame it failed at, and no other');

    await shown(small, 3);
    expect(outcomes.failedAt(place, 3), isFalse,
        reason: 'drawn at that frame, the mark goes');

    await shown(big, 3);
    expect(outcomes.failedAt(place, 3), isTrue,
        reason: 'a picture kept from before is told as a made one is');
  });

  testWidgets('an installed plugin that will not open fails as a run does — '
      'told, not drawn as if off with nothing to say — and is let go of '
      'with the plugin', (tester) async {
    final plugins = await installedShiftingFxPlugin(tester, opens: false);
    final runner = plugins.runnerFor(shiftingFxPluginDescription);
    expect(runner, isNotNull);
    expect(
      identical(plugins.runnerFor(shiftingFxPluginDescription), runner),
      isTrue,
      reason: 'kept, not opened again each frame',
    );
    final effect = shiftingFxPluginLayerEffect();
    final binding = deviceFxPluginBinding(
      runnerFor: plugins.runnerFor,
      frameRate: ProjectFrameRate.fps24,
      surfaceOf: (_, _) => null,
      outcomes: plugins.outcomes,
    );
    const paper = CanvasSize(width: 8, height: 8);
    final cel = inked(8);
    final row = Layer(
      id: const LayerId('a'),
      name: 'a',
      kind: LayerKind.animation,
      frames: const [],
      effects: [effect],
    );
    Future<void> shown() async => tester.runAsync(
      () => aRowLaidOnTheEngine(
        composite,
        letters,
        cel,
        binding(
          resolveLayerEffectsAt(
            effects: [effect],
            frameIndex: 2,
            blocks: null,
            worn: (owner: row.id, wearer: row.id),
          ),
          cut: Cut(
            id: const CutId('c'),
            name: 'c',
            duration: 4,
            canvasSize: paper,
            layers: [row],
          ),
          frameIndex: 2,
        ),
      ),
    );
    await shown();
    final place = (owner: row.id, effect: effect.id);

    expect(plugins.outcomes.failedAt(place, 2), isTrue);

    // 🚨Its build let go — here as the choice to cut changes — it fails as
    // it did: one that never opened is never closed (card a-closed-plugin-
    // runners-run-tells-no-one; `FxPluginRun.tell`).
    addTearDown(AppGpu.debugReset);
    AppGpu.settings.value = const AppGpuSettings(
      pluginShare: FxPluginShare.uncut,
    );
    expect(plugins.outcomes.failedAt(place, 2), isFalse,
        reason: '⛔premise: let go, what it told forgotten');
    expect(
      identical(plugins.runnerFor(shiftingFxPluginDescription), runner),
      isTrue,
      reason: '⛔premise: the one it was before',
    );
    await shown();
    expect(plugins.outcomes.failedAt(place, 2), isTrue);

    var heard = 0;
    plugins.outcomes.addListener(() => heard += 1);
    await tester.runAsync(
      () => plugins.uninstall(shiftingFxPluginDescription.id),
    );
    expect(plugins.outcomes.failedAt(place, 2), isFalse,
        reason: 'taken off, its build tells nothing of the next');
    expect(heard, 1);
  });

  const a = LayerId('a');
  const fx = EffectId('fx');
  const place = (owner: a, effect: fx);
  const cut = CutId('c');
  ResolvedLayerEffect sample(double value) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: [value],
    frame: 1,
  );

  test('a run is heard once the picture is made, once for the tells before '
      'it, and only where the outcome changed', () async {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final ran = sample(0);
    void tell(int frame, {required bool failed}) => outcomes.toldFor(
      (owner: a, effect: fx, wearer: a),
      ran,
      cut: cut,
      frame: frame,
    )(failed: failed);
    var heard = 0;
    outcomes.addListener(() => heard += 1);

    tell(1, failed: true);
    tell(2, failed: true);
    tell(1, failed: true);
    expect(heard, 0, reason: 'not while the picture is being made');
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1);

    tell(2, failed: true);
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1, reason: 'no change, nothing to hear');

    tell(2, failed: false);
    await Future<void>.delayed(Duration.zero);
    expect(heard, 2);
    expect(outcomes.failedAt(place, 2), isFalse);
    expect(outcomes.failedAt(place, 1), isTrue);
  });

  test('a run bound where its sample ran before is told at once how it went '
      'there — a picture served from a cache runs nothing to tell it', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    const worn = (owner: a, effect: fx, wearer: a);
    final failing = sample(1);
    final drawing = sample(2);

    outcomes.toldFor(worn, failing, cut: cut, frame: 1)(failed: true);
    outcomes.toldFor(worn, drawing, cut: cut, frame: 1)(failed: false);
    expect(outcomes.failedAt(place, 1), isFalse);

    outcomes.toldFor(worn, failing, cut: cut, frame: 1);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the value it failed at given back, as an undo gives it');

    outcomes.toldFor(worn, sample(3), cut: cut, frame: 1);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'a sample never run there says nothing until it runs');

    outcomes.toldFor(worn, failing, cut: cut, frame: 2);
    expect(outcomes.failedAt(place, 2), isFalse,
        reason: 'recalled at the frame it ran at, and no other');
    outcomes.toldFor(worn, drawing, cut: cut, frame: 1);
    expect(outcomes.failedAt(place, 1), isFalse);
    outcomes.toldFor(
      (owner: a, effect: fx, wearer: const LayerId('b')),
      failing,
      cut: cut,
      frame: 1,
    );
    expect(outcomes.failedAt(place, 1), isFalse,
        reason: 'recalled for the row it ran over, and no other');
  });

  test('a run walks back through the samples an undo is likely to, and lets '
      'go of the oldest past them', () {
    const worn = (owner: a, effect: fx, wearer: a);
    bool recalledAfter(int others) {
      final outcomes = FxPluginOutcomes();
      addTearDown(outcomes.dispose);
      final oldest = sample(-1);
      outcomes.toldFor(worn, oldest, cut: cut, frame: 1)(failed: true);
      for (var value = 0; value < others; value++) {
        outcomes.toldFor(worn, sample(value.toDouble()), cut: cut, frame: 1)(
          failed: false,
        );
      }
      outcomes.toldFor(worn, oldest, cut: cut, frame: 1);
      return outcomes.failedAt(place, 1);
    }

    expect(recalledAfter(15), isTrue, reason: 'sixteen back, it is kept');
    expect(recalledAfter(16), isFalse, reason: 'seventeen back, it is not');
  });

  test('a sample bound again, worn alike at the same frame, is told by the '
      'teller it was before — a picture that tells again what its steps '
      'told keeps one of each, however often its chain is bound', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    const worn = (owner: a, effect: fx, wearer: a);
    final once = outcomes.toldFor(worn, sample(1), cut: cut, frame: 1);

    expect(
      identical(outcomes.toldFor(worn, sample(1), cut: cut, frame: 1), once),
      isTrue,
    );
    expect(
      [
        outcomes.toldFor(worn, sample(2), cut: cut, frame: 1),
        outcomes.toldFor(worn, sample(1), cut: cut, frame: 2),
        outcomes.toldFor(
          (owner: a, effect: fx, wearer: const LayerId('b')),
          sample(1),
          cut: cut,
          frame: 1,
        ),
      ].any((other) => identical(other, once)),
      isFalse,
      reason: 'another sample, frame or wearer is told by another',
    );
  });

  test('an effect fails where any row that wears it fails — an attach row '
      'runs its base\'s chain over its own picture, a copied row keeps its '
      'chain\'s effects', () {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    final ran = sample(0);
    void Function({required bool failed}) wornBy(StringId row, CutId cut) =>
        outcomes.toldFor(
          (owner: a, effect: fx, wearer: row),
          ran,
          cut: cut,
          frame: 1,
        );
    const attach = LayerId('attach');

    wornBy(a, cut)(failed: false);
    wornBy(attach, cut)(failed: true);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the base draws, the attach row does not');
    wornBy(a, cut)(failed: false);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the base drawing again leaves the attach row\'s mark');
    wornBy(attach, cut)(failed: false);
    expect(outcomes.failedAt(place, 1), isFalse);

    wornBy(a, const CutId('other'))(failed: true);
    wornBy(a, cut)(failed: false);
    expect(outcomes.failedAt(place, 1), isTrue,
        reason: 'the same row of another cut is another wearer');

    expect(outcomes.failedAt((owner: attach, effect: fx), 1), isFalse,
        reason: 'the attach row\'s header is of its own chain');
    expect(
      outcomes.failedAt((owner: a, effect: const EffectId('other')), 1),
      isFalse,
    );
  });

  test('forgetting a plugin lets go of its runs alone, and is heard where a '
      'mark goes', () async {
    final outcomes = FxPluginOutcomes();
    addTearDown(outcomes.dispose);
    const other = EffectId('other');
    final otherPlugin = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: FxPluginDescription.fromJson({
        ...shiftingFxPluginDescription.toJson(),
        'id': 'test.other',
      }),
      values: const [],
      frame: 1,
    );
    const worn = (owner: a, effect: fx, wearer: a);
    outcomes.toldFor(worn, sample(0), cut: cut, frame: 1)(failed: true);
    outcomes.toldFor(
      (owner: a, effect: other, wearer: a),
      otherPlugin,
      cut: cut,
      frame: 1,
    )(failed: true);
    await Future<void>.delayed(Duration.zero);
    var heard = 0;
    outcomes.addListener(() => heard += 1);

    outcomes.forget('test.other');
    await Future<void>.delayed(Duration.zero);
    expect(outcomes.failedAt((owner: a, effect: other), 1), isFalse);
    expect(outcomes.failedAt(place, 1), isTrue);
    expect(heard, 1);

    outcomes.forget('test.nobody');
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1, reason: 'no mark gone, nothing to hear');
  });
}

/// Fails on a picture past [most] pixels across; draws as a
/// [ShiftingFxPlugin] by one otherwise.
final class _FailsPast implements FxPluginRunner {
  _FailsPast(this.most);

  final int most;
  final ShiftingFxPlugin _drawing = ShiftingFxPlugin(by: 1);

  @override
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      _drawing.reach(values, moment);

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) async => input.width > most
      ? null
      : await _drawing.render(
          input: input,
          values: values,
          layers: layers,
          moment: moment,
        );

  @override
  void close() {}

  @override
  bool get closed => false;
}
