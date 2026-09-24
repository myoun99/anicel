import '../../services/straight_rgba_image.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/bake_once_lru.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_settings.dart';
import '../../models/canvas_point.dart';
import '../../services/brush_dab_coverage.dart';
import '../../services/brush_dab_interpolator.dart';
import '../../services/brush_pressure_dynamics.dart';
import '../../services/brush_tip_stamp_cache.dart';
import 'brush_tool_state.dart';

/// The APP-WIDE stroke-preview raster cache (UI-R18 R18-B).
///
/// The old per-row state cache died on unmount, so every list scroll
/// re-rasterized every row SYNCHRONOUSLY in build — the brush list's
/// fixed scroll jank. This cache is process-lived and keyed by
/// (settings, raster size): a preset's sample rasterizes ONCE (in a
/// background isolate, off the scroll frames), uploads as a
/// [ui.Image], and every later mount — any list, any scroll, the
/// coming group/preset trees — draws that image for the cost of one
/// `drawImageRect`.
///
/// The raster itself is unchanged (R20-B honesty: the same
/// tip-stamp-cache + coverage-oracle path the canvas draws with); the
/// image bakes ALPHA only (premultiplied white) and rows tint it with
/// their theme color at paint time, so one entry serves every theme.
class BrushStrokePreviewCache {
  BrushStrokePreviewCache._();

  static final BrushStrokePreviewCache instance = BrushStrokePreviewCache._();

  /// LRU: access re-inserts. ~25KB per entry at list-row sizes; the cap
  /// covers several hundred presets before eviction starts.
  static const int capacity = 512;

  final BakeOnceLru<(BrushSettings, int, int), BrushStrokeSample> _store =
      BakeOnceLru<(BrushSettings, int, int), BrushStrokeSample>(
        capacity: capacity,
        // Callers hold clones (the contract above), so disposing the
        // cache's own handle here is safe.
        retire: (sample) => sample.image.dispose(),
      );

  /// Isolate fan-out cap: a fast scroll — or simply opening a group —
  /// requests dozens of rows at once.
  ///
  /// 🚨IT IS THE MACHINE'S NUMBER, NOT A CONSTANT (유저 2026-09-10: 「지금
  /// 브러시 로드가 매우 느리다」). A flat two left the whole roster queued
  /// behind two workers on a desktop with sixteen cores; measured on all 53
  /// built-ins at a one-column cell, the wall clock was **674 ms at 2, 419 ms
  /// at 4 and 346 ms at 8** — so the cap is where the curve flattens, and the
  /// machine decides how close to it we get.
  ///
  /// ⛔AND IT GOES DOWN ON SMALL MACHINES, which is the point of subtracting
  /// one: a two-core tablet now runs ONE worker beside the UI isolate instead
  /// of two competing with it. The old comment said two workers "keep the UI
  /// isolate free", and on the machines that need that most they did not.
  ///
  /// ⚠️Same formula as the .tvpp import pool (`tvpp_import_door.dart`), which
  /// is the other place in the app that fans work out over isolates. Only the
  /// ceiling differs, and it differs because it was measured HERE.
  static final int _maxConcurrentRasters = kIsWeb
      ? 1
      : rasterWorkersFor(Platform.numberOfProcessors);

  /// How many rasters a machine with [cores] processors may run at once.
  ///
  /// ⛔`cores - 1`, never `cores`: the UI isolate is one of the things
  /// competing for them, and it is the one the user is looking at.
  @visibleForTesting
  static int rasterWorkersFor(int cores) => math.max(1, math.min(cores - 1, 4));

  /// The workers, and who is waiting for one.
  ///
  /// 🚨THEY OUTLIVE THE RASTER. This used to be `Isolate.run` per sample,
  /// which spawns and tears down an isolate for every preset — measured at
  /// 0.6 ms a spawn, so ~32 ms of a 347 ms roster bake, and that is the
  /// SMALL half of why it had to go. The big half is that a fresh isolate
  /// starts with every per-isolate static cold, and the two that matter here
  /// are the tip-stamp cache and — for the native raster this makes possible
  /// — `QaNativeEngine.instance`, which would mean opening the engine
  /// library once per preset.
  final List<_RasterWorker> _workers = <_RasterWorker>[];
  final Queue<Completer<_RasterWorker>> _waiting =
      Queue<Completer<_RasterWorker>>();

  /// Spawns in flight, counted so racing callers cannot overshoot the cap
  /// while they are all awaiting their own [Isolate.spawn].
  int _spawning = 0;

