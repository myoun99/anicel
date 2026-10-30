import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../native/qa_native_engine.dart';
import '../../services/media/held_viewer_document.dart';
import '../../services/media/image_viewer_document.dart';
import '../../services/media/media_byte_source.dart' show HoldMediaBytes;
import '../../services/media/viewer_document.dart';
import '../media/shown_rasters.dart';
import '../media/viewer_raster_budget.dart';

/// What a sheet asks for a media image while it paints — the logo, a
/// cover's picture, a photo on its ink (I-97): [assetPath]'s picture
/// [width] pixels wide, or at its own size where [width] is null. Null
/// while it is still to come, and for good where it cannot be read.
typedef SheetImageLookup = ui.Image? Function(String assetPath, {int? width});

/// How a sheet's media image is read: [path]'s picture [width] pixels wide
/// — its own width where null — or null where it cannot be read
/// ([readSheetImage]).
typedef SheetImageRead = Future<ui.Image?> Function(String path, int? width);

/// One sheet media image's place among those held: its path, and the
/// width it was read at (null: its own).
typedef _SheetImageKey = ({String path, int? width});

/// [path]'s picture as [hold] answers for it — a still, a GIF's first
/// frame, a PSD's composite ([ImageViewerDocument.open]) — decoded [width]
/// pixels wide and never wider than the file, its own width where null; or
/// null where it cannot be read: a file that went away is not an error the
/// user can act on from a sheet, which prints the empty box.
///
/// ⛔ONE READER for the images a sheet prints — the logo, a 도장, a cover
/// picture, a photo — on screen and in every export. (The envelope's cache
/// once decoded its own first frame beside the sheets' reader, and never
/// learned the PSD detour.)
///
/// 🚨★★★THE CARRIED COPY WINS — `openViewerDocument`'s law, 「품은 순간
/// 데이터를 가지고있고 불변이었으면좋겠어서」 (유저 2026-08-30) — through the
/// viewer's own door ([openHeldViewerDocument]). 🪦The sheets read the
/// ORIGINAL file (`readImageFileOrNull`): an original edited or deleted
/// after the import changed the logo and the photos the sheets printed,
/// while the viewer went on showing the copy (found 2026-10-15, I-97).
Future<ui.Image?> readSheetImage(
  HoldMediaBytes hold,
  String path,
  int? width,
) => _readSheetPicture(hold, path, (document) {
  final own = document.pageSize(0);
  final ownWidth = math.max(1, own.width.round());
  final read = math.max(1, math.min(width ?? ownWidth, ownWidth));
  return document.renderPage(
    0,
    width: read,
    height: math.max(1, (own.height * read / ownWidth).round()),
  );
});

/// [read] on [path]'s picture as [hold] answers for it, the document
/// closed after; null where it cannot be read ([readSheetImage]).
Future<T?> _readSheetPicture<T extends Object>(
  HoldMediaBytes hold,
  String path,
  Future<T> Function(ViewerDocument document) read,
) async {
  try {
    final document = await openHeldViewerDocument(
      hold,
      path,
      ImageViewerDocument.open,
    );
    if (document == null) {
      return null;
    }
    try {
      return await read(document);
    } finally {
      await document.dispose();
    }
  } on Object {
    return null;
  }
}

/// The media images the sheets print — the logo (the conte's body pages and
/// the envelope), the conte's cover picture, the photos on the sheets' ink
/// (I-97) — read through the project ([readSheetImage]) as large as a sheet
/// shows them.
///
/// 🚨THE PAINTER ASKS SYNCHRONOUSLY. A sheet painter's `imageFor` returns a
/// `ui.Image?` right now — it is inside a paint pass and cannot await — so
/// a picture it has never seen answers null, the read runs off to the side,
/// and the cache NOTIFIES when it lands. A painter hands it to its
/// `repaint`: its compared inputs do not change when a picture lands, so
/// nothing else would bring the frame back. ↩️It used to call back into
/// the workspace, which rebuilt everything — and the painters, seeing equal
/// inputs, did not repaint: a logo showed only after the next pan.
///
/// ⛔A path that cannot be read is remembered, at every width. Read again
/// on every paint it would read the disk on every frame and never succeed;
/// what was read of it before still shows.
///
/// 🚨★★AS LARGE AS SHOWN, ONE READ AT A TIME, IN A BUDGET (I-97, 10-15). A
/// photo asks for the width its sheet draws it at — the viewer's ladder over
/// the file (`paintSheetPhotos`, 「화면이 필요한 만큼(최대 원본)」) — so a zoom
/// asks for new widths, and one not in yet shows the sharpest held of the
/// same picture. A read only puts the ask on a list; one runs, and when it
/// ends the list goes and the sheets ask again for what they show NOW (the
/// storyboard's 2026-09-28 crash: every step of a zoom asked every picture
/// on screen at once). What is held is one viewer's share of the device
/// ([ViewerRasterBudget]), the least recently asked let go first.
/// ↩️It decoded every file WHOLE and kept it for the life of the window,
/// for 「a handful」 of logos — a photo of 8000×6000 is 192MB whole, drawn
/// in a cell a few hundred pixels wide.
///
/// ↩️THE SECOND OF ITS KIND until 10-30: `StoryboardCutThumbnailStore`
/// listed, ran and stood in the same way, and the rule of three (CLAUDE.md
/// 절대명령 1) waited for a third. The viewer's pages were it, when the
/// panels moved onto how they are held (유저 10-30 「붙잡는 곳 하나」): all
/// three are held by [ShownRasters] now.
class SheetImageCache extends ChangeNotifier {
  SheetImageCache({required SheetImageRead read, this.onHeldBytesChanged})
    : _read = read;

  final SheetImageRead _read;

