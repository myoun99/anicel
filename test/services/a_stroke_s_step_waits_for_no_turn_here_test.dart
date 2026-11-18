// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

import '../helpers/poll_until.dart';

/// 🚨A STROKE'S STEP WAITS FOR NO TURN OF THE ENGINE'S THREAD (card
/// a-stroke-step-waits-for-the-engines-turn, 2026-11-18): its dabs piled
/// and what it shows landed are handed to that thread, as a cel number's
/// plate is (a_cel_number_s_plate_waits_for_no_gpu_here_test.dart) —
/// 🔬S5_BA cut 352 under load, the lent-wait probe (k1305): 41 piles of a
/// stroke 31–99 ms all told on this isolate, 57 of the 99 in line behind
/// the band's fill, and its 42 landings 20–34 ms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  final origin = TileCoord(x: 0, y: 0);
  final base = BitmapSurface(canvasSize: canvas, tileSize: side);

  BrushDab dab(double x, double y) => BrushDab(
    sequence: 0,
    pressure: 1,
    center: CanvasPoint(x: x, y: y),
    size: 40,
    hardness: 1,
    opacity: 1,
    flow: 1,
    color: 0xFFC86432,
    tipShape: BrushTipShape.square,
  );

  BrushLiveStrokeRasterizer rasterizer() => BrushLiveStrokeRasterizer(
    pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
    tileSize: side,
  );

  PreBlendedOverlayTile? shown(BrushLiveStrokeRasterizer stroke) => stroke
      .preBlendedOverlayTiles(
        coords: [origin],
        base: base,
        mode: BrushBlendMode.color,
        erase: false,
      )
      .single;

  test('🚨a step piles and shows while the engine\'s thread stands still — '
      'it waits for no turn there', () {
    final dabs = [dab(64, 64), dab(90, 80)];
    // ⛔premise: the stroke's kernels, its pages and the pool's made — the
    // engine's thread's work, which stands still below.
    final stroke = rasterizer()..blendFrom(dabs.sublist(0, 1), from: 0);
    shown(stroke);
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    stroke.blendFrom(dabs, from: 1);
    final tile = shown(stroke);

    expect(
      asked.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'a wait for the engine\'s thread',
    );
    expect(tile, isNotNull, reason: 'LIVENESS: the step is shown');
    stroke.clear();
  });

  // 🔬A blur's rubs were 86–118 ms of a stroke on this isolate, its reaches
  // 3–42 and its landings 24–41 (k1376); a mixing brush's steps 3–54
  // (k1377).
  test('🚨a blur\'s step rubs and shows while the engine\'s thread stands '
      'still — it waits for no turn there', () {
    final dabs = [
      dab(64, 64).copyWith(blurs: true),
      dab(90, 80).copyWith(blurs: true),
    ];
    // ⛔premise: the blur's kernels and its pages made — the engine's
    // thread's work, which stands still below.
    final stroke = rasterizer()
      ..blurOver(base)
      ..blendFrom(dabs.sublist(0, 1), from: 0);
    shown(stroke);
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    stroke.blendFrom(dabs, from: 1);
    final tile = shown(stroke);

    expect(
      asked.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'a wait for the engine\'s thread',
    );
    expect(tile, isNotNull, reason: 'LIVENESS: the step is shown');
    stroke.clear();
  });

  test('🚨a mixing brush\'s step runs and shows while the engine\'s thread '
      'stands still — it waits for no turn there', () {
    BrushDab mixing(double x, double y, int step) => dab(x, y).copyWith(
      mix: BrushDabMix(
        step: step,
        center: CanvasPoint(x: x, y: y),
        radius: 20,
        color: 0xFFC86432,
        refill: 0.12,
        laid: 0.3,
        density: 1,
        take: 0,
        share: 1,
        pick: 0.12,
        dry: false,
      ),
    );
    final dabs = [mixing(64, 64, 0), mixing(90, 80, 1)];
    // ⛔premise: the stroke's kernels, its book and its pages made — the
    // engine's thread's work, which stands still below.
    final stroke = rasterizer()
      ..mixOver(base)
      ..blendFrom(dabs.sublist(0, 1), from: 0);
    shown(stroke);
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    stroke.blendFrom(dabs, from: 1);
    final tile = shown(stroke);

    expect(
      asked.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'a wait for the engine\'s thread',
    );
    expect(tile, isNotNull, reason: 'LIVENESS: the step is shown');
    expect(
      stroke.mixedAsResolved(dabs).map((each) => each.mix),
      everyElement(isNull),
      reason: 'LIVENESS: both steps ran and were read back',
    );
    stroke.clear();
  });

  // ⚠️Last: a device that is gone is gone for its process.
  test('a picture the engine did not put is shown at no revision it carries '
      '— pen-up hands it to no committed tile', () async {
    final stroke = rasterizer()..blendFrom([dab(64, 64)], from: 0);
    final put = shown(stroke)!;
    // Its picture is put behind the stand-still above, and must be before
    // the device goes — as the plate's (11-18, k1335).
    await patiently(appGpuEngine.done());
    expect(
      shown(stroke)!.revision,
      put.revision,
      reason: '⛔premise: a picture put keeps its revision',
    );
    // Gone at once, as wgpu says it of a device it gave up for want of
    // memory: a loss told at the next wait would come after the landing.
    appGpuEngine.debugLose(forMemory: true);

    final unput = shown(stroke)!;

    expect(unput.revision, put.revision, reason: '⛔premise: shown as it was');
    expect(
      await pollUntil(() => shown(stroke)!.revision > unput.revision),
      isTrue,
      reason: 'past the revision of a picture the engine tells it did not put',
    );
    stroke.clear();
  });
}
