import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuRefused;

import '../../models/project_frame_rate.dart';
import '../../native/app_gpu_engine.dart';
import '../../native/engine_wave_peaks.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/media/viewer_document.dart';
import '../../services/straight_rgba_image.dart';
import '../audio/engine_wave_views.dart';
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

  /// The whole file across [width] × [height] pixels, drawn by the engine's
  /// wave pass — the timeline's SE rows' own — into a picture of its own,
  /// read back once: a page is asked for once and kept, so the read is no
  /// cost a frame pays.
  ///
  /// ⏳관제 2026-11-14 22:4x (card the-waveform-is-drawn-on-the-cpu-beside-
  /// its-kernel ③, 「문서 뷰어의 페이지는 (나) GpuGridPicture.read 로
  /// 이미지」 — 유저가 뒤집을 수 있다). ↩️It was the CPU band
  /// (`WaveformPainter.perSecond`), recorded and rasterised.
  ///
  /// A second is a frame here, as it was there: one frame a second, the
  /// width over the file's seconds a frame wide — the arithmetic the
  /// timeline's band runs on.
  ///
  /// ⛔No trim and no envelope: a viewer shows a whole FILE, not a clip
  /// placed on a lane, so the leading frames are none and the gain is one.
  /// ↩️A second painter written for the viewer would have been a clone
  /// whatever its text (유저 2026-08-27: 「사본 남으면 진짜 용서안할게」) —
  /// the seconds were an entrance to the timeline's band; they are the
  /// timeline's pass now.
  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    final batch = (await appGpuGridKernels.ready).batch;
    final picture =
        batch.picture(width, height) ??
        (throw GpuRefused(
          'a page past the side the device makes, '
          '${batch.mostSide} pixels',
        ));
    try {
      if (peaks.durationSeconds > 0) {
        const second = ProjectFrameRate.integer(1);
        final seconds = peaks.durationFrames(second);
        final perSecond = width / peaks.durationSeconds;
        final views = engineWaveViewsOf(
          (
            peaks: peaks,
            startFrame: 0,
            audibleFrames: seconds,
            leadingFrames: 0,
            gain: 1,
          ),
          on: (
            along: (frame) => frame * perSecond,
            origin: 0,
            from: 0,
            to: seconds,
            axis: Axis.horizontal,
            across: height.toDouble(),
            devicePixelRatio: 1,
            frameRate: second,
          ),
          ink: ink,
        );
        for (final view in views) {
          batch.wave(picture, EngineWavePeaks.of(peaks), view);
        }
      }
      return await decodeStraightRgbaImageOnAWorker(
        rgba: picture.read(),
        width: width,
        height: height,
      );
    } finally {
      picture.free();
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
