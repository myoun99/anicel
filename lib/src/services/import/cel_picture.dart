/// A picture as an import lays it on cels — decoded by the engine, or, past
/// the side this device's engine hands a picture back at, read by the app
/// itself and never made one GPU image whole.
///
/// 🗣️유저 2026-10-18 (a-picture-past-the-texture-limit-is-decoded-squashed
/// -Q1): 「원본 해상도 그대로 — GPU 를 거치지 않는 디코더로 블록씩 읽는다」 ·
/// 「메모리/시간관련 대가는 최대한 개선하면서 해결」. 🔬Measured 10-18 on the
/// Surface (Impeller): the engine's decoder hands a picture past 16384 a
/// side back with each side past it cut to 16384 on its own — 20000×1080
/// came back 16384×1080, squashed — while the file's header says its own
/// size. A picture within the side keeps the engine's road.
library;

import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;

import '../../core/floor_math.dart';
import '../../core/on_a_worker.dart';
import '../../core/rgba_premultiply.dart';
import '../../models/bitmap_tile.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/tile_coord.dart';
import '../media/png_reading.dart';
import '../persistence/brush_drawing_binary_codec.dart' show AnicelLaidCel;
import '../straight_rgba_image.dart';

/// The longest side this device's engine hands a decoded picture back at:
/// a picture longer on either side is held off it ([FilePicture],
/// [PixelsPicture]). Measured once — one raw row too long for any engine,
/// uploaded, and the width it comes back at — as the 10-18 measurement
/// read it; a row the engine refuses measures no side at all.
///
/// 🧪The test engine cuts nothing (65536×1 comes back whole — measured
/// 10-20), so a test names the side ([debugPictureSideLimit]); every test
/// stands at that one (`flutter_test_config.dart`), as a `testWidgets`
/// clock never waits the measurement out.
Future<int> pictureSideLimit() {
  final named = debugPictureSideLimit;
  if (named != null) {
    return Future<int>.value(named);
  }
  return _measuredSide ??= _measureSide().then((side) => _sideRead = side);
}

/// [pictureSideLimit]'s answer once it has been read — or the side a test
/// names — and null before: for a compose made inside a build, which
/// cannot wait for it (`piecesOver`).
int? get pictureSideLimitIfMeasured => debugPictureSideLimit ?? _sideRead;

int? _sideRead;

/// The side a test stands this device's engine at, in place of
/// [pictureSideLimit]'s measurement — or null.
@visibleForTesting
int? debugPictureSideLimit;

Future<int>? _measuredSide;

/// Longer than any engine's side: a row this long that comes back whole
/// says the engine cuts nothing a picture could be.
const int _probeSide = 1 << 16;

Future<int> _measureSide() async {
  try {
    final row = await uploadRawRgba(
      Uint8List(_probeSide * 4),
      width: _probeSide,
      height: 1,
    );
    try {
      return row.width;
    } finally {
      row.dispose();
    }
  } on Object {
    return _probeSide;
  }
}

/// Whether a picture of [width] × [height] is past [side] — held off the
/// engine.
bool isPastTheSide(int width, int height, int side) =>
    width > side || height > side;

/// Straight-RGBA [rgba] — a Photoshop document's composite or a layer of
/// it — as a picture an import lays: uploaded, or, longer on a side than
/// the engine hands back, its pixels as they are ([PixelsPicture]).
Future<CelPicture> pictureOfPixels(
  Uint8List rgba, {
  required int width,
  required int height,
}) async {
  if (isPastTheSide(width, height, await pictureSideLimit())) {
    return PixelsPicture(rgba, width: width, height: height);
  }
  return EnginePicture(
    await decodeStraightRgbaImage(rgba: rgba, width: width, height: height),
  );
}

/// A picture an import lays on cels ([layCelPicture]): its own size, its
/// pixels as straight RGBA ([straightRgba]) and the letting go of what it
/// holds.
sealed class CelPicture {
  const CelPicture();

  int get width;
  int get height;

