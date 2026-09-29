import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../photoshop/psd_image.dart' show decodePsdCompositeImage;
import '../photoshop/psd_reader.dart' show looksLikePsdBytes;
import 'media_byte_source.dart';
import 'psd_composite_document.dart';
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

  /// Opens the image [source] holds. A whole file never enters the Dart
  /// heap: the buffer goes straight to the descriptor and is released here.
  /// Bytes that are not one — a carried image inside the project file, or
  /// its framed copy — are read once and handed over the same way.
  ///
  /// 🚨A PHOTOSHOP DOCUMENT IS ASKED FOR FIRST, and opens as its composite
  /// ([PsdCompositeDocument]): no platform codec reads one, and every image
  /// entry point asks ([decodePsdCompositeImage]'s note). 🪦The viewer read
  /// its images through `decodeImageFrames`, which asks, until this
  /// document replaced it (#1364, 2026-08-29) without asking — from then on
  /// the viewer's own picker offered a `.psd` the viewer could not open, and
  /// a PSD from the pool stamped nothing onto an envelope (found 2026-09-30,
  /// moving the import preview onto the viewer's door).
  ///
  /// Everything is read before this returns, so whoever holds [source]
  /// can let go as soon as it does.
  static Future<ViewerDocument> open(MediaByteSource source) async {
    final file = source.wholeFilePath;
    if (file == null) {
      final bytes = await source.read();
      return looksLikePsdBytes(bytes)
          ? PsdCompositeDocument.read(bytes)
          : _decoded(await ui.ImmutableBuffer.fromUint8List(bytes));
    }
    return await _startsLikePsd(file)
        ? PsdCompositeDocument.read(await File(file).readAsBytes())
        : _decoded(await ui.ImmutableBuffer.fromFilePath(file));
  }

  /// Whether the file at [path] begins like a Photoshop document — four
  /// bytes read, so an image the codec takes still never enters the heap.
  static Future<bool> _startsLikePsd(String path) async {
    final file = await File(path).open();
    try {
      return looksLikePsdBytes(await file.read(4));
    } finally {
      await file.close();
    }
  }

  /// [buffer] through the platform codec. The buffer is released here,
  /// whichever way this ends.
  static Future<ImageViewerDocument> _decoded(ui.ImmutableBuffer buffer) async {
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } finally {
      buffer.dispose();
    }
    // The frame count needs a codec, and a codec needs a size; ask for the
    // smallest legal one so counting an animation costs nothing.
    //
    // 🚨★★★**AND EVERY ROAD OUT OF HERE RELEASES WHAT IT TOOK.** The buffer
    // above already had its `finally`; the descriptor and the probe did not,
    // so an image the engine refused to make a codec for — or whose first
    // frame it refused to decode — leaked BOTH. This is the biggest one of
    // its kind in the app: the header two paragraphs up measures the
    // retained descriptor at 20 MB for an 8000×6000 PNG, against the 256 KB
    // a tile holds. Found by the 2026-09-09 audit of the round that closed
    // the same shape in the decode paths and claimed the family with it.
    ui.Codec? probe;
    try {
      probe = await descriptor.instantiateCodec(targetWidth: 1, targetHeight: 1);
      final frameCount = probe.frameCount;
      // The probe is already going to decode a 1×1 frame; reading its stated
      // duration on the way past is what tells an animation from a still.
      final first = await probe.getNextFrame();
      final frameGap = first.duration;
      first.image.dispose();
      return ImageViewerDocument._(descriptor, frameCount, frameGap);
    } on Object {
      // ⚠️The descriptor is disposed ONLY on this road. On the other one it
      // becomes the document's own, and disposing it here would hand the
      // caller a handle to nothing.
      descriptor.dispose();
      rethrow;
    } finally {
      probe?.dispose();
    }
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

  /// ⚠️A codec decodes WHOLE images, so a box costs the page at its own
  /// size — the full decode this document otherwise never makes (see the
  /// header). The viewer bills that before it asks.
  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => readRegionByRenderingPage(this, pageIndex, box);

  @override
  Future<void> dispose() async => _descriptor.dispose();
}