  /// The cached sample for the key, or null (LRU touch on hit). Its image
  /// stays OWNED BY THE CACHE — callers that hold it across frames must
  /// [ui.Image.clone] it.
  BrushStrokeSample? sampleFor(BrushSettings settings, int width, int height) {
    final key = (settings, width, height);
    return _store.peek(key);
  }

  /// Rasterizes (once) and caches the key's sample. Concurrent calls for
  /// the same key share one raster.
  Future<BrushStrokeSample> ensure(
    BrushSettings settings,
    int width,
    int height,
  ) {
    final key = (settings, width, height);
    final cached = sampleFor(settings, width, height);
    if (cached != null) {
      return Future<BrushStrokeSample>.value(cached);
    }
    return _store.ensure(key, () => _rasterize(settings, width, height));
  }

  /// One raster through the shared WORKERS, kept out of the store.
  ///
  /// 🚨★★★**A VALUE NOBODY WILL ASK FOR TWICE DOES NOT GO IN A CACHE**
  /// (I-33, 2026-09-16). The live preview in the tool settings draws the
  /// brush in the hand, and that brush changes on every frame of a slider
  /// drag — so its key is a CONTINUOUS value, which is the one thing this
  /// cache's own width LADDER exists to keep out. Two hundred pixels of
  /// drag would have minted two hundred entries, each ~25KB, evicting the
  /// presets the list actually reuses.
  ///
  /// ⛔The WORKERS are still shared, and that is the half worth sharing: the
  /// pool is the machine's budget (`_maxConcurrentRasters`), so a live
  /// preview queues behind the roster instead of racing it.
  ///
  /// ⚠️THE CALLER OWNS THE IMAGE and must dispose it — there is no store to
  /// retire it. [ensure] hands out cache-owned handles; this one does not.
  Future<BrushStrokeSample> rasterizeUncached(
    BrushSettings settings,
    int width,
    int height,
  ) => _rasterize(settings, width, height);

  Future<BrushStrokeSample> _rasterize(
    BrushSettings settings,
    int width,
    int height,
  ) async {
    final Uint8List rgba;
    if (kIsWeb) {
      // No isolates on web: bake inline (still cached forever).
      rgba = bakeBrushStrokeSample(settings, width, height);
    } else {
      final worker = await _takeWorker();
      try {
        rgba = await worker.bake(settings, width, height);
      } finally {
        _releaseWorker(worker);
      }
    }

    return BrushStrokeSample(
      image: await uploadRawRgba(rgba, width: width, height: height),
    );
  }

  /// A worker that is free, spawning one if the cap allows, else a place in
  /// the queue. The returned worker is already marked busy — the caller owns
  /// it until [_releaseWorker].
  Future<_RasterWorker> _takeWorker() async {
    // A dead worker holds a slot the cap counts, so it goes before anything
    // is handed out — otherwise one crash permanently shrinks the pool.
    _workers.removeWhere((worker) => worker.isDead);
    for (final worker in _workers) {
      if (!worker.busy) {
        worker.busy = true;
        return worker;
      }
    }
    if (_workers.length + _spawning < _maxConcurrentRasters) {
      _spawning += 1;
      try {
        final worker = await _RasterWorker.spawn();
        _workers.add(worker);
        worker.busy = true;
        return worker;
      } finally {
        _spawning -= 1;
      }
    }
    final waiting = Completer<_RasterWorker>();
    _waiting.add(waiting);
    return waiting.future;
  }

