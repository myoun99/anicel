import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/import/raster_cel_import.dart';
import '../../services/media/media_byte_source.dart';
import '../../core/straight_rgba_image.dart';
import '../../models/media_asset.dart';
import '../../native/qa_video_decoder.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../theme/app_theme.dart';
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
  PdfDocumentHandle? _pdf;
  int _pdfPages = 0;
  ui.Image? _pdfPage;
  int _pdfPageShown = -1;

  /// A movie, once the reader has said what it is.
  QaVideoInfo? _video;
  ui.Image? _videoFrame;
  int _videoFrameShown = -1;
  bool _videoOpen = false;

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
    _video = null;
    if (_videoOpen) {
      _videoOpen = false;
      QaVideoDecoder.instance?.close();
    }
    final pdf = _pdf;
    _pdf = null;
    if (pdf != null) {
      unawaited(pdf.dispose());
    }
  }

  /// A movie, on the platforms whose reader exists. The decoder holds ONE
  /// document, so opening one here is also what closes the last.
  Future<void> _loadVideo(String path) async {
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      // No engine, or a build without a reader: the zone stays empty and
      // the window's footer already says a movie cannot be placed.
      setState(() {});
      return;
    }
    final info = decoder.open(path);
    if (!mounted || _loadedPath != path) {
      decoder.close();
      return;
    }
    if (info == null) {
      setState(() {});
      return;
    }
    setState(() {
      _video = info;
      _videoOpen = true;
    });
    await _renderVideoFrame(0);
  }

  /// Draws the frame under the playhead. One at a time: a scrub asks for
  /// the frame it landed on, not for the ones it passed over.
  Future<void> _renderVideoFrame(int index) async {
    final info = _video;
    final decoder = QaVideoDecoder.instance;
    if (info == null || decoder == null || index == _videoFrameShown) {
      return;
    }
    _videoFrameShown = index;
    final rgba = decoder.frame(
      index,
      width: info.width,
      height: info.height,
    );
    if (rgba == null || !mounted || _video != info) {
      return;
    }
    final completer = Completer<ui.Image>();
    decodeStraightRgbaImage(
      rgba: rgba,
      width: info.width,
      height: info.height,
      onDecoded: completer.complete,
    );
    final image = await completer.future;
    if (!mounted || _video != info) {
      image.dispose();
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
    List<ui.Image> frames = const [];
    try {
      final Uint8List bytes = await MediaFileBytes(path).read();
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

  @override
  Widget build(BuildContext context) {
    final frameCount = _video != null
        ? _video!.frameCount
        : _pdfPages > 0
        ? _pdfPages
        : (_frames.isEmpty ? 1 : _frames.length);
    final out = widget.outFrame ?? frameCount - 1;
    final shown = _video != null
        ? _videoFrame
        : _pdfPages > 0
        ? _pdfPage
        : (_frames.isEmpty
              ? null
              : _frames[_position.clamp(0, _frames.length - 1)]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: AppColors.backdrop,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: shown == null
                      ? const SizedBox.shrink()
                      : FittedBox(
                          child: SizedBox(
                            width: shown.width.toDouble(),
                            height: shown.height.toDouble(),
                            child: CustomPaint(painter: _FramePainter(shown)),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
          child: TransportBar(
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
            onRangeChanged: (start, end) => widget.onRangeChanged(
              start,
              end >= frameCount - 1 ? null : end,
            ),
          ),
        ),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.image != image;
}