  /// Told whenever [decodedBytes] changes, so the census can reach a cache
  /// that lives in the workspace — the storyboard store's shape.
  final void Function(int bytes)? onHeldBytesChanged;

  /// What is held — let go past the budget the least recently asked for
  /// first ([ShownRasters.use]), never the one just read. A file read whole
  /// has one look, so a picture held is a picture ready.
  late final ShownRasters<_SheetImageKey, ()> _images = ShownRasters(
    budget: _budget,
    // Nothing plays the sheets.
    wantedAt: (_) => null,
    lastUsed: (key) => _images.usedAt(key),
    rebuild: (change) => change(),
    mounted: () => !_disposed,
    report: (bytes) => onHeldBytesChanged?.call(bytes),
    ended: notifyListeners,
  );

  /// Paths that could not be read — never asked for again.
  final Set<String> _unreadable = {};

  bool _disposed = false;

  /// One viewer's share of this device, halved by the memory warning.
  final ViewerRasterBudget _budget = ViewerRasterBudget(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
  );

  /// What the held images cost resident, 4 bytes a pixel.
  int get decodedBytes => _images.heldBytes;

  /// [assetPath]'s picture [width] pixels wide (its own size where null):
  /// held, or the sharpest held of it at another width while that one is
  /// read — null when none is.
  ui.Image? imageFor(String assetPath, {int? width}) {
    if (_disposed) {
      return null;
    }
    final key = (path: assetPath, width: width);
    // Asked for: to the young end of the order things are let go in.
    _images.use(key);
    final held = _images.imageOf(key);
    if (held != null) {
      return held;
    }
    if (!_unreadable.contains(assetPath)) {
      _images.want(key, (), () => _readOrUnreadable(key));
    }
    return _images.sharpestOf((other) => other.path == assetPath);
  }

  /// [key]'s picture. One that cannot be read — null, or a read that threw
  /// — marks its path, and is refused like a page the viewer cannot have:
  /// what was read of the path before still shows. A read that threw is
  /// reported, rather than lost behind the refusal.
  Future<ui.Image> _readOrUnreadable(_SheetImageKey key) async {
    final ui.Image? image;
    try {
      image = await _read(key.path, key.width);
    } on Object catch (error, stack) {
      _unreadable.add(key.path);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'sheet images',
          context: ErrorDescription('reading the sheet image ${key.path}'),
        ),
      );
      rethrow;
    }
    if (image == null) {
      _unreadable.add(key.path);
      throw StateError('${key.path} cannot be read');
    }
    return image;
  }

  /// The OS says memory is tight: halve, never below one viewer page, and
  /// give back what no longer fits — see [ViewerRasterBudget].
  void respondToMemoryPressure() {
    if (_disposed) {
      return;
    }
    final before = _images.heldBytes;
    _images.heardMemoryPressure();
    if (_images.heldBytes != before) {
      // A sheet still showing what went asks again — or for a stand-in.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Tells the census nothing is held.
    _images.clear();
    super.dispose();
  }
}

/// The media images ONE export render prints, read for it: a sheet paints
/// once to say what it asks for ([imageFor] lists it), those are read, and
/// it paints again with them in hand ([paintWithSheetImages]).
///
/// 🚨★★★THE SHEET SAYS WHICH, AND HOW LARGE. The width a photo is read at
/// is the painter's own answer for the pixels it draws it at — the screen's
/// ([SheetImageCache]) — so the file samples a photo as the sheet on screen
/// does at the same size (유저 2026-09-17: 「보이는 중이랑 결과랑 절대로
/// 다르면 안 되」). ↩️The exports read every file whole beside the painter,
/// and named what to read by walks of their own: the envelope's walked the
/// photos only, so its logo and 도장 never printed (card
/// `envelope-export-lacks-images`).
class SheetImageRun {
  SheetImageRun(this._read);

  final SheetImageRead _read;

  /// What has been read, by what was asked — null where it could not be.
  final Map<_SheetImageKey, ui.Image?> _pictures = {};

  /// What was asked for and is not read yet.
  final Set<_SheetImageKey> _asked = {};

  /// [assetPath]'s picture [width] pixels wide (its own size where null)
  /// once it is read ([readAsked]); until then null, and asked for.
  ui.Image? imageFor(String assetPath, {int? width}) {
    final key = (path: assetPath, width: width);
    if (_pictures.containsKey(key)) {
      return _pictures[key];
    }
    _asked.add(key);
    return null;
  }

  /// Reads what was asked for, one at a time.
  Future<void> readAsked() async {
    final asked = [..._asked];
    _asked.clear();
    for (final key in asked) {
      _pictures[key] = await _read(key.path, key.width);
    }
  }

  /// Lets go of everything read.
  void dispose() {
    for (final image in _pictures.values) {
      image?.dispose();
    }
    _pictures.clear();
    _asked.clear();
  }
}

/// [paint] on [canvas] with every image it asks [images] for in hand:
/// painted once aside to list them, those read ([SheetImageRun.readAsked]),
/// and painted again. A paint that asks for none is drawn from the first
/// pass — painting it twice would be work for the same picture — and where
/// there are no [images] at all it is painted once, with none.
///
/// ⚠️A paint asks for the same images whatever it is handed: a width is
/// worked out from where a picture lies, never from the image it gets.
Future<void> paintWithSheetImages(
  ui.Canvas canvas,
  SheetImageRun? images,
  void Function(ui.Canvas canvas) paint,
) async {
  if (images == null) {
    paint(canvas);
    return;
  }
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final first = recorder.endRecording();
  try {
    if (images._asked.isEmpty) {
      canvas.drawPicture(first);
      return;
    }
  } finally {
    first.dispose();
  }
  await images.readAsked();
  paint(canvas);
}
