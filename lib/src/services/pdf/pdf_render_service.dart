import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../core/made_once.dart';
import '../../core/progress_share.dart';
import '../../models/kept_span.dart';
import '../flutter_test_run.dart';
import '../media/media_byte_source.dart';
import '../media/viewer_document.dart';

/// The PDF rasterizer seam (R4). PDFium arrives through pdfrx's build-time
/// native assets, and unlike the raster/audio engines there is NO Dart
/// reference to fall back to (`pdf` the package is writer-only) — so
/// absence is a visible state, not a degraded path: the importer and the
/// media viewer say "no PDF renderer" instead of pretending. Image
/// viewing never routes through this seam.
///
/// Test doctrine: flutter_tester must never touch the FFI plugin, so
/// under FLUTTER_TEST the service reports absent unless a test injects
/// [PdfRenderService.debugOpenerOverride] — the media viewer and import
/// tests drive a fake document through that seam.

/// 🪦PDF used to declare its own `PdfDocumentHandle` with these four
/// members. It was [ViewerDocument] under another name — one open
/// document, page geometry, render-at-a-size, dispose — so the viewer
/// could not treat an image the way it treats a page without writing the
/// shape a second time. The shape moved out; PDF is now one implementer
/// of it, which is what 「최대한 통일」 (유저 2026-08-29) asks for.
///
/// PDF is vector, so resolution is a call-site decision: canvas-fit for
/// placement bakes, zoom-tier for the viewer.

/// One window PDFium asked for, out of [reader]: ALL of it, or 0.
///
/// 🚨PDFium takes ANY non-zero answer for success, and pdfrx hands it -1
/// when a read throws — so a failed or short read became a page drawn from
/// whatever the buffer held. PDFium asks only within the file's length, so
/// anything short of the whole window is a failure, and 0 is the one answer
/// it reads as one (audit 2026-09-24).
Future<int> readPdfWindow(
  MediaWindowReader reader,
  Uint8List buffer,
  int position,
  int size,
) async {
  try {
    final got = await reader.readInto(buffer, position, size);
    return got == size ? got : 0;
  } on Object {
    return 0;
  }
}

/// How far PDFium has read a file while it OPENS it, told as a share of the
/// file — F-608-Q2's 「the bytes read of the bytes to read」, the decoder's
/// own reads counted (🗣️유저 11-23 「pdf읽기는 퍼센트 안들어간단게 뭐야 …
/// 당연히 넣어야하는거아니야?」).
///
/// 🔬Why the open, and why the whole file (저장 11-24, PDFium through
/// pdfrx 2.4.7, four PDFs of 5–141 MB — a conte, a manga volume, notes):
/// opening read 100.0–101.4% of each file, and a page rendered after it
/// read a few KB — so the open IS the read, and what a page reads later is
/// its rasterizing's. Re-reads are counted as read; the share stops at the
/// whole.
final class PdfOpeningReads {
  PdfOpeningReads(this._length, this._onRead);

  final int _length;
  final void Function(double fraction)? _onRead;
  int _read = 0;
  bool _opened = false;

  /// [got] more bytes read — told only while the document is opening.
  void took(int got) {
    if (_opened || got <= 0) {
      return;
    }
    _read += got;
    _onRead?.call(math.min<double>(1, doneShare(_read, _length)));
  }

  /// The document is open: what it reads from here on is a page's.
  void opened() => _opened = true;
}

/// A test opener that also hears how far the file is read ([PdfRenderService
/// .open]'s onRead) — set as [PdfRenderService.debugOpenerOverride], it
/// stands for PDFium telling its reads.
typedef PdfReadingOpener =
    Future<ViewerDocument> Function(
      MediaByteSource source, {
      void Function(double fraction)? onRead,
    });

abstract final class PdfRenderService {
  /// Test seam: when set, [open] routes here and [availability] reads
  /// true — widget tests drive fake documents without any FFI.
  static ViewerDocumentOpener? debugOpenerOverride;

  /// The probe, and its verdict once it has one ([MadeOnce]).
  static MadeOnce<bool> _probe = MadeOnce();

