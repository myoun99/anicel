import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

import '../../core/sync_image_upload.dart';
import 'deferred_image_disposal.dart';

/// A tile's picture as it is drawn: [source], one tile's worth of [image].
///
/// Either the tile's OWN texture ([OwnTilePicture]) or a SLOT of a page
/// that holds many tiles' ([TileSlot]) — the same premultiplied bytes
/// either way, and the same pixels drawn 1:1.
sealed class TilePicture {
  TilePicture._(this.source);

  ui.Image get image;
  final ui.Rect source;
}

/// A tile's picture in a texture of its own: the door's upload
/// ([pictureOf]), the pen-up handoff, or a picture carrying its chain.
final class OwnTilePicture extends TilePicture {
  OwnTilePicture(this.image)
    : super._(
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );

  @override
  final ui.Image image;
}

/// A tile's picture as a slot of a page ([TilePages]).
final class TileSlot extends TilePicture {
  TileSlot._(this._page, ui.Rect source) : super._(source);

  final _Page _page;

  /// The page, its writes not submitted yet submitted first — whatever
  /// draws the slot draws its bytes ([TilePages._submitWrites]).
  @override
  ui.Image get image => _page.drawn;

  /// The tile let its picture go: the slot is dead, and its page with it
  /// once every slot of a page that takes no more is.
  void release() => _page.release();
}

/// 🚨★★★A TILE'S BYTES GO INTO A SLOT OF A PAGE, NOT A TEXTURE OF ITS OWN —
/// where the engine can write one (frame-composite-draws-each-tile-on-its-
/// own, 2026-10-28).
///
/// A frame's picture, a step's patch, the display buffer and an in-place
/// onion each draw every tile they show, one draw a tile: 🔬S5_BA cut 352,
/// a film of 2381 tiles, 22 ms rastered when the raster thread was free —
/// the cost scaled with the tiles, not the pixels. The same tiles out of
/// one texture, a page's in one `drawAtlas`, were 8.5 ms and the same
/// bytes. So the pictures are slots of shared pages, and a paint lays a
/// page's slots together ([SlotsByPage]).
///
/// ⛔NOT BESIDE THE TILE'S OWN PICTURE. A page of copies is every picture
/// twice — ~150 MB more for that one frame's cels — on the devices with the
/// least to spare (유저 10-24 「쓸데없는 소재를 만들고 싶지 않은 것」). The
/// door writes the bytes straight into the slot instead: 🔬on the Windows
/// app (GLES, profile) 58 µs a tile against 70 µs for the door's own
/// upload of the same tiles, and no texture of the tile's own at any time.
/// (↩️10-29's probe of 400 new tiles read a submit a tile dearer than the
/// door — the writes are submitted together since, below.)
///
/// ⛔NOTHING WAITS FOR THE WRITE. The slot is drawn the moment it is handed
/// out; the GPU takes the write before any draw recorded after it, in its
/// one queue, as it takes the door's own upload
/// (`decodeImageFromPixelsSync`, whose picture is drawn before its upload
/// is done just the same): 🔬a lay drawn right after the writes were
/// submitted was 0 bytes apart from the tile-by-tile lay, on GLES (25
/// films) and on Vulkan.
///
/// 🚨THE WRITES ARE SUBMITTED TOGETHER (2026-10-29): one buffer, one
/// command buffer and one submit for every slot written until something
/// draws one ([_Page.drawn]) or the buffer is full ([_stagingBytes]). A
/// buffer, a command buffer and a submit a tile cost more than the door:
/// on the Surface the first scrub step and the first ink after a flip
/// came later than before the pages; 🔬400 tiles of 128² on the Windows
/// app (GLES, profile), UI thread 40.4 ms a submit a tile, 28.3 the door,
/// 22.0 together. ⛔Not submitted after the frame instead: the raster
/// thread may draw the frame before anything after it runs.
///
/// 🚨★★★A SLOT IS WRITTEN ONCE. A picture recorded earlier — a layer tree
/// on screen, a `toImageSync` not rastered yet — holds the page and draws
/// its slots whenever it is rastered; a slot written again would show it
/// another tile's bytes. So pages only fill, and a page goes when every
/// slot of it is dead and it takes no more ([_Page.release]); the engine
/// keeps its texture for any picture still holding it.
///
/// No page where the engine has no GPU context to write with (the test
/// runner's Skia, Impeller without Flutter GPU, a lost context): the door's
/// own picture stands, as before.
class TilePages {
  TilePages();

