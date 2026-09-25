import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/kept_span.dart';
import '../../models/movie_clock.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../services/import/raster_cel_import.dart';
import '../../services/media/held_viewer_document.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/movie_bytes.dart';
import '../../services/straight_rgba_image.dart';
import '../../models/media_asset.dart';
import '../../native/qa_video_decoder.dart';
import '../../services/media/video_decode_worker.dart';
import '../../services/media/viewer_document.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../audio/waveform_painter.dart';
import '../media/audio_viewer_document.dart' show AudioViewerDocument;
import '../theme/app_theme.dart';
import '../widgets/checkered_picture.dart';
import '../widgets/transport_bar.dart';

/// The import window's right-hand zone: the selected file, and the bar that
/// walks through it.
///
/// The picture is FITTED into a 16:9 box and nothing else is drawn — no
/// canvas outline, no placement rectangle. What the window is showing here
/// is the source, not the composition; the composition is what Fit answers
/// in the row.
///
/// A still mounts the same bar with one frame. The bar is the shared one
/// (`widgets/transport_bar.dart`), which is why a video will need nothing
/// here beyond a frame supplier the day there is a decoder.
///
/// A sound is its waveform, run over the frames it lasts, with the span
/// IN/OUT keep washed on it (the mockup's window for a sound — 유저
/// 2026-09-11: 「거기서 가져올 구간을 줄이면 블록도 그만큼 줄어든다」).
class ImportPreview extends StatefulWidget {
  const ImportPreview({
    super.key,
    required this.path,
    required this.inFrame,
    required this.outFrame,
    required this.onRangeChanged,
    required this.rangeEditable,
    required this.soundPeaks,
    required this.holdBytes,
    required this.frameRate,
    this.audioSpeed = (numerator: 1, denominator: 1),
  });

  /// The file being looked at, or null when nothing is selected.
  final String? path;

  final int inFrame;
  final int? outFrame;
  final void Function(int inFrame, int? outFrame) onRangeChanged;

  /// Whether IN/OUT can act on anything. A range that changes nothing is a
  /// control that lies, so the ends are shown only where they bite: a
  /// multi-frame source being PLACED.
  final bool rangeEditable;

  /// A sound's peaks once its conform has them
  /// (`AudioConformStore.ensurePeaksFor`); null when it never will.
  final Future<AudioPeaks?> Function(String path) soundPeaks;

  /// Where a picture's, a PDF's or a movie's bytes are
  /// (`ProjectFile.holdMediaBytes`) — the project's own copy first, so a
  /// file the pool carries shows what the project holds, whatever became of
  /// its original.
  final HoldMediaBytes holdBytes;

  /// The project's rate: a sound runs over the frames IN/OUT and the block
  /// it becomes are counted in.
  final ProjectFrameRate frameRate;

  /// The project's accumulated audio pull. A movie's frames are counted on
  /// the SOUND's clock ([MovieClock]) — the frames its IN/OUT and the block
  /// it becomes are counted in, the same ones a sound's are.
  final ({int numerator, int denominator}) audioSpeed;

  /// The narrowest this zone lays out: the transport's own minimum inside
  /// the inset around it. The window gives the file table the rest.
  static double get minimumWidth =>
      2 * _transportInset + TransportBar.minimumWidth();

  static const double _transportInset = 8;

  @override
  State<ImportPreview> createState() => _ImportPreviewState();
}

/// What the well shows: the frames the transport runs over, and the
/// picture under the playhead — or a sound's waveform.
typedef _Shown = ({int frameCount, ui.Image? picture, AudioPeaks? sound});

class _ImportPreviewState extends State<ImportPreview> {
  /// The decoded frames of [ImportPreview.path]. A GIF has many, a still
  /// has one, and anything we cannot decode has none.
  List<ui.Image> _frames = const [];
  String? _loadedPath;
  int _position = 0;

  /// A PDF is not decoded up front. A hundred-page conte rendered to look
  /// at ONE page is the thing §6-m says not to do, so the document stays
  /// open and the page under the playhead is drawn on demand.
  ViewerDocument? _pdf;
  int _pdfPages = 0;
  ui.Image? _pdfPage;
  int _pdfPageShown = -1;