  CanvasSize get size => CanvasSize(width: width, height: height);

  /// Every pixel, row after row, as straight RGBA.
  Future<Uint8List> straightRgba();

  void dispose();
}

/// A picture the engine holds: a file within its side, decoded by it, or a
/// picture it drew (a text's letters, a cel composed to be moved).
final class EnginePicture extends CelPicture {
  const EnginePicture(this.image);

  final ui.Image image;

  @override
  int get width => image.width;

  @override
  int get height => image.height;

  @override
  Future<Uint8List> straightRgba() => straightRgbaOf(image);

  @override
  void dispose() => image.dispose();
}

/// A still picture past the engine's side, as its file: read by the app's
/// own decoder when it is laid ([readFileRows]), so the picture itself is
/// never held — laid 1:1 its rows go straight into the cel's tiles
/// ([cutFileInWorker]).
final class FilePicture extends CelPicture {
  const FilePicture(this.bytes, {required this.width, required this.height});

  /// The file, as it was read.
  final Uint8List bytes;

  @override
  final int width;

  @override
  final int height;

  @override
  Future<Uint8List> straightRgba() async =>
      (await readFileInWorker(this)).rgba;

  @override
  void dispose() {}
}

/// A picture past the engine's side whose pixels are in hand — a Photoshop
/// document's, an animation's frame, a file read whole to be resampled:
/// straight RGBA, row after row.
final class PixelsPicture extends CelPicture {
  const PixelsPicture(this.rgba, {required this.width, required this.height});

  final Uint8List rgba;

  @override
  final int width;

  @override
  final int height;

  @override
  Future<Uint8List> straightRgba() async => rgba;

  @override
  void dispose() {}

