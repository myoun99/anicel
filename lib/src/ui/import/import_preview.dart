import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/import/raster_cel_import.dart';
import '../../services/media/media_byte_source.dart';
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
    final frameCount = _frames.isEmpty ? 1 : _frames.length;
    final out = widget.outFrame ?? frameCount - 1;
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
                  child: _frames.isEmpty
                      ? const SizedBox.shrink()
                      : FittedBox(
                          child: SizedBox(
                            width: _frames[_position.clamp(
                              0,
                              _frames.length - 1,
                            )].width.toDouble(),
                            height: _frames[_position.clamp(
                              0,
                              _frames.length - 1,
                            )].height.toDouble(),
                            child: CustomPaint(
                              painter: _FramePainter(
                                _frames[_position.clamp(
                                  0,
                                  _frames.length - 1,
                                )],
                              ),
                            ),
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
            onSeek: (frame) => setState(() => _position = frame),
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