  /// The probe's last verdict: null = not probed yet, false = PDFium did
  /// not load (the honest-absence state), true = ready. The runtime path
  /// report reads this without forcing a probe.
  static bool? get availability =>
      debugOpenerOverride != null ? true : _probe.orNull;

  /// Probes once per process (the app kicks this at startup so the
  /// System page and the import window have a settled answer). Any
  /// failure means absent — pdfrx has no stable public exception type
  /// for a load failure, so the catch is deliberately broad.
  static Future<bool> ensureAvailable() {
    if (debugOpenerOverride != null) {
      return Future<bool>.value(true);
    }
    return _probe.of(_probeAvailability);
  }

  static Future<bool> _probeAvailability() async {
    if (underFlutterTest) {
      // flutter_tester has no bundled native asset and must never try —
      // the same gate the audio device and video encoder use.
      return false;
    }
    try {
      await pdfrx.pdfrxFlutterInitialize();
      return true;
    } on Object {
      return false;
    }
  }

  /// Opens the PDF [source] holds, [onRead] told how far the file is read
  /// while it opens ([PdfOpeningReads]). Null means the RENDERER is absent;
  /// a file that fails to open (corrupt, password-locked) throws instead —
  /// the two states deserve different messages.
  ///
  /// Every PDF is served a window at a time, through a reader that keeps
  /// its file open for as long as the document is
  /// ([MediaByteSource.openWindowReader]): a hundred-page conte is never
  /// pulled whole, and never unpacked to a temp file (유저 2026-08-27
  /// 「사본 남으면 진짜 용서안할게」).
  ///
  /// ↩️A user's own file was PDFium's to read by its path — where the
  /// window could not see it read, so a PDF on the cloud stood at one
  /// number while it came down (decoder-reads-skip-the-percent). One
  /// reader for every PDF now; 🔬its open took 0.33 s where the path's
  /// took 0.10–0.18 s for 141 MB read warm (저장 11-24), the price of
  /// reading off the UI isolate ([MediaWindowReader.readInto]).
  static Future<ViewerDocument?> open(
    MediaByteSource source, {
    void Function(double fraction)? onRead,
  }) async {
    final override = debugOpenerOverride;
    if (override is PdfReadingOpener) {
      return override(source, onRead: onRead);
    }
    if (override != null) {
      return override(source);
    }
    if (!await ensureAvailable()) {
      return null;
    }
    return _PdfrxDocumentHandle(await _openWindowed(source, onRead));
  }

  /// [source] opened on a reader that keeps its file open for the
  /// document's whole life ([MediaByteSource.openWindowReader]) — closed
  /// when the document is, or at once when it never opens.
  static Future<pdfrx.PdfDocument> _openWindowed(
    MediaByteSource source,
    void Function(double fraction)? onRead,
  ) async {
    final length = source.lengthSync();
    final reads = PdfOpeningReads(length, onRead);
    final reader = source.openWindowReader();
    try {
      final document = await pdfrx.PdfDocument.openCustom(
        read: (buffer, position, size) async {
          final got = await readPdfWindow(reader, buffer, position, size);
          reads.took(got);
          return got;
        },
        fileSize: length,
        sourceName: '$source',
        onDispose: reader.close,
      );
      reads.opened();
      return document;
    } on Object {
      reader.close();
      rethrow;
    }
  }

  /// Test seam for [pagesKept]'s pages, for the same reason as
  /// [debugOpenerOverride]: flutter_tester never loads PDFium. The pages are
  /// counted through [open], as the fake documents are.
  static Future<Uint8List?> Function(String path, int first, int count)?
  debugPageSpanOverride;

