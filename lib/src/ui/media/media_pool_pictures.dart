import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../models/canvas_size.dart';
import '../../models/media_asset.dart';
import '../../native/qa_memory.dart';
import '../../services/composite_effect_paint.dart' show alphaOnly;
import '../../services/media/viewer_document.dart';
import 'shown_rasters.dart';
import 'viewer_raster_budget.dart';

/// Opens [asset] as the viewer does (`openViewerDocument`), or null where
/// this build has nothing that shows it.
typedef MediaPoolOpen = Future<ViewerDocument?> Function(MediaAsset asset);

/// A pooled file's bytes — its path, and the carry named there when it was
/// asked for ([MediaAsset.carry]).
typedef _PoolFile = ({String path, MediaCarry? carry});

/// One picture of a pooled file as held: the file, the page, and the width
/// in pixels of the box it is drawn in.
typedef _PoolPicture = ({String path, MediaCarry? carry, int page, int width});

/// THE PICTURES THE MEDIA POOL'S ICON VIEW DRAWS (🗣️asset-placement-presets
/// Q4 · Q6, 유저 2026-11-17 「프리미어처럼」): each file's page as large as
/// its box, and a movie's or a GIF's frame under the cursor while the
/// cursor crosses it.
///
/// 🚨HELD AS EVERY PICTURE DRAWN AS LARGE AS IT IS SHOWN IS
/// ([ShownRasters] — 유저 10-30 「붙잡는 곳 하나, 크기는 지금처럼 보이는
/// 만큼」): one render at a time, only what is shown now, in one viewer's
/// share of the device, the least recently drawn let go first. What is its
/// own is what it is a view of — a pooled file's page in a 16:10 box — and
/// the files it keeps open to draw them.
///
/// 🚨A picture is of ONE CARRY'S BYTES ([MediaAsset.carry]), as the sheets'
/// images are (`SheetImageCache`): carried anew, a path means other bytes.
///
/// ⛔A file that cannot be opened is remembered and never asked again: the
/// pool asks while it builds, and asking again on every build is a decoder
/// saying no at the frame rate. Its box draws the file's kind; the viewer
/// says why when it is opened there.
class MediaPoolPictures extends ChangeNotifier {
  MediaPoolPictures({required MediaPoolOpen open, this.onHeldBytesChanged})
    : _open = open;

  /// A box's width to its height — 16:10, as the mockup the user approved
  /// draws the icon view's pictures.
  static const double aspect = 16 / 10;

  /// How many files stay open between renders. A cursor crossing a movie
  /// asks it for frame after frame, and opening a decoder for each would
  /// cost more than the frame; two keep the movie under the cursor and the
  /// one it just left, never the whole pool.
  static const int openFiles = 2;

  final MediaPoolOpen _open;

  /// Told whenever what is held changes — the census cannot reach the
  /// workspace (`RenderCaches.viewerRasterBytesByViewer`).
  final void Function(int bytes)? onHeldBytesChanged;

  late final ShownRasters<_PoolPicture, ()> _pictures = ShownRasters(
    budget: _budget,
    // Nothing plays the pool.
    wantedAt: (_) => null,
    lastUsed: (key) => _pictures.usedAt(key),
    rebuild: (change) => change(),
    mounted: () => !_disposed,
    report: (bytes) => onHeldBytesChanged?.call(bytes),
    ended: (_) => notifyListeners(),
  );

  final ViewerRasterBudget _budget = ViewerRasterBudget(
    physicalMemoryBytes: QaMemory.physicalMemoryBytes,
  );

  /// The files open now, the one drawn from last at the end.
  final Map<_PoolFile, ViewerDocument> _documents = {};

  final Set<_PoolFile> _unreadable = {};

  /// The page each file last drew — what its box keeps showing while the
  /// page the cursor moved to renders.
  final Map<_PoolFile, int> _lastPage = {};

  bool _disposed = false;

  /// What the held pictures cost resident, 4 bytes a pixel.
  int get heldBytes => _pictures.heldBytes;

