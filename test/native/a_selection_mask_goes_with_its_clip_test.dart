@Tags(['gc'])
// The first mask compiles the selection's kernels: 40 s on a machine this
// busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuMask;

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show SelectionMaskOptions;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/selection_clip.dart';

import '../helpers/collect_garbage.dart';

/// A selection's mask on the engine is kept by the clip that asked for it
/// and goes with it (2026-11-14): nothing frees it, the collector finds the
/// clip and the mask's finalizer gives its bytes back. One freed by hand
/// gives them back then, and not a second time when it is collected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a clip let go of takes its mask with it', () async {
    final held = GpuMask.liveBytes;
    // In a call of its own: a mask is Finalizable, and one named here
    // would be kept alive to the end of this function.
    void askAndDrop() {
      final clip = SelectionClip.of(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 60, top: 20, right: 240, bottom: 180),
        ),
        wall: const CanvasSize(
          width: 300,
          height: 200,
        ).pasteboardAt(PasteboardReach.none),
        options: const SelectionMaskOptions(featherPx: 4),
      );
      expect(identical(clip.maskOnEngine(), clip.maskOnEngine()), isTrue);
    }

    askAndDrop();
    expect(GpuMask.liveBytes, greaterThan(held), reason: 'fixture premise');

    await collectGarbageUntil(() => GpuMask.liveBytes == held);
    expect(GpuMask.liveBytes, held);
  });

  test('a mask freed by hand gives its bytes back once', () async {
    final held = GpuMask.liveBytes;
    void makeFreeAndDrop() {
      GpuMask(
        appGpuComposite,
        Uint8List(64 * 32)..fillRange(0, 64 * 32, 255),
        x: 0,
        y: 0,
        width: 64,
        height: 32,
      ).free();
      expect(GpuMask.liveBytes, held);
    }

    makeFreeAndDrop();
    await collectGarbage();
    await collectGarbage();
    expect(GpuMask.liveBytes, held);
  });
}
