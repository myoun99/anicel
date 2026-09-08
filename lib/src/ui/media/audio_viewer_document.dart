import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/viewer_document.dart';
import '../audio/waveform_painter.dart';

/// A sound file, as the media viewer sees it: ONE page, and the page is
/// the waveform.
///
/// 🚨★★★**THE PICTURE OF A SOUND IS ITS WAVEFORM** — 유저 2026-09-08:
/// 「오디오파일도 열려야하고. 미디어풀에 들어가는건 전부. **통일적으로.**
/// 오디오는 그래서 파형을 보이게한다던가. **비디오 프로그램이랑 비슷한
/// 느낌으로**」. The viewer used to answer 「그림이 없다」 for audio and stop
/// there.
///
/// ⛔It is a [ViewerDocument] rather than a second arm inside the viewer,
/// and that is the whole point: the contract is 「give me this page at this
/// size」, which is exactly what a waveform can answer. Everything the
/// viewer already does — the zoom tier, the raster budget, the fit, the
/// pan, the page strip — then works with nothing written twice. That file's
/// own note says what the alternative costs: the per-medium `if (pdf) …
/// else if (frames) …` lived in the viewer five times over.
///
/// ⚠️[framesPerSecond] is null: a waveform does not advance BY ITSELF. What
/// plays here is the SOUND, and the viewer's play button asks whether the
/// asset carries any — never whether its pages turn.
class AudioViewerDocument implements ViewerDocument {
  AudioViewerDocument({
    required this.peaks,
    required this.color,
    this.pixelsPerSecond = _naturalPixelsPerSecond,
    this.height = _naturalHeight,
  });

  /// How wide one second is at 100% zoom.
  ///
  /// ⚠️A waveform has no natural size the way a scan or a video frame does,
  /// so this is a CHOICE and not a measurement: wide enough that a syllable
  /// is a readable shape, narrow enough that a minute still fits a panel.
  /// The zoom decides everything after that.
  static const double _naturalPixelsPerSecond = 100;

  /// And how tall the band stands at 100%.
  static const double _naturalHeight = 256;

  final AudioPeaks peaks;

  /// The band's ink, decided by the caller.
  ///
  /// ⚠️[renderPage] is a raster, so the colour is baked into pixels and
  /// cannot follow anything live. That is safe because the viewer hands in
  /// a PALETTE constant rather than a scheme colour: the app has one colour
  /// scheme and only its accent is live (UI-R22 #5), so an ink taken from
  /// the palette can never go stale under an already-drawn page. ⛔A caller
  /// that passes `colorScheme.primary` here reintroduces exactly that.
  final Color color;

  final double pixelsPerSecond;
  final double height;

  @override
  int get pageCount => 1;

  @override
  double? get framesPerSecond => null;

  @override
  ui.Size pageSize(int pageIndex) => ui.Size(
    // At least one pixel: an empty or unreadable conform must still be a
    // page the panel can lay out, or the viewer has nothing to frame.
    (peaks.durationSeconds * pixelsPerSecond).clamp(1.0, double.maxFinite),
    height,
  );

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());
    // ⛔THE PAINTER IS THE TIMELINE'S. Its `perSecond` entrance exists for
    // exactly this caller; drawing the band here would be the clone the
    // round was told to avoid.
    WaveformPainter.perSecond(
      peaks: peaks,
      // The whole file across whatever pixels were asked for — the
      // requested width IS the zoom, so the band scales with it.
      pixelsPerSecond: peaks.durationSeconds <= 0
          ? 0
          : size.width / peaks.durationSeconds,
      color: color,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  Future<void> dispose() async {}
}