  /// The pages [keep] answers for out of [path]'s page count, as a PDF of
  /// their own — what a trimmed PDF is carried as (유저 2026-09-23: 자른
  /// 구간만 품는다, 「비디오든 이미지든 오디오든 관계없이 법 하나로」) —
  /// and the span they are. Null when the renderer is absent, or [keep]
  /// keeps nothing.
  ///
  /// The file is opened ONCE, [onRead] told how far PDFium read it as it
  /// opened ([PdfOpeningReads]): the cut's own share of the window's
  /// percent. ↩️It was opened twice — once to count its pages, once to cut
  /// them — each read of the whole file unseen by the window
  /// (decoder-reads-skip-the-percent, 11-24).
  ///
  /// ⚠️The pages are PDFium's own objects moved into a new document, never
  /// pictures of them: a conte page stays vector, and a page that renders
  /// sharp at any zoom in the original renders sharp in its piece.
  static Future<({Uint8List bytes, KeptSpan kept})?> pagesKept(
    String path,
    KeptSpan? Function(int pageCount) keep, {
    void Function(double fraction)? onRead,
  }) async {
    final override = debugPageSpanOverride;
    if (override != null) {
      return _pagesKeptByTheSeams(path, keep, override, onRead);
    }
    if (!await ensureAvailable()) {
      return null;
    }
    final source = await _openWindowed(MediaFileBytes(path), onRead);
    try {
      final kept = keep(source.pages.length);
      if (kept == null) {
        return null;
      }
      final piece = await pdfrx.PdfDocument.createNew(sourceName: path);
      try {
        piece.pages = source.pages.sublist(kept.first, kept.first + kept.count);
        // Encoding assembles the piece first, while [source] — whose pages
        // it is borrowing — is still open.
        return (bytes: await piece.encodePdf(), kept: kept);
      } finally {
        await piece.dispose();
      }
    } finally {
      await source.dispose();
    }
  }

  /// [pagesKept] with no PDFium: the pages counted by the test opener
  /// ([open]), cut by [cut] ([debugPageSpanOverride]).
  static Future<({Uint8List bytes, KeptSpan kept})?> _pagesKeptByTheSeams(
    String path,
    KeptSpan? Function(int pageCount) keep,
    Future<Uint8List?> Function(String path, int first, int count) cut,
    void Function(double fraction)? onRead,
  ) async {
    final document = await open(MediaFileBytes(path), onRead: onRead);
    if (document == null) {
      return null;
    }
    final int pages;
    try {
      pages = document.pageCount;
    } finally {
      await document.dispose();
    }
    final kept = keep(pages);
    if (kept == null) {
      return null;
    }
    final bytes = await cut(path, kept.first, kept.count);
    return bytes == null ? null : (bytes: bytes, kept: kept);
  }

  static void debugResetForTests() {
    debugOpenerOverride = null;
    debugPageSpanOverride = null;
    _probe = MadeOnce();
  }
}

class _PdfrxDocumentHandle implements ViewerDocument {
  _PdfrxDocumentHandle(this._document);

  final pdfrx.PdfDocument _document;

  @override
  int get pageCount => _document.pages.length;

  /// A PDF never turns its own pages.
  @override
  double? get framesPerSecond => null;

  @override
  ui.Size pageSize(int pageIndex) {
    final page = _document.pages[pageIndex];
    return ui.Size(page.width, page.height);
  }

  @override
  bool get drawnAtAnySize => true;

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    final page = _document.pages[pageIndex];
    // width/height are the output pixels, fullWidth/fullHeight the full-
    // page raster size — passing both the same renders the whole page at
    // that size. The native work runs on pdfrx's own worker isolate.
    final rendered = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (rendered == null) {
      throw StateError('PDF page render was cancelled.');
    }
    try {
      return await rendered.createImage();
    } finally {
      rendered.dispose();
    }
  }

  /// A PDF renders a BOX natively: the page raster is virtual, and only
  /// the box's pixels are made.
  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) async {
    final page = _document.pages[pageIndex];
    final rendered = await page.render(
      x: box.left,
      y: box.top,
      width: box.width,
      height: box.height,
      fullWidth: page.width,
      fullHeight: page.height,
    );
    if (rendered == null) {
      throw StateError('PDF page render was cancelled.');
    }
    final ui.Image image;
    try {
      image = await rendered.createImage();
    } finally {
      rendered.dispose();
    }
    try {
      return await cropImageRgba(
        image,
        (left: 0, top: 0, width: box.width, height: box.height),
      );
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> dispose() => _document.dispose();
}