  /// The pages every tile picture of the app's caches lies in.
  static final TilePages instance = TilePages();

  /// Bytes of every page alive right now, every [TilePages]' — for the
  /// memory census and the picture budget: a page counts whole, its dead
  /// slots too, until it goes.
  static int get liveBytes => _liveBytes;
  static int _liveBytes = 0;

  /// Bytes of this one's pages alive, counted as [liveBytes] counts them.
  int get bytes => _bytes;
  int _bytes = 0;

  /// The widest a page grows (2048² · 16 MB).
  static const int widestPage = 2048;

  /// The context pages are written with, read once; null where there is
  /// none, or once a write failed.
  gpu.GpuContext? get _gpu {
    if (!_asked) {
      _asked = true;
      try {
        _context = gpu.gpuContext;
      } on Exception {
        _context = null;
      }
    }
    return _context;
  }

  gpu.GpuContext? _context;
  bool _asked = false;

  /// The page each tile size is being written into.
  final Map<int, _Page> _open = {};

  /// The side of the next page of each tile size: four tiles across at
  /// first, doubling to [widestPage], so a small project does not hold a
  /// 16 MB page for a handful of tiles.
  final Map<int, int> _nextSide = {};

  /// Whether this engine writes tile pictures into pages.
  bool get writes => _gpu != null;

  /// [bytes] — a square tile — written into the next slot of a page, or
  /// null where this engine writes no pages.
  TileSlot? write(PictureBytes bytes) {
    final context = _gpu;
    if (context == null) {
      return null;
    }
    final side = bytes.width;
    final length = side * side * 4;
    try {
      final page = _pageWithRoomFor(context, side);
      final across = page.side ~/ side;
      final x = (page.written % across) * side;
      final y = (page.written ~/ across) * side;
      final staging = _stagingFor(context, length);
      final at = _staged;
      // Copied into the buffer here, inside the read — the bytes may be a
      // window onto native memory released when the read returns.
      final copied = bytes.readPremultiplied(
        (premultiplied) => staging.overwrite(
          ByteData.sublistView(premultiplied),
          destinationOffsetInBytes: at,
        ),
      );
      if (!copied) {
        _context = null;
        return null;
      }
      _staged += length;
      (_writes ??= context.createCommandBuffer()).copyBufferToTexture(
        gpu.BufferView(staging, offsetInBytes: at, lengthInBytes: length),
        gpu.TextureRegion(page.texture, x: x, y: y, width: side, height: side),
      );
      page.written += 1;
      page.live += 1;
      return TileSlot._(
        page,
        ui.Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          side.toDouble(),
          side.toDouble(),
        ),
      );
    } on Exception {
      // The context the probe found can no longer write: the door's own
      // pictures for the rest of the run rather than a throw on a paint.
      _context = null;
      return null;
    }
  }

  /// The writes recorded and not submitted yet, and the buffer they copy
  /// from, [_staged] bytes of it filled.
  gpu.CommandBuffer? _writes;
  gpu.DeviceBuffer? _staging;
  int _staged = 0;

  /// The most bytes written and not submitted: 64 tiles of 128².
  static const int _stagingBytes = 4 << 20;

  /// The buffer the next [length] bytes are copied into: the writes' own
  /// while it has room, else a new one, the writes before submitted.
  gpu.DeviceBuffer _stagingFor(gpu.GpuContext context, int length) {
    final staging = _staging;
    if (staging != null && _staged + length <= staging.sizeInBytes) {
      return staging;
    }
    _submitWrites();
    _staged = 0;
    return _staging = context.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      math.max(length, _stagingBytes),
    );
  }

  /// The writes recorded since the last submit, submitted as one — before
  /// anything draws the slots they fill ([_Page.drawn]), so the GPU's one
  /// queue takes them first.
  void _submitWrites() {
    final writes = _writes;
    if (writes == null) {
      return;
    }
    final staging = _staging!;
    _writes = null;
    _staging = null;
    try {
      staging.flush(lengthInBytes: _staged);
      writes.submit();
    } on Exception {
      // As a write that throws: the door's own pictures from here on. The
      // slots these writes filled stay unwritten.
      _context = null;
    }
    _staged = 0;
  }

  _Page _pageWithRoomFor(gpu.GpuContext context, int side) {
    final open = _open[side];
    if (open != null && !open.full) {
      return open;
    }
    open?.close();
    final pageSide =
        _nextSide[side] ?? math.max(side, math.min(side * 4, widestPage));
    _nextSide[side] = math.max(pageSide, math.min(pageSide * 2, widestPage));
    final texture = context.createTexture(
      gpu.StorageMode.devicePrivate,
      pageSide,
      pageSide,
    );
    return _open[side] = _Page(this, texture, pageSide, side);
  }
}

