import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/brush_tip_entry.dart' show brushTipThumbnailSide;
import '../models/brush_tip_mask.dart';
import '../native/app_gpu_engine.dart' show appGpuEngineOpen;
import 'brush_tip_image_codec.dart' show brushTipThumbnailAlpha;

/// Each tip mask's picture as the grids draw it — [brushTipThumbnailSide]²
/// cells, a byte each ([brushTipThumbnailAlpha]) — made on the engine once a
/// mask, and told of as it lands.
///
/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12): 「미리 만들어 둔다 —
/// 엔진이 열리면 기다리지 않고 받아 둔다」: what the libraries hold is asked
/// for as they are read ([want]), made one after another once the engine is
/// open, the isolate that asks never waiting. A grid that asks before then
/// has its cell, empty, till its picture lands — the cost that answer took.
/// ↩️Every grid averaged the whole mask into its cells as it painted (a box
/// of its own, beside the one resampler), and every launch made a
/// thumbnail of each built-in tip that no grid drew.
///
/// ⛔NOTHING HERE OPENS THE ENGINE. The app opens it after its first frame
/// ([appGpuEngineOpen]); what is asked before waits for it.
final class BrushTipThumbnails {
  BrushTipThumbnails._() {
    appGpuEngineOpen.addListener(() => unawaited(_makeWhatIsAsked()));
  }

  /// The app's.
  static final BrushTipThumbnails instance = BrushTipThumbnails._();

  final Expando<ValueNotifier<Uint8List?>> _of = Expando();

  /// What is asked for and not made yet, first asked first — held weakly:
  /// a mask nothing holds any more is no picture anyone will draw.
  final List<WeakReference<BrushTipMask>> _asked = [];
  bool _making = false;

  /// [mask]'s picture: null till it lands. Asks for it.
  ValueListenable<Uint8List?> of(BrushTipMask mask) {
    final known = _of[mask];
    if (known != null) {
      return known;
    }
    final asked = _of[mask] = ValueNotifier(null);
    _asked.add(WeakReference(mask));
    unawaited(_makeWhatIsAsked());
    return asked;
  }

  /// Asks for [masks]' pictures ahead of any grid ([of]).
  void want(Iterable<BrushTipMask> masks) {
    for (final mask in masks) {
      of(mask);
    }
  }

  /// Test seam: how a mask's picture is made, in place of the engine's —
  /// in the test's own time.
  @visibleForTesting
  static Future<Uint8List> Function(BrushTipMask mask)? debugMake;

  static Future<Uint8List> _onTheEngine(BrushTipMask mask) =>
      brushTipThumbnailAlpha(mask, side: brushTipThumbnailSide);

  /// Once the engine is open, makes what is asked, one after another.
  ///
  /// 🚨A PICTURE WHOSE DEVICE WENT AS IT WAS MADE IS ASKED AGAIN — and
  /// whether it went is asked of THE ENGINE THE MAKING BEGAN ON
  /// (`GpuEngine.isGone`), after the wait. 🗣️gpu-canonical-store-Q11 (유저
  /// 2026-11-10): 「장치를 잃으면 앱은 꺼지지 않고 새 장치를 열어 사본으로
  /// 되살린다」. ↩️It was asked of whichever engine the app had by then
  /// (`appGpuEngineIsGone`), and the app lets a gone engine go the turn
  /// after it first hears of it (`EngineRefusals`): a making whose failure
  /// came back later than that — a worker's read, kernels still compiling
  /// — found the app on no engine or on the next, was said as an error,
  /// and its cell stayed empty for the run (read from the code 2026-11-13,
  /// board `a-tip-thumbnail-read-as-its-device-went-stays-empty`).
  Future<void> _makeWhatIsAsked() async {
    if (_making) {
      return;
    }
    _making = true;
    try {
      while (_asked.isNotEmpty) {
        final engine = appGpuEngineOpen.value;
        if (engine == null || engine.isGone) {
          // None to ask: the next the app opens asks again.
          break;
        }
        final mask = _asked.removeAt(0).target;
        if (mask == null) {
          continue;
        }
        try {
          _of[mask]!.value = await (debugMake ?? _onTheEngine)(mask);
        } on Object catch (error, stack) {
          if (engine.isGone) {
            // Asked again ahead of what waits behind it — of the engine
            // the app has by now, or of the next it opens.
            _asked.insert(0, WeakReference(mask));
            continue;
          }
          // A picture the engine would not make leaves its cell empty —
          // said, not swallowed.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'brush tips',
              context: ErrorDescription('making the picture of ${mask.id}'),
            ),
          );
        }
      }
    } finally {
      _making = false;
    }
  }
}
