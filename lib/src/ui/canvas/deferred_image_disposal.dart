import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// Disposes display [ui.Image]s only after the frames that might still
/// reference them are safely past.
///
/// Disposing an image synchronously with its replacement races the raster
/// thread: the previously produced frame's layer tree can still reference
/// the old texture while it rasterizes, and destroying it mid-flight
/// intermittently rendered that tile as an opaque black square for one
/// frame. The race window opens exactly when images are replaced or
/// finalized — pen-up commits allocate heavily and trigger GC, which runs
/// the tile-image [Finalizer] while the on-screen frame still shows the
/// just-replaced tile, matching the observed "black square behind the
/// stroke on some strokes at any zoom".
///
/// [retire] therefore holds an image for a few frame boundaries before
/// disposing it: by then the frame that stopped referencing the image has
/// been produced and handed off, and no in-flight layer tree can still
/// sample the texture. The cost is a handful of small images living a few
/// frames longer.
class DeferredImageDisposer {
  DeferredImageDisposer();

  /// Shared instance used by the display caches and the stroke overlay.
  static final DeferredImageDisposer instance = DeferredImageDisposer();

  /// Frame boundaries an image survives after retirement. Two covers the
  /// producing frame plus the frame that replaced the image; one more
  /// absorbs pipeline depth between the UI and raster threads.
  static const int _boundariesBeforeDispose = 3;

  final List<List<ui.Image>> _buckets = List<List<ui.Image>>.generate(
    _boundariesBeforeDispose,
    (_) => <ui.Image>[],
  );
  bool _flushScheduled = false;

  /// Schedules [image] for disposal after [_boundariesBeforeDispose] frame
  /// boundaries.
  ///
  /// Without a scheduler binding (bare unit tests) the image is disposed
  /// immediately — there is no raster thread racing the disposal either.
  void retire(ui.Image image) {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object catch (_) {
      image.dispose();
      return;
    }
    _buckets.last.add(image);
    _ensureFlushScheduled(binding);
  }

  void _ensureFlushScheduled(SchedulerBinding binding) {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    binding.addPostFrameCallback((_) => _onFrameBoundary(binding));
    binding.scheduleFrame();
  }

  void _onFrameBoundary(SchedulerBinding binding) {
    _flushScheduled = false;
    final expired = _buckets.removeAt(0);
    _buckets.add(<ui.Image>[]);
    for (final image in expired) {
      image.dispose();
    }
    if (_buckets.any((bucket) => bucket.isNotEmpty)) {
      _ensureFlushScheduled(binding);
    }
  }
}