  /// ⛔The worker is handed STRAIGHT to the head of the queue rather than
  /// marked free and picked up later: releasing to `busy = false` and letting
  /// the waiter re-scan would let a request that arrived afterwards jump in
  /// front of one that has been queued since before it.
  void _releaseWorker(_RasterWorker worker) {
    if (worker.isDead) {
      _workers.remove(worker);
      // Whoever is queued gets a FRESH worker rather than the corpse: the
      // next `_takeWorker` is under the cap again now that this one is gone.
      final waiting = _waiting.isEmpty ? null : _waiting.removeFirst();
      if (waiting != null) {
        unawaited(
          _takeWorker().then(waiting.complete, onError: waiting.completeError),
        );
      }
      return;
    }
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(worker);
      return;
    }
    worker.busy = false;
  }

  /// Test hook: drops every cached image.
  @visibleForTesting
  void clear() {
    for (final entry in _store.entries) {
      entry.value.image.dispose();
    }
    _store.clear();
  }

  /// Test hook: kills the workers.
  ///
  /// ⚠️Production never calls this — the pool is meant to outlive every
  /// panel. A suite that wants no live isolates at teardown does, and it must
  /// wait for its own bakes first: a worker killed mid-request leaves its
  /// caller waiting on a reply that will never come.
  @visibleForTesting
  void shutdownWorkersForTests() {
    for (final worker in _workers) {
      worker.kill();
    }
    _workers.clear();
    _waiting.clear();
  }

  /// Test hook: how many workers the pool is holding.
  @visibleForTesting
  int get liveWorkerCount => _workers.length;

  /// Test hook: the tip-stamp budget a live worker reported for itself.
  @visibleForTesting
  int? get workerStampByteBudget =>
      _workers.isEmpty ? null : _workers.first.stampByteBudget;

  /// Test hook: kill one worker WITHOUT telling the pool — a crash, not a
  /// shutdown.
  ///
  /// ⚠️It exists because the difference matters and nothing else reaches it:
  /// [shutdownWorkersForTests] empties the list itself, so a suite built on
  /// that one proves only that the pool can spawn from empty. What has to be
  /// pinned is the pool noticing a corpse IN the list — a mutation that let
  /// dead workers keep their slot passed the shutdown test untouched.
  @visibleForTesting
  void killOneWorkerForTests() {
    if (_workers.isEmpty) {
      throw StateError('no worker to kill');
    }
    _workers.first.kill();
  }
}

/// One long-lived raster isolate and the port that reaches it.
class _RasterWorker {
  _RasterWorker._(this._events);

  /// The worker's own channel: the handshake arrives here, and so does the
  /// isolate's DEATH — see [_died].
  final ReceivePort _events;
  late final Isolate _isolate;
  late final SendPort _requests;

  /// Whether a request is out. The pool owns this — see `_takeWorker`.
  bool busy = false;

  /// The request in flight, so a death can fail it instead of leaving it.
  Completer<Uint8List>? _pending;
  bool _dead = false;

  /// Whether the isolate is gone — the pool drops these rather than hand
  /// them out or keep counting them against the cap.
  bool get isDead => _dead;

  /// What the worker set its tip-stamp budget to, as the worker itself
  /// reports it. ⚠️It is echoed rather than assumed because the budget is a
  /// PER-ISOLATE static: the main isolate cannot read the worker's, and a
  /// worker that quietly kept the 128 MB default would look identical from
  /// here. That is exactly the mutation that survived the first attempt.
  late final int stampByteBudget;

  static Future<_RasterWorker> spawn() async {
    final events = ReceivePort();
    final worker = _RasterWorker._(events);
    final ready = Completer<SendPort>();
    events.listen((message) {
      if (message is List<Object?> && message.first is SendPort) {
        worker.stampByteBudget = message[1]! as int;
        ready.complete(message.first! as SendPort);
        return;
      }
      // 🚨ANYTHING ELSE MEANS THE ISOLATE IS GONE — `onExit` sends null, and
      // `errorsAreFatal` turns an uncaught throw into the same event.
      // `Isolate.run` used to surface a failure as a rejected future; a
      // persistent worker that only ever listened for replies would instead
      // leave the row blank FOREVER, which is strictly worse than the crash.
      worker._died(message);
    });
    worker._isolate = await Isolate.spawn(
      _rasterWorkerMain,
      events.sendPort,
      debugName: 'brush-preview-raster',
      onExit: events.sendPort,
      errorsAreFatal: true,
    );
    worker._requests = await ready.future;
    return worker;
  }

  Future<Uint8List> bake(
    BrushSettings settings,
    int width,
    int height,
  ) {
    if (_dead) {
      return Future<Uint8List>.error(
        StateError('the brush preview raster worker is gone'),
      );
    }
    final pending = Completer<Uint8List>();
    _pending = pending;
    final reply = ReceivePort();
    reply.listen((answer) {
      reply.close();
      if (_pending != pending || pending.isCompleted) {
        return;
      }
      _pending = null;
      // 🚨`TransferableTypedData`, NOT the bare list. A `SendPort` COPIES
      // what it carries, and this buffer is four bytes a pixel — the round
      // that put the widening inside the worker did it precisely because
      // `Isolate.run` returns by TRANSFER, and a persistent worker replying
      // with a plain `Uint8List` would have handed that back.
      if (answer is! TransferableTypedData) {
        pending.completeError(
          StateError('brush preview raster failed: $answer'),
        );
        return;
      }
      pending.complete(answer.materialize().asUint8List());
    });
    _requests.send(<Object?>[settings, width, height, reply.sendPort]);
    return pending.future;
  }