  /// A movie, once the reader has said what it is.
  ///
  /// ⚠️A token from [videoDecodeBackend], not a decoder handle: the native
  /// document lives on a worker isolate now, and TWO owners of one
  /// process-global would make the handle bookkeeping track half the truth.
  /// The viewer goes through the same door, and `close` gives back the
  /// bytes it was reading once the movie is shut ([openHeldMovie]).
  HeldMovie? _video;
  ui.Image? _videoFrame;
  int _videoFrameShown = -1;

  /// A sound, once its conform has answered.
  AudioPeaks? _sound;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ImportPreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _disposeFrames();
    super.dispose();
  }

  void _disposeFrames() {
    for (final frame in _frames) {
      frame.dispose();
    }
    _frames = const [];
    _pdfPage?.dispose();
    _pdfPage = null;
    _pdfPageShown = -1;
    _pdfPages = 0;
    _videoFrame?.dispose();
    _videoFrame = null;
    _videoFrameShown = -1;
    _sound = null;
    final video = _video;
    _video = null;
    if (video != null) {
      // ⛔Only if it is still ours — the backend closes by token, and a
      // token that is not the loaded document is a no-op.
      unawaited(video.close());
    }
    final pdf = _pdf;
    _pdf = null;
    if (pdf != null) {
      unawaited(pdf.dispose());
    }
  }

  /// A movie, on the platforms whose reader exists.
  ///
  /// 🪦This used to say 「the decoder holds ONE document, so opening one here
  /// is also what closes the last」 — a true sentence about a bug. The last
  /// one was usually the media viewer's, and it went blank with no error.
  /// A handle says which movie is whose, and the decoder puts it back.
  Future<void> _loadVideo(String path) async {
    // The capability belongs to the thing that reads — the BACKEND, as the
    // viewer asks it ([VideoDecodeBackend.supported]); a decoder asked
    // beside it could disagree with the one doing the work.
    if (!videoDecodeBackend.supported) {
      setState(() {});
      return;
    }
    final video = await openHeldMovie(
      videoDecodeBackend,
      widget.holdBytes,
      path,
    );
    if (!mounted || _loadedPath != path) {
      if (video != null) {
        unawaited(video.close());
      }
      return;
    }
    if (video == null) {
      setState(() {});
      return;
    }
    setState(() => _video = video);
    await _renderVideoFrame(0);
  }

  /// The movie's clock: its transport counts PROJECT frames, and each one
  /// shows the movie frame that holds its instant — the placement counts
  /// them the same way, so what IN/OUT frame here is what lands.
  MovieClock _clockOf(QaVideoInfo info) => movieClockFor(
    projectRate: widget.frameRate,
    audioSpeed: widget.audioSpeed,
    movie: info,
  );

  /// Draws the frame under the playhead. One at a time: a scrub asks for
  /// the frame it landed on, not for the ones it passed over.
  Future<void> _renderVideoFrame(int index) async {
    final info = _video;
    if (info == null || index == _videoFrameShown) {
      return;
    }
    _videoFrameShown = index;
    final rgba = await videoDecodeBackend.frame(info.token, index);
    if (rgba == null || !mounted || _video != info) {
      return;
    }
    // 🚨A frame the engine refused gets the answer this panel already gives
    // for a movie it could not open: nothing new is drawn. ⛔It does NOT
    // throw — this runs under a scrub, and a preview that threw would take
    // the import window with it.
    //
    // 🪦Before 2026-09-08 a refusal could not be observed here: the decode
    // was a `Completer` with no failure path, so the future stayed pending
    // forever with `_videoFrameShown` already advanced — the preview then
    // held the PREVIOUS frame and would never ask for this index again.
    // Putting the mark back is what lets the next scrub retry, and it is
    // deliberately on the FAILED road only: a frame that merely arrived too
    // late belongs to a scrub that has already moved on.
    final image = await decodedImageStillWanted(
      decodeStraightRgbaImage(
        rgba: rgba,
        width: info.info.width,
        height: info.info.height,
      ),
      wanted: () => mounted && _video == info,
      onFailed: () => _videoFrameShown = -1,
    );
    if (image == null) {
      return;
    }
    setState(() {
      _videoFrame?.dispose();
      _videoFrame = image;
    });
  }

  /// Draws the page under the playhead, once per page.
  Future<void> _renderPdfPage(int page) async {
    final pdf = _pdf;
    if (pdf == null || page == _pdfPageShown) {
      return;
    }
    _pdfPageShown = page;
    ui.Image? image;
    try {
      final size = pdf.pageSize(page);
      final scale = size.width <= 0 ? 1.0 : 640 / size.width;
      image = await pdf.renderPage(
        page,
        width: (size.width * scale).round().clamp(1, 2048),
        height: (size.height * scale).round().clamp(1, 2048),
      );
    } on Object {
      image = null;
    }
    if (!mounted || _pdf != pdf) {
      image?.dispose();
      return;
    }
    setState(() {
      _pdfPage?.dispose();
      _pdfPage = image;
    });
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == _loadedPath) {
      return;
    }
    _loadedPath = path;
    _disposeFrames();
    _position = 0;
    if (path == null) {
      setState(() {});
      return;
    }
    final kind = mediaAssetKindForPath(path);
    if (kind == MediaAssetKind.video) {
      await _loadVideo(path);
      return;
    }
    if (kind == MediaAssetKind.audio) {
      final sound = await widget.soundPeaks(path);
      if (mounted && _loadedPath == path) {
        setState(() => _sound = sound);
      }
      return;
    }
    if (path.toLowerCase().endsWith('.pdf')) {
      final pdf = await openHeldViewerDocument(
        widget.holdBytes,
        path,
        PdfRenderService.open,
      );
      if (!mounted || _loadedPath != path) {
        unawaited(pdf?.dispose());
        return;
      }
      setState(() {
        _pdf = pdf;
        _pdfPages = pdf?.pageCount ?? 0;
      });
      await _renderPdfPage(0);
      return;
    }
    var frames = const <ui.Image>[];
    try {
      final bytes = await readHeldMediaBytes(widget.holdBytes, path);
      frames = [
        for (final frame in await decodeImageFrames(bytes)) frame.image,
      ];
    } on Object {
      // A movie, a PDF, a file being written as we look at it: the zone
      // shows nothing rather than an error nobody asked for. What cannot
      // be imported is already named in the footer.
      frames = const [];
    }
    if (!mounted) {
      for (final frame in frames) {
        frame.dispose();
      }
      return;
    }
    if (_loadedPath != path) {
      for (final frame in frames) {
        frame.dispose();
      }
      return;
    }
    setState(() => _frames = frames);
  }

  /// What the well is showing right now: how many frames the transport
  /// runs over, and the picture under the playhead (null = nothing decoded
  /// yet) — or a sound's waveform.
  ///
  /// 🚨THE SOURCES ARE ASKED ONCE. The count and the picture each used to
  /// walk the same video-then-PDF-then-stills ladder in its own nested
  /// conditional, so a source added to one and not the other would scrub a
  /// video's length over a still's picture. A sound is the fourth rung:
  /// without it a sound fell to the still decode and ran over ONE frame,
  /// so the window had no range to shorten it with.
  _Shown _shownSource() {
    final video = _video;
    if (video != null) {
      return (
        frameCount: _clockOf(
          video.info,
        ).projectFramesCovering(video.info.frameCount),
        picture: _videoFrame,
        sound: null,
      );
    }
    final sound = _sound;
    if (sound != null) {
      return (
        frameCount: sound.durationFrames(widget.frameRate),
        picture: null,
        sound: sound,
      );
    }
    if (_pdfPages > 0) {
      return (frameCount: _pdfPages, picture: _pdfPage, sound: null);
    }
    if (_frames.isEmpty) {
      return (frameCount: 1, picture: null, sound: null);
    }
    return (
      frameCount: _frames.length,
      picture: _frames[_position.clamp(0, _frames.length - 1)],
      sound: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _shownSource();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _stage(source)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ImportPreview._transportInset,
            7,
            ImportPreview._transportInset,
            8,
          ),
          child: _transport(source.frameCount),
        ),
      ],
    );
  }

  /// The picture in its 16:9 well, over the app's ONE transparency checker —
  /// the export preview's own shape, shared (유저 2026-09-11: 「임포트의
  /// 미리보기에서 배경이 투명한파일은 출력창의 미리보기에서 쓰는 …
  /// 격자무늬 그대로 공용화해서 재사용하도록」). It used to draw the file
  /// straight onto the dark well, where open alpha and a dark picture look
  /// the same. A sound has no open alpha to show: its waveform stands on
  /// the well itself.
  Widget _stage(_Shown source) => ColoredBox(
    color: AppColors.backdrop,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: AspectRatio(aspectRatio: 16 / 9, child: _shown(source)),
      ),
    ),
  );

  Widget _shown(_Shown source) {
    final sound = source.sound;
    if (sound != null) {
      return _waveform(sound, source.frameCount);
    }
    final picture = source.picture;
    return picture == null
        ? const SizedBox.shrink()
        : CheckeredPicture(
            image: picture,
            checkerKey: const ValueKey<String>('import-preview-checker'),
          );
  }

  /// A sound's picture — the viewer's painter in the viewer's ink
  /// ([AudioViewerDocument.ink]) — over the frames the transport counts,
  /// with the span IN/OUT keep washed as the transport's range is.
  Widget _waveform(AudioPeaks sound, int frameCount) => LayoutBuilder(
    builder: (context, constraints) {
      final perFrame = constraints.maxWidth / frameCount;
      final kept = _kept(frameCount);
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            key: const ValueKey<String>('import-preview-waveform'),
            painter: WaveformPainter(
              peaks: sound,
              frameRate: widget.frameRate,
              pixelsPerFrame: perFrame,
              color: AudioViewerDocument.ink,
            ),
          ),
          // Always there, clear while IN/OUT do not bite — nothing pops in.
          Positioned(
            left: kept.first * perFrame,
            width: kept.count * perFrame,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              key: const ValueKey<String>('import-preview-kept-span'),
              decoration: _rangeShown(frameCount)
                  ? BoxDecoration(
                      color: TransportBar.rangeWash,
                      border: Border.symmetric(
                        vertical: BorderSide(color: AppColors.accent, width: 2),
                      ),
                    )
                  : const BoxDecoration(),
            ),
          ),
        ],
      );
    },
  );

  /// What IN/OUT keep of [frameCount] frames — the transport's ends and the
  /// waveform's wash read this one answer.
  KeptSpan _kept(int frameCount) => KeptSpan(
    length: frameCount,
    inFrame: widget.inFrame,
    outFrame: widget.outFrame,
  );

  /// IN/OUT bite only on a multi-frame source being placed.
  bool _rangeShown(int frameCount) => widget.rangeEditable && frameCount > 1;

  Widget _transport(int frameCount) {
    final kept = _kept(frameCount);
    return TransportBar(
      frameCount: frameCount,
      currentFrame: _position.clamp(0, frameCount - 1),
      inFrame: kept.first,
      outFrame: kept.last,
      playing: false,
      showRange: _rangeShown(frameCount),
      onSeek: (frame) {
        setState(() => _position = frame);
        if (_pdfPages > 0) {
          unawaited(_renderPdfPage(frame));
        }
        final video = _video;
        if (video != null) {
          unawaited(
            _renderVideoFrame(_clockOf(video.info).movieFrameAt(frame)),
          );
        }
      },
      // Playback belongs to the day a video arrives; stepping is what
      // a page or a GIF frame needs, and that is the scrub.
      onPlayPause: () {},
      onRangeChanged: (start, end) =>
          widget.onRangeChanged(start, end >= frameCount - 1 ? null : end),
    );
  }
}
