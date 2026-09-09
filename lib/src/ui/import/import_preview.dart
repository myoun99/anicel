import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/import/raster_cel_import.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/straight_rgba_image.dart';
import '../../models/media_asset.dart';
import '../../native/qa_video_decoder.dart';
import '../../services/media/video_decode_worker.dart';
import '../../services/media/viewer_document.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../theme/app_theme.dart';
import '../widgets/transport_bar.dart';
import '../repaint_props.dart';

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
class ImportPreview extends StatefulWidget {
  const ImportPreview({
    super.key,
    required this.path,
    required this.inFrame,
    required this.outFrame,
    required this.onRangeChanged,
    required this.rangeEditable,
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

  @override
  State<ImportPreview> createState() => _ImportPreviewState();
}

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
  /// The viewer goes through the same door.
  ({int token, QaVideoInfo info})? _video;
  ui.Image? _videoFrame;
  int _videoFrameShown = -1;


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
    final video = _video;
    _video = null;
    if (video != null) {
      // ⛔Only if it is still ours — the backend closes by token, and a
      // token that is not the loaded document is a no-op.
      unawaited(videoDecodeBackend.close(video.token));
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
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      // No engine, or a build without a reader: the zone stays empty and
      // the window's footer already says a movie cannot be placed.
      setState(() {});
      return;
    }
    final video = await videoDecodeBackend.open(path);
    if (!mounted || _loadedPath != path) {
      if (video != null) {
        unawaited(videoDecodeBackend.close(video.token));
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
    if (mediaAssetKindForPath(path) == MediaAssetKind.video) {
      await _loadVideo(path);
      return;
    }
    if (path.toLowerCase().endsWith('.pdf')) {
      final pdf = await PdfRenderService.open(path);
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
      final bytes = await MediaFileBytes(path).read();
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
  /// yet).
  ///
  /// 🚨THE THREE SOURCES ARE ASKED ONCE. The count and the picture each
  /// used to walk the same video-then-PDF-then-stills ladder in its own
  /// nested conditional, so a source added to one and not the other would
  /// scrub a video's length over a still's picture.
  ({int frameCount, ui.Image? picture}) _shownSource() {
    final video = _video;
    if (video != null) {
      return (frameCount: video.info.frameCount, picture: _videoFrame);
    }
    if (_pdfPages > 0) {
      return (frameCount: _pdfPages, picture: _pdfPage);
    }
    if (_frames.isEmpty) {
      return (frameCount: 1, picture: null);
    }
    return (
      frameCount: _frames.length,
      picture: _frames[_position.clamp(0, _frames.length - 1)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _shownSource();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _stage(source.picture)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
          child: _transport(source.frameCount),
        ),
      ],
    );
  }

  Widget _stage(ui.Image? picture) => ColoredBox(
    color: AppColors.backdrop,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: picture == null
              ? const SizedBox.shrink()
              : FittedBox(
                  child: SizedBox(
                    width: picture.width.toDouble(),
                    height: picture.height.toDouble(),
                    child: CustomPaint(painter: _FramePainter(picture)),
                  ),
                ),
        ),
      ),
    ),
  );

  Widget _transport(int frameCount) {
    final out = widget.outFrame ?? frameCount - 1;
    return TransportBar(
      frameCount: frameCount,
      currentFrame: _position.clamp(0, frameCount - 1),
      inFrame: widget.inFrame.clamp(0, frameCount - 1),
      outFrame: out.clamp(0, frameCount - 1),
      playing: false,
      showRange: widget.rangeEditable && frameCount > 1,
      onSeek: (frame) {
        setState(() => _position = frame);
        if (_pdfPages > 0) {
          unawaited(_renderPdfPage(frame));
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

class _FramePainter extends CustomPainter with RepaintOnProps {
  const _FramePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  Object get props => (image,);
}
