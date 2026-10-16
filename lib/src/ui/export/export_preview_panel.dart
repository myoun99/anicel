import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/project_frame_rate.dart';
import '../../services/media/viewer_document.dart';
import '../brush/brush_canvas_panel.dart';
import '../canvas/viewport_pages_painter.dart';
import '../editor_session_manager.dart';
import '../media/document_preview_panel.dart';
import '../media/media_run.dart';
import '../media/page_rasters.dart';
import '../media/viewer_pages_and_run.dart';
import '../media/viewer_sound.dart';
import '../widgets/empty_state_text.dart';
import '../widgets/page_turn_strip.dart';
import '../widgets/transport_bar.dart';
import 'export_preview_document.dart';

/// THE EXPORT WINDOW'S PREVIEW — a canvas-base panel showing the file the
/// window would write.
///
/// 🗣️F-289 (유저 2026-10-06): the preview is the panel the viewer is — its
/// pill (fit, zoom, settings), both scrollbars always, 100% a pixel of the
/// file to a pixel of the screen — and it wears what its document is
/// ([ExportPreviewShape]): 「이 캔버스 베이스패널은 형식에 따라
/// 나누기로하자」. The file's name stands at the picture's lower left
/// whatever the tab (「그냥 제안한대로 동영상뷰어던 뭐던 해당 위치 고정으로
/// 두자」).
///
/// 🚨THE VIEWER'S PAGES AND RUN — the same code, not a second player. The
/// file under preview is a [ViewerDocument] ([ExportPreviewDocument]); its
/// pages are kept by the viewer's cache ([PageRasters]), drawn by the
/// viewer's painter ([ViewportPagesPainter]) and played by the viewer's run
/// ([MediaRun]) — whose wait for a frame that has not landed was written
/// once, there. No sound: a sequence plays silent here.
///
/// ↩️A picture fitted into a well, a scrub bar and two lines of text stood
/// here, each tab's picture rendered to fit one fixed box
/// (`ExportPreviewController`).
class ExportPreviewPanel extends StatefulWidget {
  const ExportPreviewPanel({
    super.key,
    required this.session,
    required this.document,
    required this.page,
    required this.onPage,
    required this.nothingToShow,
    this.range,
    this.fileName,
    this.fileAbsent = false,
    this.enabled = true,
  });

  /// The session the window exports from: the memory census this panel's
  /// pages are counted in, and the warnings they hear.
  final EditorSessionManager session;

  /// The file under preview, or null while the tab has nothing to write.
  final ExportPreviewDocument? document;

  /// The page of it the window stands on.
  final int page;

  /// A hand — or the run — moved to a page.
  final ValueChanged<int> onPage;

  /// What the panel says while there is no document.
  final String nothingToShow;

  /// The span IN/OUT keep, on the one tab that trims.
  final TransportRange? range;

  /// The name the page shown is written under.
  final String? fileName;

  /// Whether [fileName] names a picture the run does not write
  /// ([BrushCanvasPanel.documentAbsent]).
  final bool fileAbsent;

  /// False while an export runs: nothing here turns the picture, which
  /// shows what the run under way is writing.
  final bool enabled;

  @override
  State<ExportPreviewPanel> createState() => ExportPreviewPanelState();
}

