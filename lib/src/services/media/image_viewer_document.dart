import 'dart:ui' as ui;

import 'viewer_document.dart';

/// A still or animated image, as a [ViewerDocument]: one page per frame,
/// each rendered at the size the viewer will draw it.
///
/// 🚨★★★**THE ENCODED FILE IS THE DOCUMENT — the decoded picture is not.**
/// 유저 2026-08-29 asked whether a single-frame image just has to be held
/// whole (「한장짜리면 결국 그대로 올라가는건 어쩔수없는거지?」). It does
/// not: the memory is set by the pixels on SCREEN, not by the file.
///
/// 🧪Measured on an 8000×6000 PNG: file ≈20MB · decoded at original size
/// **183MB** · decoded at a 1920×1440 view **10.5MB** — 17×. The old path
/// paid both, reading the bytes whole and then decoding every frame at
/// full resolution, and kept the big one for as long as the viewer was
/// open.
///
/// ⛔It does not decode big and scale down. `instantiateCodec` takes the
/// target size, so the large image is never made at all — which is the
/// difference between peak memory and a smaller peak.
///
/// The encoded bytes stay (as an [ui.ImageDescriptor]) because they are
/// what makes a second, sharper render possible when the user zooms in.
/// That is the same trade PDF makes by keeping its native handle open.
final class ImageViewerDocument implements ViewerDocument {
  ImageViewerDocument._(this._descriptor, this._frameCount, this._frameGap);

  /// Opens [path] without ever holding the file in the Dart heap: the
  /// buffer goes straight to the descriptor and is released here.
  static Future<ImageViewerDocument> open(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } finally {
      buffer.dispose();
    }
    // The frame count needs a codec, and a codec needs a size; ask for the
    // smallest legal one so counting an animation costs nothing.
    final probe = await descriptor.instantiateCodec(
      targetWidth: 1,
      targetHeight: 1,
    );
    final frameCount = probe.frameCount;
    // The probe is already going to decode a 1×1 frame; reading its stated
    // duration on the way past is what tells an animation from a still.
    final first = await probe.getNextFrame();
    final frameGap = first.duration;
    first.image.dispose();
    probe.dispose();
    return ImageViewerDocument._(descriptor, frameCount, frameGap);
  }

  final ui.ImageDescriptor _descriptor;
  final int _frameCount;

  /// The first frame's own duration — an animated image states one per
  /// frame, and this reads frame 0's. ⚠️A GIF whose frames differ will
  /// play at ITS rate rather than each frame's; the alternative is a
  /// per-page schedule, which nothing has asked for.
  final Duration _frameGap;

  @override
  double? get framesPerSecond =>
      _frameCount <= 1 || _frameGap <= Duration.zero
      ? null
      : 1000000 / _frameGap.inMicroseconds;

  @override
  int get pageCount => _frameCount;

  @override
  ui.Size pageSize(int pageIndex) => ui.Size(
    _descriptor.width.toDouble(),
    _descriptor.height.toDouble(),
  );

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    final codec = await _descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    try {
      // ⚠️An animated codec only walks FORWARD, so reaching frame N means
      // decoding the ones before it. That is the cost of not holding them
      // all, and it is paid only by animations — a still image is one
      // step. The viewer's page cache keeps the walk from repeating while
      // the user reads one frame.
      var frame = await codec.getNextFrame();
      for (var i = 0; i < pageIndex; i += 1) {
        frame.image.dispose();
        frame = await codec.getNextFrame();
      }
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override
  Future<void> dispose() async => _descriptor.dispose();
}