  void _died(Object? cause) {
    _dead = true;
    _events.close();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        StateError('the brush preview raster worker died: $cause'),
      );
    }
  }

  void kill() {
    _dead = true;
    _events.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// The worker's whole life: answer bake requests until it is killed.
void _rasterWorkerMain(SendPort handshake) {
  // 🚨THE STAMP CACHE IS PER ISOLATE, AND THIS ISOLATE NOW LIVES FOREVER.
  // `Isolate.run` used to take the cache down with it after every raster; a
  // pooled worker would instead grow toward the 128 MB default and sit on it
  // in the background, on machines the old-device policy says must not pay
  // for the desktop's comfort.
  //
  // 📏8 MB is the working set with room to spare, not a guess: a preview dab
  // is at most `height * 0.62` across (42 px at a DPR-2 row) and a mask costs
  // `size² * 9` bytes, so the whole taper of ONE preset — a quarter-pixel
  // ladder from nothing up to 42 px — is about 1 MB. A group is six or seven
  // presets. The masks are re-derivable in microseconds; what the cache
  // buys is reuse WITHIN a bake, and that fits.
  BrushTipStampCache.instance.byteBudget = 8 * 1024 * 1024;
  final requests = ReceivePort();
  handshake.send(<Object?>[
    requests.sendPort,
    BrushTipStampCache.instance.byteBudget,
  ]);
  requests.listen((message) {
    final request = message as List<Object?>;
    final reply = request[3]! as SendPort;
    try {
      final rgba = bakeBrushStrokeSample(
        request[0]! as BrushSettings,
        request[1]! as int,
        request[2]! as int,
      );
      reply.send(TransferableTypedData.fromList(<Uint8List>[rgba]));
    } on Object catch (error) {
      // The caller is awaiting one message; a string is enough to fail it
      // with something readable rather than hang.
      reply.send('$error');
    }
  });
}

/// One baked stroke sample: the picture.
///
/// ↩️It carried the ink under the preset's name too, a byte a column, from
/// H38 again (2026-09-11: 「슬라이더 공용 텍스트ui 그대로 재사용」): the name
/// wrote in the slider's column-by-column ink, and the bake measured the
/// ground for it off the very bytes the image was uploaded from. F-82 (유저
/// 2026-09-11 19:28) put the name on a plate in a fixed colour
/// (`BrushNameLabel`), and the measurement went with it.
class BrushStrokeSample {
  const BrushStrokeSample({required this.image});

  final ui.Image image;

  BrushStrokeSample cloneImage() => BrushStrokeSample(image: image.clone());
}

/// One preview bake, start to finish: raster the stroke and widen it to the
/// pixel format the upload wants.
///
/// 🚨THIS IS THE ISOLATE'S WHOLE JOB. Everything here used to be split — the
/// stroke over there, the widening back on the UI isolate —
/// and the split cost the UI a full-buffer loop per preset for nothing (the
/// result is transferred, not copied; see `_rasterize`).
Uint8List bakeBrushStrokeSample(
  BrushSettings settings,
  int width,
  int height,
) {
  final alpha = rasterizeBrushStrokeSample(settings, width, height);
  // Premultiplied WHITE: rgb = alpha — correct standalone, and the
  // srcIn tint at paint time only reads the alpha anyway.
  final rgba = Uint8List(alpha.length * 4);
  for (var index = 0; index < alpha.length; index += 1) {
    final value = alpha[index];
    final base = index * 4;
    rgba[base] = value;
    rgba[base + 1] = value;
    rgba[base + 2] = value;
    rgba[base + 3] = value;
  }
  return rgba;
}

/// The stroke-sample rasterizer (moved OUT of the widget so the isolate
/// can run it): a synthetic S-curve with a 0-1-0 pressure arc, resolved
/// through the SAME tip-stamp cache + pixel-coverage oracle the canvas
/// draws with (R20-B: what the list shows is the quantized reality).
/// Placement dynamics (scatter/jitter) stay intentionally off so the
/// preview is deterministic.
Uint8List rasterizeBrushStrokeSample(
  BrushSettings settings,
  int width,
  int height,
) {
  final accumulated = Float64List(width * height);
  final baseSize = height * 0.62;
  // The canvas's own step for this size and spacing — the preview draws by
  // the canvas's law (R20-B), and a floor of its own (0.02) stood here
  // while the canvas clamped at 0.05.
  final spacing = const BrushDabInterpolator().spacingForBrushSize(
    baseSize,
    BrushToolState.clampSpacing(settings.spacing),
  );
  final margin = baseSize * 0.5 + 1;

  const curveSteps = 512;
  double? previousX;
  double? previousY;
  var pendingDistance = double.infinity;
  var sequence = 0;
  for (var step = 0; step <= curveSteps; step += 1) {
    final t = step / curveSteps;
    final x = margin + t * (width - margin * 2);
    final y = height / 2 + math.sin(t * math.pi * 2) * height * 0.18;
    if (previousX != null && previousY != null) {
      final dx = x - previousX;
      final dy = y - previousY;
      pendingDistance += math.sqrt(dx * dx + dy * dy);
    }
    previousX = x;
    previousY = y;
    if (pendingDistance < spacing) {
      continue;
    }
    pendingDistance = 0;

    final pressure = math.sin(t * math.pi).clamp(0.08, 1.0).toDouble();
    // BB-3: the preview's synthetic pressure arc rides the SAME curves as
    // real strokes, so the list shows the configured taper (size/opacity/
    // flow/hardness alike). ⛔It used to ride a COPY of them — the same four
    // multiplications written a third time. Now it runs the one law and
    // keeps only what is its own: the floors below.
    //
    // ⚠️F-12: the base opacity is 1.0 and the tool's opacity caps the
    // ACCUMULATED swatch once, at the end — on the dab it would not cap
    // anything, and the preview would go on darkening past the setting
    // exactly the way the canvas did.
    final curved = applyBrushInputDynamics(
      BrushDab(
        center: CanvasPoint(x: x, y: y),
        color: 0xFF000000,
        size: baseSize,
        opacity: 1.0,
        flow: settings.flow,
        hardness: settings.hardness,
        pressure: pressure,
        sequence: sequence,
        roundness: settings.roundness,
        angleDegrees: settings.angleDegrees,
        tipMask: settings.tipMask,
        dualMask: settings.dualMask,
        dualMaskScale: settings.dualMaskScale,
        dualDensity: settings.dualDensity,
        dualCompositeMode: settings.dualCompositeMode,
        textureMask: settings.textureMask,
        textureScale: settings.textureScale,
        textureDensity: settings.textureDensity,
        // The swatch has to show the brush the canvas will draw, so the
        // edge step and the dual density belong here too. ⚠️The dual PHASE
        // deliberately does not: it is random per dab on the canvas, and a
        // preview that moved under you every rebuild would be noise.
        antiAlias: settings.antiAlias,
      ),
      shape: settings.shape,
    );
    // 🚨THE FLOORS ARE THE PREVIEW'S OWN, and that is why they stayed here
    // rather than moving into the law: a swatch has to show the brush's
    // SHAPE at any setting, so it never fades to nothing and never thins
    // below one pixel. The canvas has no such duty.
    final dab = BrushTipStampCache.instance.resolveDab(
      curved.copyWith(
        size: math.max(1.0, curved.size),
        opacity: curved.opacity.clamp(0.05, 1.0),
        flow: curved.flow.clamp(0.05, 1.0),
      ),
    );
    sequence += 1;

    // 🚨THE VISITOR, NOT THE LIST. This fold is the whole consumer: a pixel
    // arrives, it is added to the plane, and nothing ever looks at it again.
    // The list form allocates a `BrushPixelCoverage` for every one of them
    // and copies the lot for `List.unmodifiable` — measured 2026-09-10, one
    // bake of the 53-preset roster at a DPR-2 one-column cell made 8,480,380
    // of those objects, and the container was 127 ms of an 833 ms raster.
    // ⛔The arithmetic is unchanged: same walk, same cascade, same order —
    // see `forEachBrushPixelCoverage`, which the list form now also runs.
    // ⛔`coverage * dab.flow * dab.opacity` STAYS IN THAT ORDER. Folding the
    // two dab factors into one hoisted product is the same value in algebra
    // and a different double in floating point, and this plane is compared
    // byte for byte by the preview's own pins.
    forEachBrushPixelCoverage(dab, (x, y, coverage) {
      if (x >= width || y >= height) {
        return;
      }
      final index = y * width + x;
      final dabAlpha = coverage * dab.flow * dab.opacity;
      accumulated[index] += dabAlpha * (1 - accumulated[index]);
    });
  }

  // The ceiling, once, on what the dabs accumulated. Floored the way the
  // per-dab value has always been: the row has to show the brush's SHAPE
  // at any setting, so a swatch never fades to nothing.
  final ceiling = settings.opacity.clamp(0.05, 1.0);
  final bytes = Uint8List(width * height);
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = (accumulated[index].clamp(0.0, 1.0) * ceiling * 255).round();
  }
  return bytes;
}