  /// Each row, top to bottom, handed to [row] where it lies.
  void rows(void Function(int y, Uint8List rgba) row) {
    final stride = width * 4;
    for (var y = 0; y < height; y += 1) {
      row(y, Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
    }
  }
}

/// Where a lay puts a picture on a [canvas]-sized cel of [tileSize] tiles:
/// over the [tiles] the placed picture covers inside the pasteboard wall
/// (tiles beyond it are refused by the surface) — or, laid whole, over the
/// picture's own rect on whole pixels, which the surface keeps tiles over
/// and is told of ([laid], `BitmapSurface.laidBounds`).
typedef CelLayout = ({
  CanvasSize canvas,
  int tileSize,
  TileRange tiles,
  DirtyRegion? laid,
});

/// Where a picture laid 1:1 is cut into a cel's tiles: its top-left on the
/// canvas, on whole pixels, and the [layout] its lay makes.
typedef PictureCut = ({int left, int top, CelLayout layout});

/// [picture]'s file read on a worker and cut into tile blocks there, from
/// the allocator of the isolate that adopts them ([BitmapTile.blocks]) —
/// the cel-thaw's road (`layCelInWorker`): the main isolate copies nothing
/// and the picture is never held whole, only its tiles and the row of them
/// under way.
Future<AnicelLaidCel> cutFileInWorker(FilePicture picture, PictureCut cut) {
  final sent = TransferableTypedData.fromList([picture.bytes]);
  final blocks = BitmapTile.blocks;
  final width = picture.width;
  final height = picture.height;
  return onAWorker(() {
    final cutter = TileCutter(cut, width, tileBlocksHere(blocks));
    try {
      readFileRows(
        sent.materialize().asUint8List(),
        width: width,
        height: height,
        row: cutter.row,
      );
      return cutter.finish();
    } on Object {
      cutter.giveBack();
      rethrow;
    }
  });
}

/// [picture]'s file read whole on a worker — every pixel of it, for a lay
/// that resamples it.
Future<PixelsPicture> readFileInWorker(FilePicture picture) {
  final sent = TransferableTypedData.fromList([picture.bytes]);
  final width = picture.width;
  final height = picture.height;
  return onAWorker(() {
    final rgba = Uint8List(width * height * 4);
    final stride = width * 4;
    readFileRows(
      sent.materialize().asUint8List(),
      width: width,
      height: height,
      row: (y, row) => rgba.setRange(y * stride, (y + 1) * stride, row),
    );
    return PixelsPicture(rgba, width: width, height: height);
  });
}

/// [picture]'s pixels cut into tile blocks here, from this isolate's own
/// allocator — for pixels already in hand ([cutFileInWorker]'s cut, by the
/// same [TileCutter]).
AnicelLaidCel cutPixels(PixelsPicture picture, PictureCut cut) {
  final cutter = TileCutter(
    cut,
    picture.width,
    tileBlocksHere(BitmapTile.blocks),
  );
  try {
    picture.rows(cutter.row);
    return cutter.finish();
  } on Object {
    cutter.giveBack();
    rethrow;
  }
}

/// Every row of the picture file [bytes] — [width] × [height], as its
/// header said — as straight RGBA8, top to bottom: a PNG's as they are
/// inflated ([readPngRows]); any other picture's through the image package,
/// which turns a JPEG by its EXIF as the engine does (measured 10-20).
///
/// Throws when the file reads to another size than it said.
void readFileRows(
  Uint8List bytes, {
  required int width,
  required int height,
  required void Function(int y, Uint8List rgba) row,
}) {
  final png = readPngHeader(bytes);
  if (png != null && !png.interlaced) {
    _expectSize(png.width, png.height, width, height);
    readPngRows(bytes, row);
    return;
  }
  final frame = _decodedByPackage(bytes, frame: 0);
  _expectSize(frame.width, frame.height, width, height);
  _rowsOf(frame, row);
}

void _expectSize(int width, int height, int saidWidth, int saidHeight) {
  if (width != saidWidth || height != saidHeight) {
    throw FormatException(
      'A picture said ${saidWidth}x$saidHeight and read ${width}x$height.',
    );
  }
}

/// The picture file [bytes] through the image package — its [frame] alone,
/// or every frame.
img.Image _decodedByPackage(Uint8List bytes, {int? frame}) {
  final decoded = img.findDecoderForData(bytes)?.decode(bytes, frame: frame);
  if (decoded == null) {
    throw const FormatException('Not a picture this reads.');
  }
  return decoded;
}

/// [frame]'s rows as straight RGBA8, top to bottom. An eight-bit RGB or
/// RGBA picture — a JPEG, a BMP — is read a row at a time where the package
/// decoded it, so it is held once; any other is converted whole first.
void _rowsOf(img.Image frame, void Function(int y, Uint8List rgba) row) {
  if (frame.format != img.Format.uint8 ||
      frame.hasPalette ||
      frame.numChannels < 3) {
    PixelsPicture(
      _straightRgba8(frame),
      width: frame.width,
      height: frame.height,
    ).rows(row);
    return;
  }
  final channels = frame.numChannels;
  final bytes = frame.toUint8List();
  final rgba = Uint8List(frame.width * 4)..fillRange(0, frame.width * 4, 255);
  for (var y = 0; y < frame.height; y += 1) {
    final at = y * frame.rowStride;
    if (channels == 4) {
      rgba.setRange(0, rgba.length, bytes, at);
      zeroFullyClearPixels(rgba);
    } else {
      for (var to = 0, from = at; to < rgba.length; to += 4, from += 3) {
        rgba[to] = bytes[from];
        rgba[to + 1] = bytes[from + 1];
        rgba[to + 2] = bytes[from + 2];
      }
    }
    row(y, rgba);
  }
}

/// The frames of the picture file [bytes] through the image package, each
/// straight RGBA8 with how long it shows.
List<({Uint8List rgba, int width, int height, Duration duration})>
readFramesByPackage(Uint8List bytes) => [
  for (final frame in _decodedByPackage(bytes).frames)
    (
      rgba: _straightRgba8(frame),
      width: frame.width,
      height: frame.height,
      duration: Duration(milliseconds: frame.frameDuration),
    ),
];

/// [frame] as straight RGBA8 — the package's own bytes where they are that
/// already, a converted copy's where not; this changes them either way: a
/// pixel left fully clear is all zero, as the engine hands one back.
Uint8List _straightRgba8(img.Image frame) {
  final rgba =
      frame.format == img.Format.uint8 &&
          frame.numChannels == 4 &&
          !frame.hasPalette
      ? frame
      : frame.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
  final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
  zeroFullyClearPixels(bytes);
  return bytes;
}

/// The frames of an animation past the engine's side, read on a worker.
Future<List<({PixelsPicture picture, Duration duration})>>
readFramesInWorker(Uint8List bytes) {
  final sent = TransferableTypedData.fromList([bytes]);
  return onAWorker(
    () => [
      for (final frame in readFramesByPackage(
        sent.materialize().asUint8List(),
      ))
        (
          picture: PixelsPicture(
            frame.rgba,
            width: frame.width,
            height: frame.height,
          ),
          duration: frame.duration,
        ),
    ],
  );
}

/// Rows of a picture laid 1:1 ([PictureCut]) written into tile blocks from
/// [hands] as they arrive: the tiles of one tile row are open at a time,
/// and a tile the picture left clear goes back as it closes.
final class TileCutter {
  TileCutter(this.cut, this.width, this.hands);

