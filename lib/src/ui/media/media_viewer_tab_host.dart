import '../widgets/empty_state_text.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/identity_memo.dart';
import '../../core/page_stack.dart';
import '../../models/app_input_settings.dart' show CanvasTouchDragAction;
import '../../models/canvas_shape_kind.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_piece.dart' show CutPiece;
import '../../models/rgba_image_bytes.dart';
import '../../models/canvas_viewport.dart';
import '../../models/media_asset.dart';
import '../../native/qa_native_engine.dart';
import '../../services/media/held_viewer_document.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/viewer_document.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/cut_piece_lift.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/project_lookup.dart' show mediaKindCanCarrySound;
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/canvas_book.dart';
import '../brush/brush_tool_state.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../editor_session_manager.dart';
import '../playback/playback_transport.dart';
import '../dialogs/open_file_flow.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import 'media_asset_drag_data.dart';
import 'media_asset_drop_target.dart';
import 'media_run.dart';
import 'open_viewer_document.dart';
import 'page_rasters.dart';
import 'viewer_raster_budget.dart';
import 'viewer_render_tier.dart';
import 'viewer_sound.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/page_turn_strip.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import '../widgets/cursor_notice.dart' show cursorNotices;
import '../listenable_rebind.dart';
import '../sliced_value_listenable_builder.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart' show ByList;

/// What the media viewer is looking at. Owned by the workspace (the
/// dockable-panel view-state rule) so the choice survives tab switches
/// and re-docking.
class MediaViewerRequest {
  const MediaViewerRequest({required this.path, required this.kind, this.name});

  final String path;
  final MediaAssetKind kind;

  /// Display name (the asset's); null falls back to the file name.
  final String? name;

  String get displayName => name ?? mediaFileName(path);
}

/// ONE viewer's whole state, owned by the workspace: what it looks at,
/// how far into that document, and where the view sits.
///
/// Two of these exist — the floor's viewer and the sub viewer beside the
/// drawing — and they share NOTHING. Opening a reference in one must
/// never change what the other is showing, which is the entire reason
/// there are two.
class MediaViewerSlot {
  final ValueNotifier<MediaViewerRequest?> request = ValueNotifier(null);

  /// See [MediaViewerTabHost.position] — one slot, whatever the kind.
  final ValueNotifier<int> position = ValueNotifier(0);

  final ValueNotifier<CanvasViewport?> viewport = ValueNotifier(null);

  /// WHICH DOCUMENT the [viewport] above was framed for.
  ///
  /// 🚨★★★It lives up here for the same reason the viewport does. The
  /// reframe used to be keyed on the host State's own load counter, so
  ///「문서 하나당 한 번」 was really 「로드 하나당 한 번」 — and closing the
  /// panel destroys the State, so REOPENING was a new load and the fit ran
  /// again over a view the user had set (유저 2026-08-27: 「확대해두고 패널
  /// 닫고 다시열면 초기화되있음 … 다시 열었을때 이전 배율 그대로 있었다가,
  /// fit으로 초기화되」).
  ///
  /// ⛔A panel-local memory cannot answer 「have I already framed this
  /// document?」, because the panel is exactly what goes away. The slot is
  /// what survives, so the slot is what remembers.
  final ValueNotifier<Object?> framedFor = ValueNotifier(null);

  /// Points this viewer at a document. The position goes back to the
  /// start, because "page 37" of the file you just left means nothing in
  /// the one you just opened.
  ///
  /// A SWAP deliberately does not come through here — it carries each
  /// file's own page across with it (see [swapWith]).
  void open(MediaViewerRequest? next) {
    request.value = next;
    position.value = 0;
  }

  /// Puts back a document the project remembered, at the page it
  /// remembered — the one path that sets a request WITHOUT going back to
  /// the start. Null empties the viewer, which is what a reference the
  /// app can no longer reach comes back as (유저 확정 ⑭: quietly).
  void restore(MediaViewerRequest? request, {int position = 0}) {
    this.request.value = request;
    this.position.value = request == null || position < 0 ? 0 : position;
  }

  /// Trades documents with the other viewer: 유저 확정 ⑪⑯⑰ — the verb is
  /// SWAP and it has no special cases, so trading with an empty viewer
  /// leaves this one empty. A button whose result depends on what the
  /// other side happens to hold is a button nobody can predict.
  ///
  /// The page travels WITH its file (page 37 of the conte is still page
  /// 37 when it lands on the floor). The viewport does not: the two
  /// panels are different widths, so each re-frames what arrives.
  void swapWith(MediaViewerSlot other) {
    final request = this.request.value;
    final position = this.position.value;
    this.request.value = other.request.value;
    this.position.value = other.position.value;
    other.request.value = request;
    other.position.value = position;
  }

  void dispose() {
    request.dispose();
    position.dispose();
    viewport.dispose();
    framedFor.dispose();
  }
}

/// The media viewer PANEL (§6-h, absorbing backlog 11's image viewer):
/// any browsable file — registered asset or one picked on the spot —
/// inside the canvas panel shell, so navigation is the drawing canvas's
/// (wheel zoom, middle-drag pan, panbars, Fit). Images decode once
/// through the import codec; PDFs render LAZILY, the visible page at the
/// current zoom tier (§6-m — a 100-page conte must never pre-render for
/// viewing). No PDF renderer is a stated condition on screen, never a
/// blank page — and images never route through the PDF engine.
///
/// 🗣️I-14 (유저 2026-09-11): one finger PANS here, and the cut tool CUTS
/// here — at the page's own size, into the piece the canvas stamps.
class MediaViewerTabHost extends StatefulWidget {
  const MediaViewerTabHost({
    super.key,
    required this.viewerId,
    required this.session,
    required this.request,
    required this.position,
    this.onRequestPicked,
    this.onSwapViewers,
    this.onRegisterAsset,
    this.isPathRegistered,
    this.onAssetDropped,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.framedFor,
    this.filePicker,
    this.sound,
    this.brushTool,
    this.cutPieceSlot,
  });

  /// WHICH viewer this is — the panel's tab id, and the prefix every
  /// widget key in here is built from.
  ///
  /// 🚨 Required, and never spell a key literally below. The app mounts
  /// more than one of these at once (the floor's viewer and the sub
  /// viewer beside the drawing), and a hardcoded key would have both
  /// instances answering the same `find.byKey` — one test finding two
  /// widgets, and no way to say which viewer a test means.
  final String viewerId;

  final EditorSessionManager session;

  /// The workspace-owned "what to view" signal. EVERY open lands here —
  /// a browser double-click, a dropped row, a swap, and the panel's own
  /// file button through [onRequestPicked]. The panel used to keep a
  /// loose file in its own State and prefer it over this one; that made
  /// the panel's own choice the one thing the workspace could neither
  /// remember across a rebuild nor hand to the other viewer.
  final ValueListenable<MediaViewerRequest?> request;