class ExportPreviewPanelState extends State<ExportPreviewPanel>
    with TickerProviderStateMixin
    implements MediaRunSurface {
  /// Where this panel's pages are counted in the memory census
  /// (`RenderCaches.viewerRasterBytesByViewer`).
  static const String _censusKey = 'export-preview';

  /// The renders out with the document, for [debugSettle].
  final List<Future<void>> _asks = [];

  late final ViewerPagesAndRun _pagesAndRun = ViewerPagesAndRun(
    surface: this,
    sound: ViewerSound.ofSession(widget.session),
    report: (bytes) =>
        widget.session.renderCaches.viewerRasterBytesByViewer[_censusKey] =
            bytes,
  );
  PageRasters get _rasters => _pagesAndRun.rasters;
  MediaRun get _run => _pagesAndRun.run;

  late int _page = widget.page;

  @override
  void initState() {
    super.initState();
    widget.session.memoryPressureTicks.addListener(_onMemoryPressure);
  }

  @override
  void didUpdateWidget(ExportPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.document;
    final now = widget.document;
    _page = _pageIn(now, widget.page);
    if (was?.subject != now?.subject || was?.look != now?.look) {
      _heardAnother();
    }
    if (!widget.enabled && _run.playing) {
      _run.stop();
    }
  }

  /// The document is another one — another subject, or the same one drawn
  /// another way: nothing of the last is kept, and the panel says it is
  /// loading until a page of this one lands ([_pictureUp]).
  ///
  /// ↩️The same sheet drawn another way kept the picture that was up until
  /// the new one landed — F-315 (유저 2026-10-08) asked for the loading
  /// widget in its place: 「준비안된상태면 지금 이전그림 보여주는데 그게아니라
  /// … 로딩창같은거 해당패널중앙에 위젯 띄우도록」.
  void _heardAnother() {
    _run.stop();
    _rasters.clear();
  }

  @override
  void dispose() {
    widget.session.memoryPressureTicks.removeListener(_onMemoryPressure);
    _run.dispose();
    _rasters.clear();
    widget.session.renderCaches.viewerRasterBytesByViewer.remove(_censusKey);
    super.dispose();
  }

  void _onMemoryPressure() => _rasters.heardMemoryPressure(keeping: _page);

  static int _pageIn(ExportPreviewDocument? document, int page) =>
      document == null || document.pageCount <= 0
      ? 0
      : page.clamp(0, document.pageCount - 1);

  // --- The run's surface ([MediaRunSurface]) -------------------------------

  @override
  TickerProvider get vsync => this;

  @override
  ProjectFrameRate get frameRate =>
      widget.session.projectSettings.projectFrameRate;

  /// The document as the page cache and the run ask it — each render asked
  /// of it remembered until it answers ([debugSettle]).
  @override
  ViewerDocument? get document {
    final shown = widget.document;
    return shown == null ? null : _AskedDocument(shown, _asks);
  }

  @override
  int get page => _page;

  @override
  void turnToPage(int page) {
    final next = _pageIn(widget.document, page);
    if (next == _page) {
      return;
    }
    _page = next;
    widget.onPage(next);
  }

  /// A sequence plays silent here, for now: the design as it was closed on
  /// the card (F-289, 2026-10-06) leaves the preview's sound for later.
  @override
  String? get soundPath => null;

  @override
  ViewerLoudness get loudness => const ViewerLoudness();

  /// Test seam: asks for the page stood on and completes once it has
  /// landed — called inside `tester.runAsync`, where time is real. (A render
  /// asked for under a test's faked clock never answers, so what is out is
  /// turned away and asked again from here.)
  @visibleForTesting
  Future<void> debugSettle() async {
    final scale = _rasters.scale;
    if (widget.document == null || scale == null) {
      return;
    }
    _rasters.turnAway();
    _asks.clear();
    _rasters.ensureRendered(_page, scale);
    while (_asks.isNotEmpty) {
      final out = [..._asks];
      _asks.clear();
      await Future.wait(out);
      // The landing is a turn behind the answer it waits on.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Test seam: the picture drawn, and what stands under it.
  @visibleForTesting
  ({ui.Image? image, bool checkered}) get debugPicture => (
    image: _pictureUp(),
    checkered: widget.document?.opensAlpha ?? false,
  );

  /// The picture that is up: the page stood on, at whatever scale it
  /// landed — and none until it lands, while the panel says it is loading
  /// ([ViewerPageLoading]).
  ///
  /// ↩️Until it landed, the last page drawn stood in for it, so a hand
  /// running along the track saw the last frame that had landed (F-315: a
  /// press on 「다음」 showed the drawing before).
  ui.Image? _pictureUp() => _rasters.imageOf(_page);

  // --- What the panel wears ------------------------------------------------

  /// The page cluster on the left — a book's.
  List<Widget> _pageStrip(ExportPreviewDocument? document) =>
      document == null || document.shape != ExportPreviewShape.book
      ? const []
      : pageTurnStrip(
          keyPrefix: 'export-preview',
          page: viewerPage(_page, document.pageCount),
          onTurnTo: widget.enabled ? turnToPage : null,
        );

  /// The transport under a document that runs — there whatever its length
  /// (a cut of one frame keeps the rows, with nowhere to go).
  CanvasTransportBand? _transport(
    BuildContext context,
    ExportPreviewDocument? document,
  ) {
    if (document == null || document.shape != ExportPreviewShape.runs) {
      return null;
    }
    final rate = widget.session.projectSettings.projectFrameRate;
    final range = widget.range;
    return CanvasTransportBand(
      height: TransportBar.heightIn(context, range: range != null),
      child: AbsorbPointer(
        absorbing: !widget.enabled,
        child: TransportBar(
          keyPrefix: 'export-transport',
          frameCount: document.pageCount,
          currentFrame: _page,
          playing: _run.playing,
          onSeek: (frame) => _run.seekToFrame(frame, rate),
          onPlayPause: widget.enabled && _run.canPlay ? _run.toggle : null,
          range: range,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return DocumentPreviewPanel(
      keyPrefix: 'export-preview',
      pagesAndRun: _pagesAndRun,
      document: document,
      page: _page,
      nothing: _nothing(),
      ground: document?.opensAlpha ?? false
          ? ViewportPageGround.checker
          : ViewportPageGround.none,
      pageStrip: _pageStrip(document),
      transport: _transport(context, document),
      documentName: widget.fileName,
      documentAbsent: widget.fileAbsent,
    );
  }

  /// What the panel says in the picture's place while there is no document.
  Widget _nothing() => Padding(
    padding: const EdgeInsets.all(24),
    child: EmptyStateText(
      widget.nothingToShow,
      key: const ValueKey<String>('export-preview-empty'),
      place: EmptyStatePlace.stage,
    ),
  );
}

/// A document as it is ASKED: every render asked of it is remembered until
/// it answers, so a test can wait for the pictures
/// ([ExportPreviewPanelState.debugSettle]).
class _AskedDocument implements ViewerDocument {
  const _AskedDocument(this._document, this._asks);

  final ExportPreviewDocument _document;
  final List<Future<void>> _asks;

  @override
  int get pageCount => _document.pageCount;

  @override
  double? get framesPerSecond => _document.framesPerSecond;

  @override
  ui.Size pageSize(int pageIndex) => _document.pageSize(pageIndex);

  @override
  bool get drawnAtAnySize => _document.drawnAtAnySize;

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) {
    final render = _document.renderPage(
      pageIndex,
      width: width,
      height: height,
    );
    final asked = render.then<void>((_) {}, onError: (Object _) {});
    _asks.add(asked);
    unawaited(asked.whenComplete(() => _asks.remove(asked)));
    return render;
  }

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => _document.readRegionRgba(pageIndex, box);

  @override
  Future<void> dispose() => _document.dispose();
}
