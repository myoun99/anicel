import 'dart:ui' as ui;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/brush_settings.dart';
import '../effective_device_pixel_ratio.dart';
import 'brush_stroke_preview.dart';
import 'brush_stroke_preview_cache.dart';

/// How a stroke sample is baked. ⚠️A SEAM FOR TESTS: the real one runs in an
/// isolate, so a widget test that drove the settings would be measuring the
/// scheduler rather than this widget's own rule.
typedef BrushStrokeRasterize =
    Future<BrushStrokeSample> Function(
      BrushSettings settings,
      int width,
      int height,
    );

/// The brush in the HAND, drawn as a stroke, following the settings as they
/// are changed.
///
/// 🚨★★★I-33 (유저 2026-09-16): 「브러시/지우개의 프리뷰는 **스트로크를
/// 보여줌. 설정하는거에 맞춰서 실시간 갱신되는**」.
///
/// ⛔**NOT [BrushStrokePreview].** That one draws a PRESET: its settings
/// change when the row is recycled onto another brush, so every sample it
/// asks for is worth keeping and the app-wide cache is exactly right for it.
/// This one's settings change on every frame of a slider drag, and the two
/// things that follows from are the whole of this widget:
///
/// ①**Its samples are not cached** ([BrushStrokePreviewCache.rasterizeUncached]),
/// because a continuous key fills a 512-entry LRU with values nobody will
/// ask for twice and evicts the presets the list reuses.
/// ②**Its requests COALESCE.** At most one bake is in flight and at most one
/// waits behind it, and the waiting one is always the NEWEST — a drag that
/// passes through two hundred values bakes what the machine can afford and
/// lands on the value the hand stopped at. ⛔Without this the worker pool
/// queues every intermediate value and the preview finishes long after the
/// drag, which on an old tablet is the whole drag spent behind stale work.
///
/// ⚠️It OWNS the image it shows (that is what uncached means) and disposes
/// it when the next one lands or the widget goes.
class BrushStrokeLivePreview extends StatefulWidget {
  const BrushStrokeLivePreview({
    super.key,
    required this.settings,
    this.rasterize,
  });

  final BrushSettings settings;

  /// Null = the shared workers, uncached. See [BrushStrokeRasterize].
  final BrushStrokeRasterize? rasterize;

  @override
  State<BrushStrokeLivePreview> createState() => _BrushStrokeLivePreviewState();
}

class _BrushStrokeLivePreviewState extends State<BrushStrokeLivePreview> {
  /// What is on screen. Owned here.
  ui.Image? _shown;

  /// What [_shown] was baked from — the request whose answer is already up.
  ///
  /// 🚨★★★**WHAT IS ON SCREEN IS NOT WORTH ASKING FOR** (유저 2026-09-22:
  /// 「스트로크는 한번 굽고, **값이 바뀔때만** 구우면 되는게 맞지않나?」).
  ///
  /// The widget asks in `build`, and adopting an image rebuilds — so
  /// without this the finished bake's own `setState` asked for the
  /// IDENTICAL bake again, for ever. Nothing on screen ever changed, which
  /// is exactly why it looked like nothing was wrong: a worker isolate
  /// stayed busy and every completion scheduled a frame, so the whole app
  /// re-rastered with the hand standing still (유저 실기: 「가만히 있어도 쭉
  /// 화면이 갱신되고있어」, and this surface alone wore the 「alive」 badge
  /// under Show Repaints).
  ///
  /// ⛔[_running] and [_queued] cannot answer it — both are null by the
  /// time that rebuild runs. The preset preview has kept the same rule all
  /// along, in `_sampleSettings` (`BrushStrokePreview`).
  (BrushSettings, int, int)? _showing;

  /// The newest request nothing has started yet — the coalescing slot.
  (BrushSettings, int, int)? _queued;

  /// The request in flight, so an identical one is not started again.
  (BrushSettings, int, int)? _running;

  @override
  void dispose() {
    _shown?.dispose();
    _shown = null;
    super.dispose();
  }

  void _want(BrushSettings settings, int width, int height) {
    final wanted = (settings, width, height);
    if (wanted == _showing || wanted == _running || wanted == _queued) {
      return;
    }
    _queued = wanted;
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running != null) {
      return; // The completion below picks the queue up again.
    }
    final next = _queued;
    if (next == null) {
      return;
    }
    _queued = null;
    _running = next;
    final rasterize =
        widget.rasterize ?? BrushStrokePreviewCache.instance.rasterizeUncached;
    BrushStrokeSample? sample;
    try {
      sample = await rasterize(next.$1, next.$2, next.$3);
    } on Object catch (_) {
      // A dead worker is the pool's problem to report; the preview simply
      // keeps whatever it was showing.
      sample = null;
    }
    _running = null;
    if (!mounted) {
      sample?.image.dispose();
      return;
    }
    if (sample != null) {
      setState(() {
        _shown?.dispose();
        _shown = sample!.image;
        _showing = next;
      });
    }
    unawaited(_pump());
  }

  @override
  Widget build(BuildContext context) {
    final strokeInk = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.floor();
        final height = constraints.maxHeight.floor();
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }
        final devicePixelRatio = EffectiveDevicePixelRatio.of(context);
        // The same width LADDER the preset rows raster on: a panel splitter
        // drag must not be a re-bake per pixel either.
        _want(
          widget.settings,
          brushStrokePreviewRasterWidth(width.toDouble(), devicePixelRatio),
          (height * devicePixelRatio).round(),
        );
        final shown = _shown;
        if (shown == null) {
          // ⛔The box still takes its place — the panel must not reflow when
          // the first bake lands (없다가 생기는 UI 금지).
          return SizedBox(
            width: width.toDouble(),
            height: height.toDouble(),
          );
        }
        return RawImage(
          image: shown,
          width: width.toDouble(),
          height: height.toDouble(),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          color: strokeInk,
          colorBlendMode: BlendMode.srcIn,
        );
      },
    );
  }
}