  /// How far into the document — the page of a PDF, the frame of an
  /// animated image. ONE slot, deliberately: a video's paused position
  /// belongs in this same field when video arrives, with only its unit
  /// (a tick rather than a page) decided then. The KIND already says how
  /// to read it.
  ///
  /// Owned above the panel, like the viewport, because a rail group the
  /// user folds away unmounts the panel inside it — and coming back to
  /// page 1 of a hundred-page conte is not "where I was".
  ///
  /// The OBJECT, not a value and a callback: in a document read as a book
  /// (F-201 — a PDF, a picture) it is the page the reader is on, which
  /// the panel keeps true to the view ([CanvasBook]) — writing it turns
  /// to the page, and the view moving writes it back. One object, for
  /// the reason the viewport is one ([BrushCanvasPanel.viewportController]).
  final ValueNotifier<int> position;

  /// Where the panel's own file button puts its answer. Null hides that
  /// button: a viewer with nowhere to put the reply should not ask.
  final ValueChanged<MediaViewerRequest>? onRequestPicked;

  /// Trades documents with the OTHER viewer (유저 확정 ⑪): same button on
  /// both sides, because swapping is symmetric.
  final VoidCallback? onSwapViewers;

  /// Adds the file being viewed to the media pool (유저 확정 ⑱), through
  /// whatever the app's one import does. Offered only for a file that is
  /// not in the pool yet — [isPathRegistered] answers that.
  ///
  /// The point of the button: a loose path is remembered as an absolute
  /// path and breaks on another machine, while a pooled one travels with
  /// the project. This is how a person promotes the first into the
  /// second without going back to the browser to find the file again.
  final ValueChanged<String>? onRegisterAsset;
  final bool Function(String path)? isPathRegistered;

  /// A media-browser row dropped on this panel (유저 확정 ⑬).
  final ValueChanged<MediaAssetDragData>? onAssetDropped;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;

  /// [MediaViewerSlot.framedFor] — the document this viewer's stored view was
  /// framed for. Null in hosts that own no slot; then every load frames, which
  /// is the old behaviour and correct when there is nothing to preserve.
  final ValueNotifier<Object?>? framedFor;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Injectable loose-file picker (tests).
  final Future<String?> Function()? filePicker;

  /// Injectable sound (tests) — the same seam as [filePicker].
  ///
  /// 🚨★★★**WITHOUT THIS THE SOUND HALF IS UNMEASURED.** A widget test
  /// never gets an audio device (`audioOutputUnlessTesting`), so every
  /// call this panel makes into [ViewerSound] is a no-op on the bench:
  /// deleting the hold, the resume or the stop leaves the whole suite
  /// green. That is not 「no test was needed」, it is 「the bench cannot
  /// see it」 — and this is the door that lets it.
  final ViewerSound? sound;

  /// The workspace's tool, read for ONE thing: whether the cut tool is
  /// armed, and with which outline ([armedCutShape]) — sliced, so a brush's
  /// size or colour never rebuilds this panel.
  ///
  /// 🗣️I-14 (유저 2026-09-11): 「뷰어패널의 잘라내기툴 사용 가능하도록」 —
  /// and the viewer has no drawing (「뷰어패널은 기본적으로 드로잉모드
  /// 존재안하니」), so the cut is the one tool with anything to do here.
  final ValueListenable<BrushToolState>? brushTool;

  /// Where a cut from this viewer lands — the cut tool's one held piece,
  /// the slot the canvas's cuts fill too. Null offers no cut.
  ///
  /// ⛔Not handed to the panel below: a mounted canvas panel installs its
  /// paste-at-origin into the slot, and the viewer has no cel to paste on.
  final CutPieceSlot? cutPieceSlot;

  @override
  State<MediaViewerTabHost> createState() => _MediaViewerTabHostState();
}

/// In the place of a document let go of while a save replaces its file
/// (`_MediaViewerTabHostState._letGoThenFollow`): the page on screen keeps
/// its size and the document its page count — so nothing on screen moves —
/// and nothing is read through it. A page asked of it fails, and is asked
/// again of the document that takes its place.
final class _LetGoOf implements ViewerDocument {
  _LetGoOf(ViewerDocument document, {required int page})
    : pageCount = document.pageCount,
      framesPerSecond = document.framesPerSecond,
      _size = document.pageCount == 0
          ? ui.Size.zero
          : document.pageSize(page.clamp(0, document.pageCount - 1));

  @override
  final int pageCount;

  @override
  final double? framesPerSecond;

  final ui.Size _size;

  @override
  ui.Size pageSize(int pageIndex) => _size;

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) => Future.error(StateError('let go of while its file is replaced'));

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) => Future.error(StateError('let go of while its file is replaced'));

  @override
  Future<void> dispose() async {}
}