  final PictureCut cut;
  final int width;
  final TileBlockHands hands;

  final _done = <({int x, int y, int pixels})>[];
  final _open = <int, ({Pointer<Uint8> block, Uint8List view})>{};
  int? _openRow;

  int get _side => cut.layout.tileSize;

  TileRange get _tiles => cut.layout.tiles;

  void row(int y, Uint8List rgba) {
    final canvasY = cut.top + y;
    final tileY = floorDiv(canvasY, _side);
    if (tileY < _tiles.firstY || tileY > _tiles.lastY) {
      return;
    }
    if (_openRow != tileY) {
      _close();
      _openRow = tileY;
    }
    final inTile = canvasY - tileY * _side;
    final first = math.max(_tiles.firstX, floorDiv(cut.left, _side));
    final last = math.min(_tiles.lastX, floorDiv(cut.left + width - 1, _side));
    for (var tileX = first; tileX <= last; tileX += 1) {
      final from = math.max(tileX * _side, cut.left);
      final to = math.min(tileX * _side + _side, cut.left + width);
      final at = (inTile * _side + from - tileX * _side) * 4;
      _blockAt(tileX).view.setRange(
        at,
        at + (to - from) * 4,
        rgba,
        (from - cut.left) * 4,
      );
    }
  }

  ({Pointer<Uint8> block, Uint8List view}) _blockAt(int tileX) =>
      _open.putIfAbsent(tileX, () {
        final length = BitmapTile.bytesFor(_side);
        final block = hands.allocate(length);
        final view = block.asTypedList(length)..fillRange(0, length, 0);
        return (block: block, view: view);
      });

  void _close() {
    final tileY = _openRow;
    for (final MapEntry(key: tileX, value: open) in _open.entries) {
      if (tileY != null && _anyInk(open.view)) {
        _done.add((x: tileX, y: tileY, pixels: open.block.address));
      } else {
        hands.free(open.block);
      }
    }
    _open.clear();
  }

  static bool _anyInk(Uint8List pixels) {
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 0) {
        return true;
      }
    }
    return false;
  }

  /// The cel the rows made: its tiles' blocks, for the isolate whose
  /// allocator they came from to adopt (`laidCelSurface`).
  AnicelLaidCel finish() {
    _close();
    return (
      canvasSize: cut.layout.canvas,
      tileSize: _side,
      tiles: _done,
      texts: const [],
      photos: const [],
      laidBounds: cut.layout.laid,
    );
  }

  /// Every block taken, given back — a cut that failed part-way.
  void giveBack() {
    for (final open in _open.values) {
      hands.free(open.block);
    }
    _open.clear();
    for (final tile in _done) {
      hands.free(Pointer<Uint8>.fromAddress(tile.pixels));
    }
    _done.clear();
  }
}
