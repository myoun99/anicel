import '../../services/straight_rgba_image.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/bake_once_lru.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_settings.dart';
import '../../models/canvas_point.dart';
import '../../services/brush_dab_coverage.dart';
import '../../services/brush_pressure_dynamics.dart';
import '../../services/brush_tip_stamp_cache.dart';

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

  final BakeOnceLru<(BrushSettings, int, int), ui.Image> _store =
      BakeOnceLru<(BrushSettings, int, int), ui.Image>(
        capacity: capacity,
        // Callers hold clones (the contract above), so disposing the
        // cache's own handle here is safe.
        retire: (image) => image.dispose(),
      );

  /// Isolate fan-out cap: a fast scroll requests dozens of rows at once;
  /// two workers keep the UI isolate free without a spawn storm.
  static const int _maxConcurrentRasters = 2;
  int _activeRasters = 0;
  final Queue<void Function()> _rasterQueue = Queue<void Function()>();

  /// The cached image for the key, or null (LRU touch on hit). The
  /// returned image stays OWNED BY THE CACHE — callers that hold it
  /// across frames must [ui.Image.clone] it.
  ui.Image? imageFor(BrushSettings settings, int width, int height) {
    final key = (settings, width, height);
    return _store.peek(key);
  }

  /// Rasterizes (once) and caches the key's sample. Concurrent calls for
  /// the same key share one raster.
  Future<ui.Image> ensure(BrushSettings settings, int width, int height) {
    final key = (settings, width, height);
    final cached = imageFor(settings, width, height);
    if (cached != null) {
      return Future<ui.Image>.value(cached);
    }
    return _store.ensure(key, () => _rasterize(settings, width, height));
  }

  Future<ui.Image> _rasterize(
    BrushSettings settings,
    int width,
    int height,
  ) async {
    final Uint8List alpha;
    if (kIsWeb) {
      // No isolates on web: rasterize inline (still cached forever).
      alpha = rasterizeBrushStrokeSample(settings, width, height);
    } else {
      await _acquireRasterSlot();
      try {
        alpha = await Isolate.run(
          () => rasterizeBrushStrokeSample(settings, width, height),
        );
      } finally {
        _releaseRasterSlot();
      }
    }

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
    return uploadRawRgba(rgba, width: width, height: height);
  }

  Future<void> _acquireRasterSlot() {
    if (_activeRasters < _maxConcurrentRasters) {
      _activeRasters += 1;
      return Future<void>.value();
    }
    final gate = Completer<void>();
    _rasterQueue.add(() {
      _activeRasters += 1;
      gate.complete();
    });
    return gate.future;
  }

  void _releaseRasterSlot() {
    _activeRasters -= 1;
    if (_rasterQueue.isNotEmpty) {
      _rasterQueue.removeFirst()();
    }
  }

  /// Test hook: drops every cached image.
  @visibleForTesting
  void clear() {
    for (final entry in _store.entries) {
      entry.value.dispose();
    }
    _store.clear();
  }
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
  final spacing = math.max(1.0, baseSize * settings.spacing.clamp(0.02, 4.0));
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
    final curved = applyBrushPressureDynamics(
      BrushDab(
        center: CanvasPoint(x: x, y: y),
        color: 0xFF000000,
        size: baseSize,
        opacity: 1.0,
        flow: settings.flow,
        hardness: settings.hardness,
        tipShape: settings.tipShape,
        pressure: pressure,
        sequence: sequence,
        roundness: settings.roundness,
        angleDegrees: settings.angleDegrees,
        tipMask: settings.tipMask,
        dualMask: settings.dualMask,
        dualMaskScale: settings.dualMaskScale,
        textureMask: settings.textureMask,
        textureScale: settings.textureScale,
        textureDensity: settings.textureDensity,
      ),
      sizeCurve: settings.sizePressureCurve,
      opacityCurve: settings.opacityPressureCurve,
      flowCurve: settings.flowPressureCurve,
      hardnessCurve: settings.hardnessPressureCurve,
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

    for (final pixel in brushPixelCoveragesForDab(dab)) {
      if (pixel.x >= width || pixel.y >= height) {
        continue;
      }
      final index = pixel.y * width + pixel.x;
      final dabAlpha = pixel.coverage * dab.flow * dab.opacity;
      accumulated[index] += dabAlpha * (1 - accumulated[index]);
    }
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
