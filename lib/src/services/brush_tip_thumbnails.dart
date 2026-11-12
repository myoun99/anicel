import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/brush_tip_entry.dart' show brushTipThumbnailSide;
import '../models/brush_tip_mask.dart';
import '../native/app_gpu_engine.dart'
    show appGpuEngineIsGone, appGpuEngineOpen;
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

  /// Once the engine is open, makes what is asked, one after another.
  Future<void> _makeWhatIsAsked() async {
    if (_making) {
      return;
    }
    _making = true;
    try {
      while (_asked.isNotEmpty && appGpuEngineOpen.value != null) {
        final mask = _asked.removeAt(0).target;
        if (mask == null) {
          continue;
        }
        try {
          _of[mask]!.value = await brushTipThumbnailAlpha(
            mask,
            side: brushTipThumbnailSide,
          );
        } on Object catch (error, stack) {
          if (appGpuEngineIsGone) {
            // Its device went as it made it: asked again of the next, once
            // that one is open.
            _asked.insert(0, WeakReference(mask));
            break;
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
