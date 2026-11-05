import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/viewer_document.dart';
import '../audio/waveform_painter.dart';
import '../theme/app_theme.dart';

/// A sound file, as the media viewer sees it: ONE page as wide as the sound
/// is long — what its run counts and what its view's zoom is measured
/// against.
///
/// 🚨★★★**THE PICTURE OF A SOUND IS ITS WAVEFORM** — 유저 2026-09-08:
/// 「오디오파일도 열려야하고. 미디어풀에 들어가는건 전부. **통일적으로.**
/// 오디오는 그래서 파형을 보이게한다던가. **비디오 프로그램이랑 비슷한
/// 느낌으로**」. The viewer used to answer 「그림이 없다」 for audio and stop
/// there.
///
/// ⛔It is a [ViewerDocument] rather than a second arm inside the viewer:
/// the run, the transport, the fit and the zoom take it as they take any
/// document. ↩️What the stage SHOWS of it is no longer the page: the page was
/// rasterised onto paper and zoomed as a picture is (F-71, 유저 09-11:
/// 「진짜 미디어 플레이어처럼」), and the surfaces draw its face instead
/// (`SoundFace`) — the view's zoom is the face's lower row. [renderPage]
/// still answers the contract for whatever asks a page of it.
///
/// ⚠️[framesPerSecond] is null: a waveform does not advance BY ITSELF. What
/// plays here is the SOUND, and the viewer's play button asks whether the
/// asset carries any — never whether its pages turn.
class AudioViewerDocument implements ViewerDocument {
  AudioViewerDocument({required this.peaks});

  /// How wide one second is at 100% zoom — the face's lower row at the
  /// pill's 1:1 (`SoundFace.zoom`).
  ///
  /// ⚠️A waveform has no natural size the way a scan or a video frame does,
  /// so this is a CHOICE and not a measurement: wide enough that a syllable
  /// is a readable shape, narrow enough that a minute still fits a panel.
  /// The zoom decides everything after that.
  static const double pixelsPerSecondAtOne = 100;

  /// How tall the page stands: a pixel. Nothing shows it, and Fit takes the
  /// smaller of the two ways a page fits — a sound fits by its LENGTH, so
  /// its 맞춤 is the whole file across the face's lower row. ↩️It was 256,
  /// the band's height on the page, and a short sound fitted by it.
  static const double _height = 1;

  final AudioPeaks peaks;

  /// A sound's ink wherever its picture is drawn — the viewer's face and the
  /// import window's show one sound one way: 🗣️F-71-Q2 (유저 2026-11-05)
  /// 「단색」.
  ///
  /// ⚠️A PALETTE constant, not `colorScheme.primary`: a page is a raster and
  /// the accent is live, so an accent-coloured band would be wrong the
  /// moment the accent changed — the app has one colour scheme and only its
  /// accent is live (UI-R22 #5).
  static Color get ink => AppColors.textDim;

  @override
  int get pageCount => 1;

  @override
  double? get framesPerSecond => null;

  @override
  ui.Size pageSize(int pageIndex) => ui.Size(
    // At least one pixel: an empty or unreadable conform must still be a
    // page the panel can lay out, or the viewer has nothing to frame.
    (peaks.durationSeconds * pixelsPerSecondAtOne).clamp(
      1.0,
      double.maxFinite,
    ),
    _height,
  );

  /// Drawn at the size asked, as a PDF's page is: its lines are as sharp as
  /// the pixels they are drawn on.
  @override
  bool get drawnAtAnySize => true;

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
      color: ink,
      // Drawn at the pixels asked: one of them is a column.
      devicePixelRatio: 1,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => readRegionByRenderingPage(this, pageIndex, box);

  @override
  Future<void> dispose() async {}
}
