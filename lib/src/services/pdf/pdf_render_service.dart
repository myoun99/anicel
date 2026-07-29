import 'dart:io';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart' as pdfrx;

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

/// One open PDF document: page geometry plus page rendering at whatever
/// pixel size the caller picks (PDF is vector — resolution is a call-site
/// decision, canvas-fit for placement bakes, zoom-tier for the viewer).
abstract class PdfDocumentHandle {
  /// Number of pages (§6-k: 1 page = 1 frame when placed).
  int get pageCount;

  /// Page size in PDF points (1/72 inch); pages of one document can
  /// differ.
  ui.Size pageSize(int pageIndex);

  /// Renders page [pageIndex] to exactly [width]×[height] pixels.
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  });

  /// Releases the native document.
  Future<void> dispose();
}

/// The open seam tests inject fakes through.
typedef PdfDocumentOpener = Future<PdfDocumentHandle> Function(String path);

abstract final class PdfRenderService {
  /// Test seam: when set, [open] routes here and [availability] reads
  /// true — widget tests drive fake documents without any FFI.
  static PdfDocumentOpener? debugOpenerOverride;

  static bool? _availability;
  static Future<bool>? _probe;

  /// The probe's last verdict: null = not probed yet, false = PDFium did
  /// not load (the honest-absence state), true = ready. The runtime path
  /// report reads this without forcing a probe.
  static bool? get availability =>
      debugOpenerOverride != null ? true : _availability;

  /// Probes once per process (the app kicks this at startup so the
  /// System page and the import window have a settled answer). Any
  /// failure means absent — pdfrx has no stable public exception type
  /// for a load failure, so the catch is deliberately broad.
  static Future<bool> ensureAvailable() {
    if (debugOpenerOverride != null) {
      return Future<bool>.value(true);
    }
    return _probe ??= _probeAvailability();
  }

  static Future<bool> _probeAvailability() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      // flutter_tester has no bundled native asset and must never try —
      // the same gate the audio device and video encoder use.
      return _availability = false;
    }
    try {
      await pdfrx.pdfrxFlutterInitialize();
      return _availability = true;
    } on Object {
      return _availability = false;
    }
  }

  /// Opens [path]. Null means the RENDERER is absent; a file that fails
  /// to open (corrupt, password-locked) throws instead — the two states
  /// deserve different messages.
  static Future<PdfDocumentHandle?> open(String path) async {
    final override = debugOpenerOverride;
    if (override != null) {
      return override(path);
    }
    if (!await ensureAvailable()) {
      return null;
    }
    final document = await pdfrx.PdfDocument.openFile(path);
    return _PdfrxDocumentHandle(document);
  }

  static void debugResetForTests() {
    debugOpenerOverride = null;
    _availability = null;
    _probe = null;
  }
}

class _PdfrxDocumentHandle implements PdfDocumentHandle {
  _PdfrxDocumentHandle(this._document);

  final pdfrx.PdfDocument _document;

  @override
  int get pageCount => _document.pages.length;

  @override
  ui.Size pageSize(int pageIndex) {
    final page = _document.pages[pageIndex];
    return ui.Size(page.width, page.height);
  }

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

  @override
  Future<void> dispose() => _document.dispose();
}