  /// [asset]'s [page] in a box [width] pixels wide: held, or — while it
  /// renders — the page the box last drew, or that page at another width;
  /// null while none is, and for good where the file cannot be opened.
  ui.Image? pictureOf(
    MediaAsset asset, {
    required int page,
    required int width,
  }) {
    final file = (path: asset.path, carry: asset.carry);
    if (_disposed || _unreadable.contains(file)) {
      return null;
    }
    final key = (path: file.path, carry: file.carry, page: page, width: width);
    _pictures.use(key);
    final held = _pictures.imageOf(key);
    if (held != null) {
      _lastPage[file] = page;
      return held;
    }
    _pictures.want(key, (), () => _render(asset, key));
    final last = _lastPage[file];
    return (last == null
            ? null
            : _pictures.imageOf((
                path: file.path,
                carry: file.carry,
                page: last,
                width: width,
              ))) ??
        _pictures.sharpestOf(
          (other) =>
              other.path == file.path &&
              other.carry == file.carry &&
              other.page == page,
        );
  }

  /// [key]'s picture, contained in its box and never past the page's own
  /// pixels where the page is made of them ([ViewerDocument.drawnAtAnySize]).
  Future<ui.Image> _render(MediaAsset asset, _PoolPicture key) async {
    final document = await _documentOf(asset);
    if (document == null || document.pageCount <= 0) {
      throw StateError('${key.path} has no picture to draw');
    }
    final page = math.min(key.page, document.pageCount - 1);
    final own = document.pageSize(page);
    if (own.isEmpty) {
      throw StateError('${key.path} page $page has no size');
    }
    final contained = math.min(
      key.width / own.width,
      key.width / aspect / own.height,
    );
    final at = document.drawnAtAnySize ? contained : math.min(contained, 1.0);
    final CanvasSize(:width, :height) = pagePixelSize(document, page, at: at);
    return document.renderPage(page, width: width, height: height);
  }

  /// [asset]'s file open — kept open, or opened and the one drawn from
  /// least recently closed past [openFiles]. Null where it cannot be.
  ///
  /// Asked only inside a render, and renders run one at a time
  /// ([ShownRasters.want]): a file is never closed under a render.
  Future<ViewerDocument?> _documentOf(MediaAsset asset) async {
    final file = (path: asset.path, carry: asset.carry);
    final kept = _documents.remove(file);
    if (kept != null) {
      _documents[file] = kept;
      return kept;
    }
    ViewerDocument? opened;
    try {
      opened = await _open(asset);
    } on Object {
      opened = null;
    }
    if (opened == null) {
      _unreadable.add(file);
      return null;
    }
    if (_disposed) {
      unawaited(opened.dispose());
      return null;
    }
    _documents[file] = opened;
    while (_documents.length > openFiles) {
      final oldest = _documents.keys.first;
      unawaited(_documents.remove(oldest)!.dispose());
    }
    return opened;
  }

  /// The OS says memory is tight: halve, and give back what no longer fits
  /// ([ViewerRasterBudget]).
  void respondToMemoryPressure() {
    if (_disposed) {
      return;
    }
    final before = _pictures.heldBytes;
    _pictures.heardMemoryPressure();
    if (_pictures.heldBytes != before) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Tells the census nothing is held.
    _pictures.clear();
    for (final document in _documents.values) {
      unawaited(document.dispose());
    }
    _documents.clear();
    super.dispose();
  }
}

/// [image] — a pool picture ([MediaPoolPictures.pictureOf]) — drawn over
/// [onto], [opacity] of it: the icon view's box, and the 배치 프리셋
/// window's canvas, where what overflows it is drawn faint.
///
/// ⛔ONE DRAW for the two. A thumbnail owns its quality on its own paint
/// (`layer_image_draw_contract_test`): resampled smooth, as a picture shown
/// smaller than its pixels is.
void paintPoolPicture(
  ui.Canvas canvas,
  ui.Image image,
  ui.Rect onto, {
  double opacity = 1,
}) => canvas.drawImageRect(
  image,
  ui.Offset.zero & ui.Size(image.width.toDouble(), image.height.toDouble()),
  onto,
  ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..color = alphaOnly(opacity),
);
