import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show debugWaitsHere;
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/brush_tip_entry.dart'
    show brushTipThumbnailSide;
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_tip_image_codec.dart';
import 'package:anicel/src/services/brush_tip_thumbnails.dart';

import '../helpers/poll_until.dart';

/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12): 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」. A tip's picture — its mask read
/// down by the engine's R1 — is asked for ahead of any grid, made once the
/// engine is open and never opening it, and read with no wait for the GPU
/// on the isolate that asks.
void main() {
  test('🚨a picture asked for before the engine is open waits for it, '
      'opening nothing, and lands once it is open', () async {
    final mask = _ramp('asked-early');
    final picture = BrushTipThumbnails.instance.of(mask);
    await pumpEventQueue();
    // Asked for, not open yet: an opening begun is under way off this
    // isolate, and would say nothing here till it is done.
    expect(
      (picture.value, debugAppGpuEngineAskedFor),
      (null, false),
      reason: 'nothing makes it, nor asks for the engine to',
    );

    await openAppGpuEngine();
    await _landed(picture);
    expect(
      picture.value,
      await brushTipThumbnailAlpha(mask, side: brushTipThumbnailSide),
    );
  });

  test('🚨a tip\'s picture is read with no wait for the GPU on the isolate '
      'that asks', () async {
    await openAppGpuEngine();
    // The kernels' compile is not this one's to count.
    await appGpuStampLandingKernels.ready;
    final mask = _ramp('read-off');
    Future<int> waitedHere() async {
      final before = debugWaitsHere;
      await brushTipThumbnailAlpha(mask, side: brushTipThumbnailSide);
      return debugWaitsHere - before;
    }

    expect(await waitedHere(), greaterThan(0), reason: '⛔CONTROL: read here');
    debugWorkersRunHere = false;
    addTearDown(() => debugWorkersRunHere = true);
    expect(await waitedHere(), 0);
  });
}

/// A 64² mask whose coverage ramps left to right.
BrushTipMask _ramp(String id) => BrushTipMask(
  id: id,
  size: 64,
  alpha: Uint8List.fromList([
    for (var y = 0; y < 64; y += 1)
      for (var x = 0; x < 64; x += 1) x * 4,
  ]),
);

/// Once [picture] has landed — [patiently], so a picture that never lands
/// fails rather than hangs.
Future<void> _landed(ValueListenable<Uint8List?> picture) {
  if (picture.value != null) {
    return Future.value();
  }
  final landed = Completer<void>();
  void heard() {
    if (picture.value != null && !landed.isCompleted) {
      landed.complete();
    }
  }

  picture.addListener(heard);
  return patiently(
    landed.future,
  ).whenComplete(() => picture.removeListener(heard));
}