/// One texture of slots, written in order and never again.
class _Page {
  _Page(this._owner, this.texture, this.side, int slotSide)
    : image = texture.asImage(),
      capacity = (side ~/ slotSide) * (side ~/ slotSide),
      _held = side * side * 4 {
    TilePages._liveBytes += _held;
    _owner._bytes += _held;
  }

  final TilePages _owner;
  final gpu.Texture texture;
  final ui.Image image;

  /// [image] to draw: its owner's writes not submitted yet go first.
  ui.Image get drawn {
    _owner._submitWrites();
    return image;
  }

  final int side;
  final int capacity;

  /// Slots written so far — the next one is the slot at this index.
  int written = 0;

  /// Slots written whose tile still holds them.
  int live = 0;

  /// Whether a page takes no more: full, or another opened after it.
  bool _closed = false;

  bool get full => written == capacity;

  /// Bytes the texture holds.
  final int _held;

  void close() {
    _closed = true;
    _goIfDead();
  }

  void release() {
    live -= 1;
    _goIfDead();
  }

  void _goIfDead() {
    if (_closed && live == 0) {
      TilePages._liveBytes -= _held;
      _owner._bytes -= _held;
      DeferredImageDisposer.instance.retire(image);
    }
  }
}

/// Slots laid 1:1 at their origins — a page's together, in one
/// [ui.Canvas.drawAtlas] ([drawInto]).
///
/// 🚨★★★ONLY WHERE THE PAINT CARRIES NO COLOUR MATRIX. 🔬A slot by
/// `drawAtlas` is the bytes of the tile's own picture by `drawImage` at
/// every alpha and every blend a row rides (`srcOver` · `plus` · the
/// float's `dstOut`) on Skia and Impeller — but with a colour matrix and an
/// alpha under 255 Impeller rounds it apart, by 1 (a ghost's tint, the
/// in-place onion's 1,133 pixels). Where one rides, the caller lays each
/// slot by `drawImageRect`, which is `drawImage` of the slot (0 apart).
/// ⛔Not a layer around the atlas: 🔬a layer of a multiply or a screen at
/// alpha 128 is 1 apart itself, on Impeller.
final class SlotsByPage {
  final Map<_Page, ({List<ui.RSTransform> at, List<ui.Rect> from})> _pages =
      Map.identity();

  /// [slot] to lay with its top-left at [origin] — its page's writes left
  /// to submit together when the page is drawn ([drawInto]).
  void add(TileSlot slot, ui.Offset origin) {
    final laid = _pages.putIfAbsent(
      slot._page,
      () => (at: <ui.RSTransform>[], from: <ui.Rect>[]),
    );
    laid.at.add(ui.RSTransform(1, 0, origin.dx, origin.dy));
    laid.from.add(slot.source);
  }

  /// Lays every slot added, a page at a time, in [paint] — and forgets
  /// them.
  void drawInto(ui.Canvas canvas, ui.Paint paint) {
    for (final MapEntry(key: page, value: laid) in _pages.entries) {
      canvas.drawAtlas(
        page.drawn,
        laid.at,
        laid.from,
        null,
        null,
        null,
        paint,
      );
    }
    _pages.clear();
  }
}
