import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/fx_plugin_stages.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show applyEffectSteps;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_plugin_that_shifts.dart';

/// 🗣️I-132-Q34 a (유저 2026-10-30): 「어디에 걸어도 돌고, 결과가 올 때까지
/// 그 프레임의 직전 완성 그림에 머문다」 — a plugin past a cel's own pixels
/// runs over the picture its chain made before it, read back from the GPU,
/// where a route can wait for it ([FxPluginStages]); drawn as if off where
/// it cannot.
void main() {
  const width = 6;
  const height = 2;
  const paper = Rect.fromLTWH(0, 0, width + 0.0, height + 0.0);
  const red = [200, 10, 20, 255];
  const clear = [0, 0, 0, 0];

  /// A picture with red at (0, 0) and nothing else.
  ui.Image source() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = const Color.fromARGB(255, 200, 10, 20),
    );
    return recorder.endRecording().toImageSync(width, height);
  }

  ResolvedLayerEffect plugin(ShiftingFxPlugin runner) => ResolvedLayerEffect(
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
    values: const [],
    run: fxPluginRunOf(runner),
  );

  /// [chain] over [source] as the steps a route draws it in, recorded —
  /// the paper lying [on] its pixels, [scale] of them a canvas pixel.
  ui.Picture recorded(
    ui.Image source,
    List<ResolvedLayerEffect> chain, {
    Rect on = paper,
    double scale = 1,
  }) {
    final plan = resolveCompositeEffectPlan(chain, paper: on);
    final image = applyEffectSteps(
      source: source,
      steps: plan.preSteps,
      imageScale: scale,
      paper: on,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(image, Offset.zero, Paint());
    if (!identical(image, source)) {
      image.dispose();
    }
    return recorder.endRecording();
  }

  Future<List<List<int>>> rowOf(ui.Picture picture) async {
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    final bytes = Uint8List.view(data!.buffer);
    return [
      for (var x = 0; x < width; x += 1) bytes.sublist(x * 4, x * 4 + 4),
    ];
  }

  test('is a step of its own in a chain past the head, as far as its plugin '
      'reaches — and none where it has no run on this device', () {
    final runner = ShiftingFxPlugin(by: 2);
    final plan = resolveCompositeEffectPlan([plugin(runner)], paper: paper);
    expect(plan.preSteps.single.lead, isA<PluginEffect>());
    expect(plan.outsetPixels, 2);

    final off = ResolvedLayerEffect(
      kind: EffectKind.plugin,
      plugin: shiftingFxPluginDescription,
      values: const [],
    );
    expect(
      resolveCompositeEffectPlan([off], paper: paper).isSingleDraw,
      isTrue,
    );
  });

  test('a route that waits records again once the plugin has run, and the '
      'step draws what it made', () async {
    final runner = ShiftingFxPlugin(by: 2);
    final picture = source();
    final recordings = <ui.Picture>[];
    final discarded = <ui.Picture>[];
    final made = await FxPluginStages.recordedThrough(
      () {
        final made = recorded(picture, [plugin(runner)]);
        recordings.add(made);
        return made;
      },
      discard: (made) {
        discarded.add(made);
        made.dispose();
      },
    );

    final row = await rowOf(made);
    expect(row[0], clear);
    expect(row[2], red);
    expect(
      recordings,
      hasLength(2),
      reason: 'one round to meet it, one to draw it',
    );
    expect(runner.renders, 1);
    // Handed the picture its chain made, where it lies.
    expect(runner.inputs.single, (left: 0, top: 0, width: width, height: 2));
    expect(discarded, [recordings.first], reason: 'the round it replaced');
    expect(
      picture.debugGetOpenHandleStackTraces(),
      hasLength(1),
      reason: 'what its plugin was handed is let go of once it answers',
    );
    picture.dispose();
  });

  for (final (scale, greens) in [
    (1.0, {3}),
    (2.0, {4, 5}),
  ]) {
    test('handed its picture where it lies on the paper, and each row it '
        'names on the same grid, as the row\'s own cel holds it — $scale of '
        'its pixels a canvas pixel', () async {
      final reading = FxPluginDescription.fromJson({
        ...shiftingFxPluginDescription.toJson(),
        'params': [
          {'id': 'map', 'kind': 'layer', 'label': 'Map'},
        ],
      })!;
      const green = [0, 200, 0, 255];
      const map = LayerId('map');
      final runner = ShiftingFxPlugin(by: 0);
      final effect = ResolvedLayerEffect(
        kind: EffectKind.plugin,
        plugin: reading,
        values: const [0],
        layers: const {'map': map},
        run: fxPluginRunOf(
          runner,
          rows: {
            // A cel green at its (1, 0).
            map: BitmapSurface(
              canvasSize: const CanvasSize(width: 4, height: height),
              tileSize: 4,
              tiles: {
                TileCoord(x: 0, y: 0): BitmapTile(
                  size: 4,
                  pixels: Uint8List(4 * 4 * 4)..setAll(4, green),
                ),
              },
            ),
          },
        ),
      );
      final picture = source();

      // The paper two pixels into the picture: its first pixel lies two
      // left of the paper's.
      final made = await FxPluginStages.recordedThrough(
        () => recorded(
          picture,
          [effect],
          on: const Rect.fromLTWH(2, 0, 4, 2),
          scale: scale,
        ),
        discard: (made) => made.dispose(),
      );
      made.dispose();
      picture.dispose();

      expect(runner.inputs.single, (left: -2, top: 0, width: width, height: 2));
      final row = runner.lastLayers.single;
      expect((row.left, row.top, row.width, row.height), (-2, 0, width, 2));
      bool isGreen(int x) =>
          row.pixels.sublist(x * 4, x * 4 + 4).join(',') == green.join(',');
      expect(
        {
          for (var x = 0; x < width; x += 1)
            if (isGreen(x)) x,
        },
        greens,
        reason: 'the cel\'s (1, 0), where it lies on this grid',
      );
    });
  }

  for (final (what, rows, metAs)
      in [
        (
          'over a picture of another size',
          height * 2,
          (ResolvedLayerEffect effect) => effect,
        ),
        (
          'as another sample',
          height,
          (ResolvedLayerEffect effect) => ResolvedLayerEffect(
            kind: effect.kind,
            plugin: effect.plugin,
            values: effect.values,
            frame: 1,
            run: effect.run,
          ),
        ),
      ]) {
    test('a step met again $what is run again', () async {
      final runner = ShiftingFxPlugin(by: 0);
      final step = plugin(runner);
      final first = source();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      final then = recorder.endRecording().toImageSync(width, rows);
      var recordings = 0;

      final made = await FxPluginStages.recordedThrough(() {
        recordings += 1;
        return recordings == 1
            ? recorded(first, [step])
            : recorded(then, [metAs(step)]);
      }, discard: (made) => made.dispose());
      made.dispose();
      first.dispose();
      then.dispose();

      expect(runner.renders, 2, reason: 'once for each it was met as');
      expect(recordings, 3);
    });
  }

  test('a pixel its plugin leaves clear is clear, whatever colour it gave '
      'it', () async {
    final runner = _LeavesColourInTheClear();
    final picture = source();

    final made = await FxPluginStages.recordedThrough(
      () => recorded(picture, [
        ResolvedLayerEffect(
          kind: EffectKind.plugin,
          plugin: shiftingFxPluginDescription,
          values: const [],
          run: fxPluginRunOf(runner),
        ),
      ]),
      discard: (made) => made.dispose(),
    );
    final image = await made.toImage(width, height);
    final data = await image.toByteData();
    image.dispose();
    made.dispose();
    picture.dispose();

    expect(runner.renders, 1, reason: '⛔premise');
    final premultiplied = Uint8List.view(data!.buffer);
    expect(premultiplied.sublist(4, 8), clear);
    expect(premultiplied.sublist(0, 4), red, reason: '⛔CONTROL: as it was');
  });

  test('a route that cannot wait draws it as if off — and says so', () async {
    final runner = ShiftingFxPlugin(by: 2);
    final picture = source();
    final before = FxPluginStages.unrun;

    final row = await rowOf(recorded(picture, [plugin(runner)]));

    expect(row[0], red);
    expect(row[2], clear);
    expect(runner.renders, 0);
    expect(FxPluginStages.unrun, before + 1);
    picture.dispose();
  });

  test('a plugin over another\'s picture is run a round after it, over what '
      'the first made', () async {
    final first = ShiftingFxPlugin(by: 1);
    final second = ShiftingFxPlugin(by: 2);
    final picture = source();
    var recordings = 0;
    final made = await FxPluginStages.recordedThrough(() {
      recordings += 1;
      return recorded(picture, [plugin(first), plugin(second)]);
    }, discard: (made) => made.dispose());

    final row = await rowOf(made);
    expect(row[3], red);
    expect(row[0], clear);
    expect(recordings, 3);
    expect((first.renders, second.renders), (1, 1));
    // The second was handed the first's picture: red at 1.
    expect(second.lastInput.sublist(4, 8), isNot(clear));
    picture.dispose();
  });

  test('a plugin that fails is drawn as if off, and asked no more', () async {
    final runner = ShiftingFxPlugin(by: 2, fails: true);
    final picture = source();
    var recordings = 0;
    final made = await FxPluginStages.recordedThrough(() {
      recordings += 1;
      return recorded(picture, [plugin(runner)]);
    }, discard: (made) => made.dispose());

    final row = await rowOf(made);
    expect(row[0], red);
    expect(recordings, 2);
    expect(runner.renders, 1);
    picture.dispose();
  });
}

/// Gives back what it is handed, every clear pixel of it given a colour no
/// alpha shows.
final class _LeavesColourInTheClear implements FxPluginRunner {
  int renders = 0;

  @override
  int? reach(Float64List values, FxPluginMoment moment) => 0;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    renders += 1;
    final out = Uint8List.fromList(input.pixels);
    for (var at = 0; at < out.length; at += 4) {
      if (out[at + 3] == 0) {
        out.setRange(at, at + 3, const [90, 90, 90]);
      }
    }
    return out;
  }

  @override
  void close() {}
}
