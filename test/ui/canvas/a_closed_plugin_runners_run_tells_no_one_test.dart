import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/a_row_laid_on_the_engine.dart';

/// 🚨★A CLOSED RUNNER'S RUN TELLS NOBODY (card a-closed-plugin-runners-run-
/// tells-no-one, 관제 2026-11-13): a build the list of plug-ins let go —
/// with the app's engine, replaced, taken off, the choice to cut changed —
/// whose run ends after told its effect it failed, and the header showed
/// ⚠ till the frame was made again on the next build. Every route tells
/// through the run (`FxPluginRun.tell`): a step run or kept, here; a
/// picture shown again (`a_frame_that_waits_for_its_plugins_holds_its_
/// picture_test`); a reach the plugin failed to say, here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 128;
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  /// A cel of one tile, a pixel of ink at its corner.
  BitmapSurface aCel() => BitmapSurface(
    canvasSize: const CanvasSize(width: side, height: side),
    tileSize: side,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: side,
        pixels: Uint8List(side * side * 4)
          ..setAll(0, const [200, 10, 20, 255]),
      ),
    },
  );

  /// [runner]'s effect, its run telling [tells] how it went.
  ResolvedLayerEffect through(FxPluginRunner runner, List<bool> tells) =>
      ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: shiftingFxPluginDescription,
        values: const [],
        run: fxPluginRunOf(
          runner,
          told: ({required failed}) => tells.add(failed),
        ),
      );

  for (final fails in [true, false]) {
    final went = fails ? 'failed' : 'drew';
    test('a run that ends after its runner is closed tells nobody it $went '
        '— one that ends with its runner open does', () async {
      final tells = <bool>[];
      await aRowLaidOnTheEngine(composite, letters, aCel(), [
        through(_ClosedOnItsWay(fails: fails, closes: false), tells),
      ]);
      expect(tells, [fails], reason: '⛔premise: an open runner\'s run tells');

      tells.clear();
      final closing = _ClosedOnItsWay(fails: fails, closes: true);
      await aRowLaidOnTheEngine(composite, letters, aCel(), [
        through(closing, tells),
      ]);

      expect(closing.renders, 1, reason: 'LIVENESS: it ran');
      expect(tells, isEmpty);
    });
  }

  test('a step kept on its cel, its runner closed since, tells nobody as '
      'it is laid again', () async {
    final cel = aCel();
    final runner = ShiftingFxPlugin(by: 0, fails: true);
    final tells = <bool>[];
    final effects = [through(runner, tells)];
    await aRowLaidOnTheEngine(composite, letters, cel, effects);
    await aRowLaidOnTheEngine(composite, letters, cel, effects);
    expect(runner.renders, 1, reason: '⛔premise: kept, not run again');
    expect(tells, [true, true], reason: '⛔premise: kept, told again');

    runner.close();
    await aRowLaidOnTheEngine(composite, letters, cel, effects);

    expect(runner.renders, 1, reason: 'LIVENESS: kept, not run');
    expect(tells, [true, true]);
  });

  test('a reach a closed runner fails to say tells nobody', () async {
    final tells = <bool>[];
    await aRowLaidOnTheEngine(composite, letters, aCel(), [
      through(ShiftingFxPlugin(reachFails: true), tells),
    ]);
    expect(tells, isNotEmpty, reason: '⛔premise: an open runner\'s tells');
    expect(tells, everyElement(isTrue));

    tells.clear();
    await aRowLaidOnTheEngine(composite, letters, aCel(), [
      through(ShiftingFxPlugin(reachFails: true)..close(), tells),
    ]);

    expect(tells, isEmpty);
  });
}

/// Hands its input back — or nothing, [fails] — and, [closes], is closed
/// while its run is on its way: as the list of plug-ins lets a build go
/// under a run on a worker.
final class _ClosedOnItsWay implements FxPluginRunner {
  _ClosedOnItsWay({required this.fails, required this.closes});

  final bool fails;
  final bool closes;
  int renders = 0;

  @override
  bool closed = false;

  @override
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) => 0;

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) async {
    renders += 1;
    await null;
    if (closes) {
      close();
    }
    return fails ? null : Uint8List.fromList(input.pixels);
  }

  @override
  void close() => closed = true;
}