class _MediaViewerTabHostState extends State<MediaViewerTabHost>
    implements PlaybackTransport, MediaRunSurface {
  /// Commit sink required by the panel API; the viewer never invalidates
  /// playback caches.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  MediaViewerRequest? get _currentRequest => widget.request.value;

  /// The open document, whatever medium it came from — 🪦there used to be
  /// a `_frames` list AND a `_pdf` handle here, and five places downstream
  /// had to ask which was live. See [ViewerDocument].
  ViewerDocument? _document;

  /// The document's pages as rasters, under this device's budget — see
  /// [PageRasters].
  ///
  /// ⚠️Built with the State, so a test that wants a tight budget sets
  /// [ViewerRasterBudget.debugPageBytesOverride] BEFORE the panel mounts;
  /// pumping the same widget again reuses this State and this budget.
  late final PageRasters _rasters = PageRasters(
    budget: ViewerRasterBudget(
      physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    ),
    document: () => _document,
    distance: (page) => _run.distanceTo(page),
    rebuild: setState,
    mounted: () => mounted,
    // The census cannot reach into this State, so the total goes to it —
    // see [RenderCaches.viewerRasterBytesByViewer].
    report: (bytes) =>
        widget.session.renderCaches.viewerRasterBytesByViewer[widget
                .viewerId] =
            bytes,
  );

  /// The run: the timer turning pages, the sound beside them, and the law
  /// that the whole transport waits — see [MediaRun].
  late final MediaRun _run = MediaRun(
    surface: this,
    rasters: _rasters,
    sound: _sound,
  );

  // A book's pages one under another, memoized with the document.
  final _stack = IdentityMemo<PageStack>();

  /// 🪦A `_lastDrawnPage` stood here: when a page's raster had not landed,
  /// the painter was handed the LAST one instead, so playback kept moving
  /// while the picture did not.
  ///
  /// 🚨★★★**A HELD PICTURE IS INDISTINGUISHABLE FROM A HOLD THE ANIMATOR
  /// DREW**, which is the one judgement this panel exists to support. 유저
  /// 2026-08-31: 「직전그림을 유지하게 하는건 진짜 아니라고 생각하거든? …
  /// 유지하지말고 **로드할때까지 멈춰있어야지**」— and then, correcting the
  /// word for it: 「그림을 유지한다는게 아니라 **그 곳에 멈춘다**는거야」.
  ///
  /// That distinction is the whole fix. The playhead PARKS; the picture
  /// stays because the playhead is genuinely on that frame, not because an
  /// old one was kept. ⛔The scale-axis rule is untouched — a blurrier
  /// render of the SAME page is not a lie about which frame this is.

  String? _message;

  /// The cut in flight — the next waits its turn rather than racing it for
  /// the budget.
  Future<void> _cuts = Future<void>.value();

  /// The OS said memory is tight. The session already stood its own caches
  /// down; this is the viewer's share.
  void _onMemoryPressure() => _rasters.heardMemoryPressure(keeping: _page);

  /// Read-only here — the workspace holds it (see
  /// [MediaViewerTabHost.position]) and [_turnToPage] asks it to move.
  int get _page => widget.position.value;

  /// The page on show: [_page], inside the document.
  int get _pageShown {
    final count = _pageCount;
    return count == 0 ? 0 : _page.clamp(0, count - 1);
  }

  /// Guards every async landing against a newer load.
  int _generation = 0;

  /// This viewer's sound, or silence if the app has no audio device.
  late final ViewerSound _sound =
      widget.sound ?? ViewerSound.ofSession(widget.session);

  /// Token that changes once per successfully LOADED document — drives
  /// the panel's auto-reframe so a preserved deep zoom/pan from the
  /// previous asset can never leave the new one entirely off-screen.
  Object? _loadedToken;

  /// The document ([_loadedToken]) whose first framing has gone out. Until
  /// it has, the view on screen is the one the fit is about to replace —
  /// pages asked for through it would be rendered at a scale nobody sees,
  /// and in a book (F-201) for pages the fit takes off screen.
  Object? _framingSent;

  /// What identifies the DOCUMENT this viewer is showing — the file it came
  /// from, since that is what「이 문서를 이미 맞춰 놓았나」 has to be asked
  /// about. ⛔Not the page: turning a page inside one document must not
  /// throw away the zoom the user set to read it.
  String? get _documentIdentity => widget.request.value?.path;

  /// Whether the stored view still belongs to some OTHER document — the one
  /// case a fit is right, and the case the original comment was written for
  /// (a deep zoom from a large scan leaving a small next document entirely
  /// off-screen).
  bool get _needsFraming {
    final remembered = widget.framedFor;
    if (remembered == null) {
      return true;
    }
    return remembered.value != _documentIdentity;
  }

  /// Records that this document has been framed, so the next open of the
  /// SAME one leaves the user's view alone. Runs after the frame the
  /// request went out on, because the request is read during build.
  void _rememberFramed() {
    final remembered = widget.framedFor;
    final identity = _documentIdentity;
    if (remembered == null || remembered.value == identity) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        remembered.value = identity;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.request.addListener(_onRequestChanged);
    widget.session.memoryPressureTicks.addListener(_onMemoryPressure);
    widget.position.addListener(_onPosition);
    widget.session.playbackRig.transports.add(this);
    unawaited(_load(_currentRequest));
  }

  @override
  void didUpdateWidget(covariant MediaViewerTabHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (rebindListener(oldWidget.request, widget.request, _onRequestChanged)) {
      _onRequestChanged();
    }
    rebindListener(
      oldWidget.session.memoryPressureTicks,
      widget.session.memoryPressureTicks,
      _onMemoryPressure,
    );
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.playbackRig.transports.remove(this);
      widget.session.playbackRig.transports.add(this);
    }
    if (rebindListener(oldWidget.position, widget.position, _onPosition)) {
      _forgetRefusals();
    }
  }

  /// The page moved — a turn, the view scrolling a book, a playhead.
  void _onPosition() {
    if (mounted) {
      setState(_forgetRefusals);
    }
  }

  void _forgetRefusals() {
    // 🚨★★★**TURNING A PAGE IS ASKING AGAIN**, and until now only a RUN
    // was. The run's tick was the sole place a refusal was forgotten, and
    // it exists only while a run does ([MediaRun]) — which needs a document
    // that turns its own pages or carries sound. A PDF has neither, so a
    // page whose render the engine once refused stayed blank for the life
    // of the panel: the round that stopped the hot loop had traded a
    // livelock for a surrender, which is the half of 유저 2026-08-31's
    // 「로드할때까지 멈춰있어야지」 that says a WAIT, not a giving up.
    // Found by the 2026-09-09 audit of that round.
    //
    // ⛔Not a second clock, and not a rebuild-driven clear: this fires on
    // a USER ACTION, so it cannot feed itself. A refusal is still
    // remembered for as long as the reader is looking at the same page —
    // nothing about that page changed, so there is nothing to re-ask for.
    _rasters.forgetRefusals();
  }

  @override
  void dispose() {
    widget.request.removeListener(_onRequestChanged);
    widget.session.memoryPressureTicks.removeListener(_onMemoryPressure);
    widget.position.removeListener(_onPosition);
    // ⚠️Before [_disposeContent]: it stops the timer, and a transport that
    // is still registered would report the flip to a gate that is about to
    // lose the object anyway. Leaving it registered is the real hazard —
    // a closed tab would answer 「재생 중」 forever.
    widget.session.playbackRig.transports.remove(this);
    _generation += 1;
    _disposeContent();
    // ⛔REMOVE, not zero: a viewer that is gone is not a viewer holding
    // nothing, and an entry per closed tab would grow for the session.
    widget.session.renderCaches.viewerRasterBytesByViewer.remove(
      widget.viewerId,
    );
    _run.dispose();
    super.dispose();
  }

  void _onRequestChanged() => _load(widget.request.value);

  void _disposeContent() {
    // A timer outliving its document would page a viewer that has none.
    _run.letGo();
    _rasters.clear();
    final document = _document;
    _document = null;
    unawaited(document?.dispose());
    _message = null;
  }

  Future<void> _load(MediaViewerRequest? request) async {
    _generation += 1;
    final generation = _generation;
    // The position is NOT reset here. Whoever changes the request decides
    // whether this is a new document (page 1) or the same one arriving
    // again — a swap hands the other viewer's page over with the file,
    // and a remount after a folded-away rail must land where it left.
    // A position past the end of a shorter document reads clamped
    // ([_turnToPage] and the build both clamp), never out of range.
    setState(_disposeContent);
    if (request == null) {
      return; // The empty state reads from _currentRequest == null.
    }
    // ONE landing for every medium: open a document, or say why not. The
    // three arms this replaces differed only in HOW they opened and in
    // which field they parked the result — the guards against a stale
    // generation, the failure message and the reframe were written three
    // times and had already drifted (the image arm disposed its frames on a
    // stale landing, the PDF arm its handle, and audio had neither).
    final ViewerDocument? document;
    try {
      document = await _openDocument(request);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = _couldNotOpen(error));
      }
      return;
    }
    if (!mounted || generation != _generation) {
      await document?.dispose();
      return;
    }
    setState(() {
      if (document == null) {
        _message = _nothingOpensFor(request.kind);
      } else {
        _document = document;
        _loadedToken = generation;
      }
    });
    if (document is HeldViewerDocument) {
      _watch(document, request);
    }
    // The page request goes out on the build this setState causes; the
    // record lands after it, so the NEXT open of this document sees it.
    _rememberFramed();
  }

  /// Follows [held] each time the bytes it reads move
  /// ([HeldViewerDocument.moved]).
  void _watch(HeldViewerDocument held, MediaViewerRequest request) {
    held.moved.listen((move) => unawaited(_follow(held, request, move)));
  }

  /// The bytes [was] reads have an answer somewhere else now
  /// ([HeldViewerDocument.moved]) — a save absorbed the staged copy it
  /// reads, or wrote the file it reads anew elsewhere. The same [request]
  /// is opened again on the new answer, swapped
  /// in once it is open, and [was] let go; the pages already drawn stay,
  /// being the same bytes, so nothing on screen blinks.
  ///
  /// 🚨★★★**HELD WHILE IT SHOWS, THE COPY STAYED WHILE IT SHOWED** — the
  /// save retires a staged copy only when its reader lets go, so a viewer
  /// left open kept one on disk beside the entry that replaced it (card
  /// `canvas-holds-staged-for-session`). ⛔Not through [_load]: that empties
  /// the panel first, for a new document.
  ///
  /// 🚨Opened again on [was]'s OWN bytes ([HeldViewerDocument.again]), never
  /// on what [request]'s path names by then: removed from the pool or
  /// carried again, it names another carry — and the pages already drawn
  /// are this one's (audit 09-25).
  Future<void> _follow(
    HeldViewerDocument was,
    MediaViewerRequest request,
    HeldBytesMove move,
  ) async {
    if (!mounted || !identical(_document, was)) {
      return;
    }
    if (move == HeldBytesMove.replacing) {
      return _letGoThenFollow(was, request);
    }
    final ViewerDocument? fresh;
    try {
      fresh = await _openDocument(request, hold: (_) => was.again());
    } on Object {
      return; // The old answer still reads; nothing is gained by losing it.
    }
    // A cut being read off [was] reads it to the end and lands: the swap
    // below turns away whatever [was] answers after it, and a cut is not
    // asked again the way a page is.
    await _cuts;
    if (!mounted || !identical(_document, was) || fresh == null) {
      await fresh?.dispose();
      return;
    }
    _takeUp(fresh, request);
    unawaited(was.dispose());
  }

  /// A save is REPLACING the file [was] reads, and cannot while it is held
  /// open ([HeldBytesMove.replacing]) — so [was] goes FIRST, and its bytes
  /// open again once the save lets them: the open waits for the save to end
  /// (card `rewrite-under-offset-readers`). The pages already drawn stay on
  /// screen meanwhile; a page asked in between is asked again of the new
  /// document, and a cut waits for it.
  ///
  /// 🚨★★★**NOTHING TOUCHES [was] ONCE IT IS LET GO OF.** It stayed the
  /// document shown until the new one opened, and a picture's descriptor
  /// read after its dispose — a render, a second dispose — is a native
  /// crash (audit 09-25). A stand-in with its size and page count takes
  /// its place ([_LetGoOf]).
  Future<void> _letGoThenFollow(
    HeldViewerDocument was,
    MediaViewerRequest request,
  ) async {
    // Every cut already asked of [was] lands before it goes.
    for (var cuts = _cuts; ; cuts = _cuts) {
      await cuts;
      if (identical(cuts, _cuts)) {
        break;
      }
    }
    if (!mounted || !identical(_document, was)) {
      return;
    }
    final reopened = Completer<void>();
    _cuts = reopened.future;
    final standIn = _LetGoOf(was, page: _page);
    setState(() => _document = standIn);
    try {
      await was.dispose();
      final ViewerDocument? fresh;
      try {
        fresh = await _openDocument(request, hold: (_) => was.again());
      } on Object catch (error) {
        if (mounted && identical(_document, standIn)) {
          setState(() => _message = _couldNotOpen(error));
        }
        return;
      }
      if (!mounted || !identical(_document, standIn)) {
        await fresh?.dispose();
        return;
      }
      if (fresh == null) {
        // Nothing opens it now: the stand-in reads nothing, and the panel
        // says so the way a first open would (audit 09-25 — it said
        // nothing).
        setState(() => _message = _nothingOpensFor(request.kind));
        return;
      }
      _takeUp(fresh, request);
    } finally {
      reopened.complete();
    }
  }

  /// What the panel says when a document will not open.
  ///
  /// 🚨WHY, under the sentence that says WHAT. The engines answer with a
  /// reason — 「this file has no readable video stream」, 「no decoder for
  /// this codec」 — and the viewer used to drop it on the floor, so every
  /// unreadable file looked identical to every other one.
  /// ⚠️The detail is the engine's own words and is not translated; the
  /// export path made the same call with the encoder's.
  static String _couldNotOpen(Object error) =>
      '${AppText.strings.mediaViewerLoadFailed}\n$error';

  /// What the panel says when this build has nothing that opens a [kind] —
  /// the honest-absence states, each saying WHICH absence: a build without a
  /// PDF rasterizer or without a video reader is a missing engine the user
  /// can act on (a different build). ⛔One message for all of them would
  /// send someone hunting for a codec they do not need.
  static String _nothingOpensFor(MediaAssetKind kind) => switch (kind) {
    MediaAssetKind.pdf => AppText.strings.mediaViewerNoPdfRenderer,
    MediaAssetKind.video => AppText.strings.mediaViewerNoVideoDecoder,
    // 🪦Audio moved off this line in 2026-09-08: it HAS a picture now (its
    // waveform), so an absence here is a conform that could not be built —
    // a file this build cannot decode, which is the same sentence a missing
    // video reader gets.
    MediaAssetKind.audio => AppText.strings.mediaViewerNoAudioDecoder,
    MediaAssetKind.image => AppText.strings.mediaViewerCannotDisplay,
  };

  /// [fresh] in place of the document shown, for the same [request] — and
  /// followed in its turn.
  void _takeUp(ViewerDocument fresh, MediaViewerRequest request) {
    setState(() {
      // A render still out on the document it replaces lands nowhere, and
      // is asked of [fresh].
      _generation += 1;
      _rasters.turnAway();
      _document = fresh;
    });
    if (fresh is HeldViewerDocument) {
      _watch(fresh, request);
    }
  }

  /// Opens whatever [request] names — [openViewerDocument], with the
  /// project's bytes unless [hold] says where else.
  Future<ViewerDocument?> _openDocument(
    MediaViewerRequest request, {
    HoldMediaBytes? hold,
  }) => openViewerDocument(
    request.kind,
    request.path,
    hold: hold ?? widget.session.projectFile.holdMediaBytes,
    soundPeaks: widget.session.audioConformStore.ensurePeaksFor,
  );

  // --- Paging ------------------------------------------------------------

  int get _pageCount => _document?.pageCount ?? 0;

  void _turnToPage(int page) {
    final count = _pageCount;
    final next = count <= 0 ? 0 : page.clamp(0, count - 1);
    widget.position.value = next;
  }

  bool get _turnsItsOwnPages => _run.turnsItsOwnPages;

  /// The document's pages one under another, read as a book (F-201, 유저
  /// 2026-09-27: 「뷰어든 콘티 프리뷰든 pdf같은거 여러페이지 동시에
  /// 볼수있게」) — a PDF's pages, a picture's or a waveform's one; null
  /// for a document that turns its own pages, which shows the frame its
  /// playhead is on alone.
  ///
  /// ⚠️No margin round it, where the conte's and the timesheet's have one:
  /// the view never shows past the paper ([BrushCanvasPanel.viewLimit]),
  /// so a desk round the pages would be canvas nobody sees — and the first
  /// page stays where a one-page document always lay, at the origin.
  PageStack? get _book {
    final document = _document;
    if (document == null || _pageCount == 0 || _turnsItsOwnPages) {
      return null;
    }
    return _stack.resolve(
      identity: document,
      build: () => PageStack([
        for (var page = 0; page < document.pageCount; page += 1)
          document.pageSize(page),
      ], margin: 0),
    );
  }

  /// The file whose SOUND this viewer would play, or null when the thing
  /// on screen cannot carry any.
  ///
  /// ⛔It asks [mediaKindCanCarrySound] — the predicate the conform walk
  /// already uses — rather than testing for audio here. A movie carries a
  /// soundtrack, and a viewer that decided that for itself would be the
  /// second place the app answers 「이게 소리를 가질 수 있나」.
  String? get _soundPath {
    final request = _currentRequest;
    return request != null && mediaKindCanCarrySound(request.kind)
        ? request.path
        : null;
  }

  // --- The run's surface ([MediaRunSurface]) -------------------------------

  @override
  ViewerDocument? get document => _document;

  @override
  int get page => _page;

  @override
  void turnToPage(int page) => _turnToPage(page);

  @override
  String? get soundPath => _soundPath;

  /// 🚨★★★[PlaybackTransport] — this viewer is one of the things the app
  /// can be playing, so the actuation gate stops it with the same law it
  /// stops the canvas with (유저 09-07 `exclusive`, both directions).
  /// ⛔It answers from the run's timer and stops through [MediaRun.stop]; a
  /// separate "am I playing" for the gate would be the per-surface check
  /// the gate exists to avoid.
  @override
  bool get isPlaying => _run.playing;

  @override
  void stop() {
    if (!_run.playing) {
      return;
    }
    setState(_run.stop);
  }

  @override
  ValueListenable<bool> get isActiveListenable => _run.playingFlips;

  Future<void> _pickLooseFile() async {
    // 🚨EVERY PICKER SHOWS EVERY FILE (유저 2026-08-29) — the refusal is a
    // notice after the pick, not a greyed-out file in the dialog. The
    // widget's own [filePicker] seam still wins, so tests drive a path
    // straight in.
    final injected = widget.filePicker;
    final path = injected != null
        ? await injected()
        : await openSupportedFile(
            context,
            supportedExtensions: FileTypeGroups.viewableMedia.extensions ?? [],
          );
    if (path == null || !mounted) {
      return;
    }
    final kind = mediaAssetKindForPath(path) ?? MediaAssetKind.image;
    widget.onRequestPicked?.call(MediaViewerRequest(path: path, kind: kind));
  }

  /// Whether the file on screen can still be added to the media pool —
  /// false for one already in it, and for nothing at all.
  bool get _canRegister {
    final path = _currentRequest?.path;
    return path != null &&
        widget.onRegisterAsset != null &&
        !(widget.isPathRegistered?.call(path) ?? true);
  }

  void _registerCurrent() {
    final path = _currentRequest?.path;
    if (path == null) {
      return;
    }
    widget.onRegisterAsset?.call(path);
    // The import lands synchronously and this panel does not listen to
    // the session (a viewer that rebuilt on every session notify would
    // be the expensive kind of panel). Ask again ourselves, so the
    // button goes quiet the moment its work is done.
    setState(() {});
  }

  /// Every widget key in this panel, built from [MediaViewerTabHost.viewerId]
  /// — the ONE place the prefix is applied, so a second viewer cannot end
  /// up sharing a key with the first.
  String _key(String suffix) => '${widget.viewerId}-$suffix';

  /// The page cluster, STACKED for the left strip (유저 확정 ⑥) — and empty
  /// unless there is more than one page, because a still image has no pages
  /// to turn and a strip standing there for it would be a permanent
  /// disabled promise.
  List<Widget> _pageStrip(int pageIndex, int pageCount) {
    final strings = AppText.strings;
    return pageTurnStrip(
      keyPrefix: widget.viewerId,
      page: viewerPage(pageIndex, pageCount),
      onTurnTo: _turnToPage,
      leading: [
        // 🚨PLAY sits with the page controls, not in a strip of its own:
        // playing IS turning pages, and the user asked for 「최대한 통일」.
        // ⛔It is present only when the document turns its own pages — the
        // same rule this whole strip already follows (유저 확정 ⑥: a still
        // image gets no strip rather than a permanently disabled one).
        if (_run.canPlay)
          AppIconButton(
            keyValue: _key('play-button'),
            tooltip: _run.playing ? strings.menuPause : strings.menuPlay,
            icon: Icon(_run.playing ? Icons.pause : Icons.play_arrow),
            size: AppIconButtonSize.strip,
            onPressed: _run.toggle,
          ),
      ],
    );
  }

  // --- Cutting (I-14: the cut tool, at the page's own size) -------------

  /// The tool the viewer's panel runs: the CUT while the cut tool is armed,
  /// and NULL otherwise — nothing else has anything here to act on. One
  /// instance per outline, so a rebuild hands the panel the SAME state.
  ///
  /// 🗣️유저 2026-09-16 (F-80): 「작동 가능한 거면 해당 도구 작동시키고,
  /// 불가능하면 팬」 — null IS that answer, and the panel turns it into a
  /// press that moves the page ([BrushCanvasPanel.runsTheSelectedTool]).
  ///
  /// The panel HEARS its brush (H40 ②), and this one never changes while it
  /// is held — an outline is a different tool — so each is a listenable
  /// that stands still: Flutter's own [AlwaysStoppedAnimation].
  static ValueListenable<BrushToolState>? _toolFor(
    BrushToolState workspaceTool,
  ) {
    final shape = armedCutShape(workspaceTool);
    return shape == null
        ? null
        : _cutTools.putIfAbsent(
            shape,
            () => AlwaysStoppedAnimation<BrushToolState>(
              BrushToolState.defaults.copyWith(
                tool: CanvasTool.cut,
                cutShape: shape,
              ),
            ),
          );
  }

  static final Map<CanvasShapeKind, ValueListenable<BrushToolState>>
  _cutTools = {};

  /// A finished cut outline over the page on screen: read its box at the
  /// page's OWN size and hold it as the cut tool's piece.
  ///
  /// 🗣️유저 2026-09-11: 「원본크기로 잘라냄」 — 「34%의 크기가 스탬프
  /// 크기값이 100%이 되는게 아니라, 제대로 100% 해상도만큼」. The outline
  /// arrives in document units whatever the zoom, and the read is in those
  /// same units, so the piece is the source's own pixels and the stamp's
  /// 100% is that size.
  ///
  /// ⚠️Of the page it was drawn on, taken NOW: a cut can wait its turn — a
  /// cut before it, a document being let go of — and a page turned in the
  /// meantime would have the outline cut out of the wrong page (audit
  /// 09-25).
  ///
  /// In a book (F-201) the page is the one the outline lies on most — the
  /// pages lie one under another — and the outline moves into that page's
  /// own space. An outline on the desk between pages cuts nothing.
  void _cutFromPage(CanvasSelectionShape shape) {
    final book = _book;
    if (book == null) {
      final page = _page;
      _cuts = _cuts.then((_) => _cut(shape, page));
      return;
    }
    final page = _pageUnder(book, shape);
    if (page == null) {
      return;
    }
    final at = book.pageRect(page).topLeft;
    final onPage = shape.translated(dx: -at.dx, dy: -at.dy);
    _cuts = _cuts.then((_) => _cut(onPage, page));
  }

  /// The page of [book] the outline [shape] covers most — null when it
  /// covers none.
  int? _pageUnder(PageStack book, CanvasSelectionShape shape) {
    final b = CanvasSelectionRegion.shape(shape).selectedBounds;
    final bounds = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    int? most;
    var mostArea = 0.0;
    for (final page in book.pagesMeeting(bounds)) {
      final overlap = book.pageRect(page).intersect(bounds);
      final area = overlap.width * overlap.height;
      if (area > mostArea) {
        mostArea = area;
        most = page;
      }
    }
    return most;
  }

  Future<void> _cut(CanvasSelectionShape shape, int page) async {
    final slot = widget.cutPieceSlot;
    final document = _document;
    final pageCount = _pageCount;
    if (!mounted || slot == null || document == null || pageCount == 0) {
      return;
    }
    final pageIndex = page.clamp(0, pageCount - 1);
    final pixels = viewerPagePixels(document.pageSize(pageIndex));
    // 📨THE BUDGET THE PAGES LIVE UNDER (the import-export session,
    // 2026-09-11: 「뷰어 예산 … 을 따르면 됩니다」). The read is billed as the
    // page at its own size — the most any document's read holds, since an
    // image decodes whole — and the cached pages make room for it. What
    // cannot fit even then is REFUSED, never read smaller: a shrunken piece
    // is exactly what the user ruled out.
    final bytes = estimatedImageBytes(pixels.width, pixels.height);
    var held = 0;
    setState(() {
      _rasters.extraBytes = bytes;
      held = _rasters.evictToBudget(keeping: pageIndex);
    });
    if (held + bytes > _rasters.budget.byteBudget) {
      _endCutRead();
      cursorNotices.show(
        AppText.strings.mediaViewerCutTooLarge,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final generation = _generation;
    final CutPiece? piece;
    try {
      piece = await buildCutPieceFromPicture(
        region: CanvasSelectionRegion.shape(shape),
        picture: pixels,
        readRgba: (box) => document.readRegionRgba(pageIndex, box),
      );
    } on Object {
      if (mounted && generation == _generation) {
        cursorNotices.show(AppText.strings.mediaViewerLoadFailed);
      }
      return;
    } finally {
      if (mounted) {
        _endCutRead();
      }
    }
    // The document it was cut from is gone, or the panel is: what is on
    // screen now is not what was cut.
    if (!mounted || generation != _generation || piece == null) {
      return;
    }
    slot.hold(piece);
  }

  /// The read is back, or never went out: stop billing it.
  void _endCutRead() {
    setState(() {
      _rasters.extraBytes = 0;
      _rasters.evictToBudget(keeping: _page);
    });
  }

  /// The pages the view shows now and where each lies — every page on
  /// screen in the book ([_book]), the page on show ([_pageShown])
  /// otherwise — each asked for at the zoom the view has — none while
  /// [asking] is false (a fit is about to replace the view).
  ///
  /// 🚨★★★THE ZOOM THE VIEW HAS, read HERE, from the view the panel hands
  /// this builder. It was read in `build` from `widget.viewport` — a seed
  /// the workspace never passes (it hands over the controller) — so in
  /// the app every page was asked for at a zoom of 1 whatever the view
  /// showed, and a zoomed-in page was that render stretched (found reading
  /// the viewer for its book, F-201).
  ///
  /// 🚨The tier is chosen from DEVICE coverage, not from the render zoom.
  /// The viewer is a document view, so R11 excludes it from the UI scale
  /// by DIVIDING its render zoom when the scale goes up — so reading the
  /// raw zoom made raising the interface LOWER the tier while the page
  /// deliberately stayed the same size on screen: same dimensions,
  /// visibly softer, and the only thing the user changed was how big the
  /// chrome is.
  ///
  /// 🚨★★★**IMAGES COME THROUGH HERE.** They used to skip the tier and draw
  /// a decode of the ORIGINAL file, which is the 17× the card measured.
  ///
  /// 🚨THE SCALE AXIS ONLY. [PageRasters.imageOf] says a wrong-SCALE image
  /// draws while the right one renders — a blurrier render of the SAME page
  /// is not a lie about which frame this is. 🪦A page-axis twin once drew
  /// the LAST page when this one's raster had not landed, answering the
  /// white flashes 유저 2026-08-31 reported (「첫 재생때 … 흰 화면이
  /// 엄청나게 깜빡이면서 재생됨」) by making the picture lie; the playhead
  /// does not reach a frame that is not there instead.
  List<({Rect rect, ui.Image? image})> _pagesShown(
    BuildContext context,
    CanvasViewport viewport,
    Size box, {
    required bool asking,
  }) {
    final document = _document;
    if (document == null || _pageCount == 0) {
      _rasters.shown = const {};
      return const [];
    }
    final book = _book;
    final page = _pageShown;
    final shown = [
      if (book == null)
        (page: page, rect: Offset.zero & document.pageSize(page))
      else
        for (final index in book.pagesMeeting(
          canvasRectShown(viewport, box),
        ))
          (page: index, rect: book.pageRect(index)),
    ];
    _rasters.shown = {for (final entry in shown) entry.page};
    if (asking) {
      final coverage = CanvasZoomScale.of(context).display(viewport.zoom);
      for (final entry in shown) {
        final scale = viewerRenderScaleFor(
          coverage,
          document.pageSize(entry.page),
        );
        if (entry.page == page) {
          _rasters.scale = scale;
        }
        _rasters.ensureRendered(entry.page, scale);
      }
      _run.fillBuffer();
    }
    return [
      for (final entry in shown)
        (rect: entry.rect, image: _rasters.imageOf(entry.page)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final request = _currentRequest;
    final pageCount = _pageCount;
    final pageIndex = _pageShown;

    // Document space: the page/frame being shown. ONE answer now — the
    // document knows its own page size, whether that is PDF points, image
    // pixels or a video frame.
    final document = _document;
    final docSize = document != null && pageCount > 0
        ? document.pageSize(pageIndex)
        : const ui.Size(640, 480);

    // How long the sound is, when the page IS the sound — the waveform's
    // whole width is that many seconds, so it is also the scale the
    // playhead sits on.
    //
    // ⛔Only for a page that does not turn: a movie's playhead is its PAGE,
    // and giving it a second one in seconds would be two answers to 「어디를
    //보고 있나」. The movie's soundtrack is the next step of the roadmap and
    // it rides the page, not this.
    final waveformSeconds = _turnsItsOwnPages ? null : _run.soundLengthSeconds;


    final message = request == null ? strings.mediaViewerEmpty : _message;

    // The page on the canvas: what a fit frames and where the view stops
    // (F-201). None while a message stands in for it or the document is
    // still on its way — a stand-in's size would hold a view the slot
    // restored somewhere the page is not.
    final book = message == null ? _book : null;
    final paper = message == null && document != null && pageCount > 0
        ? (book?.paper ?? Rect.fromLTWH(0, 0, docSize.width, docSize.height))
        : null;
    // What the canvas spans: the book, or the one page.
    final canvas = book?.size ?? docSize;

    // Reframe ONCE per loaded document: the workspace-owned viewport
    // survives asset switches, and a deep zoom/pan from a large scan would
    // otherwise leave a small next document entirely off-screen — a blank
    // panel this viewer promises never to show.
    // 🚨THE TOKEN IS THE DOCUMENT, NOT THE LOAD. It used to be this State's
    // own load counter, and a State dies with the panel — so reopening
    // minted a fresh one and the fit ran again over a view the user had
    // set. What the slot remembers is what makes 「once per document」 true
    // across a close.
    final framing = paper != null && _loadedToken != null && _needsFraming
        ? CanvasAutoFrameRequest(
            token: _loadedToken!,
            rect: book?.pageRect(pageIndex) ?? paper,
          )
        : null;
    // The pages wait for the fit: it lands after this frame, and the build
    // it leads to asks for them through the view they will be seen in.
    final framingPending = framing != null && _framingSent != _loadedToken;
    if (framingPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _framingSent = _loadedToken);
        }
      });
    }

    BrushCanvasPanel panelWith(ValueListenable<BrushToolState>? tool) =>
        BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: CanvasSize(
        width: canvas.width.ceil().clamp(1, 1 << 14).toInt(),
        height: canvas.height.ceil().clamp(1, 1 << 14).toInt(),
      ),
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      // Paper rule: the viewer never rotates the view.
      allowViewRotation: false,
      // Read-only host: a brush-tip cursor over undrawable content is a
      // false affordance.
      toolCursorsEnabled: false,
      // F-77 (유저: 「뷰어패널 열린거 없으면 확대나 스크롤바같은 조작 버튼
      // 비활성화」): with no file open there is no view to operate.
      hasContentToView: request != null,
      // 🗣️I-14 (유저 2026-09-11): 「뷰어패널은 기본적으로 드로잉모드
      // 존재안하니 한손가락 핑거시 팬」 — whatever the one-finger slot says,
      // and so a finger drives no tool here: the cut takes a pen or a mouse.
      oneFingerAction: CanvasTouchDragAction.navigate,
      brushToolState: tool,
      // F-80: with no cut armed nothing here can act on a press, so it
      // moves the page instead.
      runsTheSelectedTool: tool != null,
      // F-179 (유저 2026-09-25: 「타임시트패널등 캔버스 베이스 패널엔
      // 페이스트보드가 없다는 뜻임」): the viewer is one of those panels —
      // F-201 names it one — so its paper lies on the panel's backdrop.
      hasPasteboard: false,
      onCutContent: widget.cutPieceSlot == null ? null : _cutFromPage,
      autoFrame: framing,
      // 유저 확정 2026-08-13 (⑤): opening a file is the one verb that stays
      // on the pill. Register and swap are a session's worth of taps
      // between them, and every control that stays costs the pill 44px of
      // budget it then takes from the page navigation on a narrow rail.
      bottomBarLeading: [
        if (widget.onRequestPicked != null)
          AppIconButton(
            keyValue: _key('open-file-button'),
            tooltip: strings.mediaViewerOpenFile,
            icon: const Icon(Icons.file_open_outlined),
            size: AppIconButtonSize.strip,
            onPressed: _pickLooseFile,
          ),
      ],
      pageStrip: _pageStrip(pageIndex, pageCount),
      bottomBarSettings: [
        // Both keep their retired button's key string — the flyout's own
        // convention, so every test that pressed them gains a menu-open
        // tap and nothing else.
        if (widget.onRegisterAsset != null)
          PanelFlyoutItem(
            keyValue: _key('register-asset-button'),
            label: strings.mediaViewerRegisterAsset,
            icon: Icons.playlist_add_outlined,
            enabled: _canRegister,
            onSelected: _registerCurrent,
          ),
        if (widget.onSwapViewers != null)
          PanelFlyoutItem(
            keyValue: _key('swap-button'),
            label: strings.mediaViewerSwap,
            icon: Icons.swap_horiz,
            onSelected: widget.onSwapViewers,
          ),
      ],
      // The register command's enabled state rides this token too — it
      // changes with the file, which is exactly when the answer to "is
      // this one in the pool" can change. ⚠️It has to: the list captures
      // the entries when the BAR is built, not when the list opens.
      bottomBarHostToken: (pageIndex, pageCount, _canRegister),
      // A book's Fit frames the page read — the panel's to know.
      fitFocusRect: book == null ? paper : null,
      viewLimit: paper,
      book: book == null
          ? null
          : CanvasBook(pages: book, reading: widget.position),
      contentOverride: (context, viewport) => Stack(
        children: [
          if (message != null)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateText(
                  message,
                  key: ValueKey<String>(_key('message')),
                  place: EmptyStatePlace.stage,
                ),
              ),
            )
          else
            Positioned.fill(
              // Same shape and same reason as the conte and envelope
              // pages: a light table that changes when you page or pan
              // and not otherwise, which was being re-rastered on every
              // frame the app produced for any reason at all.
              child: LayoutBuilder(
                builder: (context, box) => StaticRaster(
                  debugLabel: _key('page'),
                  child: CustomPaint(
                    key: ValueKey<String>(_key('page')),
                    painter: _MediaPagePainter(
                      pages: _pagesShown(
                        context,
                        viewport,
                        box.biggest,
                        asking: !framingPending,
                      ),
                      // PDF paper is opaque white; a transparent image
                      // shows the checker-free paper too — the viewer is
                      // a light table, not a compositor.
                      paperFill: document != null,
                      viewport: viewport,
                      effectiveRatio: EffectiveDevicePixelRatio.of(context),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          // The playhead over a waveform — its own layer, never inside the
          // page above.
          //
          // 🚨The page rides a [StaticRaster] because it changes when you
          // page or pan and NOT otherwise; a playhead painted into it would
          // re-bake that raster sixty times a second, which is the exact
          // cost that widget exists to remove.
          //
          // ⛔Present whenever the file has sound, not only while it plays:
          // a line that appears on the first press is UI that pops into
          // existence, and where the playhead STANDS is what tells you
          // where a second press would resume from.
          if (waveformSeconds != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: ValueKey<String>(_key('playhead')),
                  painter: _PlayheadPainter(
                    atSeconds: _run.soundSeconds,
                    ofSeconds: waveformSeconds,
                    docSize: docSize,
                    viewport: viewport,
                    effectiveRatio: EffectiveDevicePixelRatio.of(context),
                    color: AppColors.accent,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
    final brushTool = widget.brushTool;
    final panel = brushTool == null
        ? panelWith(null)
        : SlicedValueListenableBuilder<BrushToolState, CanvasShapeKind?>(
            valueListenable: brushTool,
            slice: armedCutShape,
            builder: (context, tool) => panelWith(_toolFor(tool)),
          );

    final surface = ColoredBox(
      key: ValueKey<String>(_key('panel')),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: panel,
    );
    final onAssetDropped = widget.onAssetDropped;
    if (onAssetDropped == null) {
      return surface;
    }
    // 유저 확정 ⑬: a browser row dropped here opens HERE. The rows are
    // already `Draggable<MediaAssetDragData>` for the SE blocks, so this
    // is a second destination for a drag people already do — and it says
    // which viewer with the hand instead of with a menu entry.
    //
    // ⚠️`surface` is the Stack's UNPOSITIONED child and the highlight is
    // the positioned one, never the other way round: a Stack whose
    // children are ALL positioned takes the smallest size its
    // constraints allow, which in a rail collapsed this whole panel and
    // left its pill sitting on top of its own canvas, unhittable.
    return Stack(
      fit: StackFit.expand,
      children: [
        surface,
        Positioned.fill(
          child: MediaAssetDropTarget(
            onDrop: (data, _) => onAssetDropped(data),
          ),
        ),
      ],
    );
  }
}

class _MediaPagePainter extends CustomPainter with RepaintOnProps {
  const _MediaPagePainter({
    required this.pages,
    required this.paperFill,
    required this.viewport,
    required this.effectiveRatio,
  });

  /// The pages on screen, each where it lies in document space with its
  /// raster — null draws the paper alone (a page still rendering). A
  /// raster draws scaled INTO its rect, so a higher-tier render stays
  /// sharp under zoom.
  final List<({Rect rect, ui.Image? image})> pages;

  final bool paperFill;
  final CanvasViewport viewport;

  /// The view's DPR, for [applyViewportTransform]'s pan-phase snap.
  final double effectiveRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // P8's ONE transform. ⛔The snap already happened at the host, so the
    // ratio here keeps the helper's own snap idempotent.
    applyViewportTransform(canvas, viewport, devicePixelRatio: effectiveRatio);
    for (final (:rect, :image) in pages) {
      if (paperFill) {
        canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
      }
      if (image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
      }
    }
    canvas.restore();
  }

  /// ⚠️The pages by their CONTENTS: the list is built afresh every build.
  @override
  Object get props => (ByList(pages), paperFill, viewport, effectiveRatio);
}

/// The line that says where in the sound you are.
///
/// ⚠️Its own painter and its own layer above the page: the page is a
/// [StaticRaster] that re-bakes only when you page or pan, and a playhead
/// inside it would re-bake it on every tick of a run.
class _PlayheadPainter extends CustomPainter with RepaintOnProps {
  const _PlayheadPainter({
    required this.atSeconds,
    required this.ofSeconds,
    required this.docSize,
    required this.viewport,
    required this.effectiveRatio,
    required this.color,
  });

  final double atSeconds;
  final double ofSeconds;
  final ui.Size docSize;
  final CanvasViewport viewport;
  final double effectiveRatio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (ofSeconds <= 0) {
      return;
    }
    canvas.save();
    // The SAME transform the page uses — the line has to land on the
    // waveform under every zoom and pan, so it cannot compute its own.
    applyViewportTransform(canvas, viewport, devicePixelRatio: effectiveRatio);
    final x = docSize.width * (atSeconds / ofSeconds).clamp(0.0, 1.0);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, docSize.height),
      Paint()
        // In DOCUMENT units, so the line thins as you zoom in rather than
        // growing into a bar over the sample it is pointing at.
        ..strokeWidth = docSize.width / 600
        ..color = color,
    );
    canvas.restore();
  }

  @override
  Object get props =>
      (atSeconds, ofSeconds, docSize, viewport, effectiveRatio, color);
}
