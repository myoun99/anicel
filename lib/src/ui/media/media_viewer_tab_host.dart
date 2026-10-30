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
import '../../models/project_frame_rate.dart';
import '../../models/rgba_image_bytes.dart';
import '../../models/canvas_viewport.dart';
import '../../models/media_asset.dart';
import '../../models/viewer_ink_keys.dart' show viewerInksOn;
import '../../services/media/held_viewer_document.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/viewer_document.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/cut_piece_lift.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/project_lookup.dart' show mediaKindCanCarrySound;
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../canvas/viewport_pages_painter.dart';
import '../effective_device_pixel_ratio.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/canvas_book.dart';
import '../brush/canvas_floor_insets.dart';
import '../brush/canvas_selection_commands.dart';
import '../brush/brush_tool_state.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/cut_into_the_hand.dart';
import '../brush/sheet_canvas_panel.dart'
    show SheetStrokeHold, sheetBrushSwitch, sheetRunsTool;
import '../editor_session_manager.dart';
import '../input/os_file_drop.dart';
import '../playback/playback_transport.dart';
import '../session/media_file_views.dart';
import '../sheet/sheet_ink_layer.dart' show SheetInkWindow;
import '../sheet/sheet_shape_targets.dart';
import '../dialogs/open_file_flow.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import 'media_asset_drag_data.dart';
import 'media_asset_drop_target.dart';
import 'media_run.dart';
import 'open_viewer_document.dart';
import 'page_rasters.dart';
import 'viewer_page_loading.dart';
import 'viewer_pages_and_run.dart';
import 'viewer_render_tier.dart';
import 'viewer_ink.dart';
import 'viewer_sound.dart';
import 'waveform_marks_painter.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/page_turn_bar.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/transport_bar.dart';
import '../widgets/static_raster.dart';
import '../widgets/cursor_notice.dart' show cursorNotices;
import '../listenable_rebind.dart';
import '../sliced_value_listenable_builder.dart';

/// What the media viewer is looking at. Owned by the workspace (the
/// dockable-panel view-state rule) so the choice survives tab switches
/// and re-docking.
class MediaViewerRequest {
  const MediaViewerRequest({required this.path, required this.kind});

  final String path;
  final MediaAssetKind kind;

  // 🪦No name of its own (F-376, 2026-10-17): it carried the pooled
  // asset's name as it stood when the viewer opened, and a rename while
  // the file was open did not reach the viewer's plate. The plate reads
  // the pool now ([MediaViewerTabHost]).
}

/// ONE viewer's whole state, owned by the workspace: what it looks at,
/// how far into that document, and where the view sits.
///
/// Two of these exist — the floor's viewer and the sub viewer beside the
/// drawing — and they share NOTHING. Opening a reference in one must
/// never change what the other is showing, which is the entire reason
/// there are two.
class MediaViewerSlot {
  MediaViewerSlot() {
    position.addListener(_keepPage);
    viewport.addListener(_keepFraming);
  }

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

  /// How loud this viewer plays ([MediaViewerTabHost.loudness]) — up here
  /// for the reason the page is: a rail group folded away unmounts the
  /// panel, and coming back to a sound at full that was turned down is not
  /// 「where I was」.
  ///
  /// ⚠️The viewer's, not the file's: a swap carries each file's page across
  /// and leaves each viewer its own level ([swapWith]).
  final ValueNotifier<ViewerLoudness> loudness = ValueNotifier(
    const ViewerLoudness(),
  );

  /// This viewer's brush switch ([MediaViewerTabHost.brushAllowed]) — off
  /// to begin with, as every sheet's (I-114: 「다른 캔버스 베이스패널의
  /// 브러시 허용이랑 똑같은」), and up here for the reason the page is.
  ///
  /// ⚠️The viewer's, not the file's: a swap trades the files and leaves
  /// each viewer its own switch ([swapWith]), as its loudness.
  final ValueNotifier<bool> brushAllowed = ValueNotifier(false);

  /// Points this viewer at a document — at the page that FILE was last seen
  /// at, in either viewer, or its first when it never was turned (F-382,
  /// [keepIn]). "Page 37" of the file you just left means nothing in the
  /// one you just opened: the page is always the arriving file's. Null
  /// empties the viewer, which is also what a reference the app can no
  /// longer reach comes back as (유저 확정 ⑭: quietly).
  ///
  /// ↩️A project's remembered documents came back through a door of their
  /// own, the one that did not go back to the start; with the page the
  /// file's, every open is that door.
  ///
  /// A SWAP deliberately does not come through here — it carries each
  /// file's own page across with it (see [swapWith]).
  void open(MediaViewerRequest? next) {
    request.value = next;
    position.value = next == null ? 0 : (_views?.pageOf(next.path) ?? 0);
  }

  /// Trades documents with the other viewer: 유저 확정 ⑪⑯⑰ — the verb is
  /// SWAP and it has no special cases, so trading with an empty viewer
  /// leaves this one empty. A button whose result depends on what the
  /// other side happens to hold is a button nobody can predict.
  ///
  /// The page travels WITH its file (page 37 of the conte is still page
  /// 37 when it lands on the floor). The viewport does not: the two
  /// panels are different widths, so each frames what arrives for itself
  /// — as it last framed that file, or fitted ([keptFramingOf]).
  void swapWith(MediaViewerSlot other) {
    final request = this.request.value;
    final position = this.position.value;
    this.request.value = other.request.value;
    this.position.value = other.position.value;
    other.request.value = request;
    other.position.value = position;
  }

  /// What this viewer keeps of each file it shows — the page it was left
  /// at and how it was framed (F-382) — and its panel id, the framing's
  /// key. The project on screen's ([keepIn]); with none, every file opens
  /// at its first page, fitted.
  MediaFileViews? _views;
  String _viewer = '';

  /// From now on this viewer keeps what it shows in [views], as [viewer]
  /// — the project that came on screen's.
  void keepIn(MediaFileViews views, {required String viewer}) {
    _views = views;
    _viewer = viewer;
  }

  /// The view this viewer left [path] framed at — null when it never
  /// framed it, and the file is fitted ([MediaViewerTabHost.keptFraming]).
  CanvasViewport? keptFramingOf(String path) =>
      _views?.framingOf(path, viewer: _viewer);

  /// The file the page and the view belong to now — none while the viewer
  /// is between files ([framedFor] still names the last one): what moves
  /// then is the last document's view, or the next one's page on its way,
  /// and keeping it would hand one file another's.
  String? get _seen {
    final path = request.value?.path;
    return path != null && framedFor.value == path ? path : null;
  }

  void _keepPage() {
    if (_seen case final path?) {
      _views?.rememberPage(path, position.value);
    }
  }

  void _keepFraming() {
    if ((_seen, viewport.value) case (final path?, final framing?)) {
      _views?.rememberFraming(path, viewer: _viewer, framing: framing);
    }
  }

  void dispose() {
    request.dispose();
    position.dispose();
    viewport.dispose();
    framedFor.dispose();
    loudness.dispose();
    brushAllowed.dispose();
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
    this.onRequestClosed,
    this.onSwapViewers,
    this.onRegisterAsset,
    this.isPathRegistered,
    this.onAssetDropped,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.framedFor,
    this.keptFraming,
    this.loudness,
    this.selection,
    this.filePicker,
    this.sound,
    this.brushTool,
    this.cutPieceSlot,
    this.inkController,
    this.brushAllowed = false,
    this.onBrushAllowedChanged,
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

  /// Empties the viewer — its close button, beside the open one. Null
  /// hides that button, as [onRequestPicked] hides its own.
  final VoidCallback? onRequestClosed;

  /// Trades documents with the OTHER viewer (유저 확정 ⑪): same button on
  /// both sides, because swapping is symmetric.
  final VoidCallback? onSwapViewers;

  /// Adds the file being viewed to the media pool (유저 확정 ⑱), through
  /// whatever the app's one import does — done once that is. Offered only
  /// for a file that is not in the pool yet — [isPathRegistered] answers
  /// that.
  ///
  /// The point of the button: a loose path is remembered as an absolute
  /// path and breaks on another machine, while a pooled one travels with
  /// the project. This is how a person promotes the first into the
  /// second without going back to the browser to find the file again.
  final FutureOr<void> Function(String path)? onRegisterAsset;
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

  /// [MediaViewerSlot.keptFramingOf] — the view this viewer left a file
  /// framed at (F-382). A document it has framed before comes back framed
  /// so, at the page its file was last seen at, rather than fitted. Null in
  /// hosts that own no slot: every document is fitted.
  final CanvasViewport? Function(String path)? keptFraming;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// [MediaViewerSlot.loudness] — how loud this viewer plays its sound.
  /// Null in hosts that own no slot: the panel keeps a level of its own for
  /// as long as it is mounted.
  final ValueNotifier<ViewerLoudness>? loudness;

  /// This viewer's selection channel, the window's for it (F-380 —
  /// `HomePage`): where the cut's polygon trace is tapped out. Null in a
  /// host handed none: the panel keeps a channel of its own for as long as
  /// it is mounted.
  final CanvasSelectionCommands? selection;

  /// Injectable loose-file picker (tests): answers in place of the dialog.
  final LooseFilePicker? filePicker;

  /// Injectable sound (tests) — the same seam as [filePicker].
  ///
  /// 🚨★★★**WITHOUT THIS THE SOUND HALF IS UNMEASURED.** A widget test
  /// never gets an audio device (`audioDeviceUnlessTesting`), so every
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
  /// ↩️I-114 gave it one — [brushAllowed], on a file the project carries —
  /// and while it is on the brush reaches the page's ink as on a sheet.
  final ValueListenable<BrushToolState>? brushTool;

  /// Where a cut from this viewer lands — the cut tool's one held piece,
  /// the slot the canvas's cuts fill too. Null offers no cut.
  ///
  /// ⛔Not handed to the panel below: a mounted canvas panel installs its
  /// paste-at-origin into the slot, and the viewer has no cel to paste on.
  final CutPieceSlot? cutPieceSlot;

  /// The ink the viewers write on the files the project carries. Null
  /// writes on none.
  final ViewerInkController? inkController;

  /// THE VIEWER'S BRUSH SWITCH — the sheets' 「브러시 허용」
  /// ([sheetBrushSwitch]), off by default as theirs is.
  ///
  /// 🗣️I-114 (유저 2026-10-21): 「뷰어패널(서브던 메인이던) 새 기능. 다른
  /// 캔버스 베이스패널의 브러시 허용이랑 똑같은 직접 그릴수있는기능 법
  /// 통일해서 구현. 물론 그리는게 가능한 파일만 대응 … 오디오파일처럼
  /// 못그리는건 대응불가하도록」 — and I-114-Q1: 「품은 파일만」. On any
  /// other file the switch keeps its place, off ([viewerInksOn]).
  final bool brushAllowed;

  /// Flips [brushAllowed]. Null shows no switch — a viewer with nowhere to
  /// keep the answer.
  final ValueChanged<bool>? onBrushAllowedChanged;

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
      drawnAtAnySize = document.drawnAtAnySize,
      _size = document.pageCount == 0
          ? ui.Size.zero
          : document.pageSize(page.clamp(0, document.pageCount - 1));

  @override
  final int pageCount;

  @override
  final double? framesPerSecond;

  @override
  final bool drawnAtAnySize;

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
    with TickerProviderStateMixin
    implements PlaybackTransport, MediaRunSurface {
  /// Commit sink required by the panel API; the viewer never invalidates
  /// playback caches.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  /// The page ink's live-stroke hold — a sheet's ([SheetStrokeHold]).
  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => widget.session.setBrushInputActive(live),
  );

  /// What takes a shape on the page ink — its layer says (F-420).
  final SheetShapeTargets _shapes = SheetShapeTargets();

  /// Whether the last build mounted the page ink: drawing going off — the
  /// switch, another file — unmounts it under a pen that will never be
  /// lifted there.
  bool _drawingOn = false;

  MediaViewerRequest? get _currentRequest => widget.request.value;

  /// The open file's name as the pool shows it NOW (F-376) — a rename while
  /// it is open reaches the plate — or null with nothing open.
  String? get _shownName => switch (_currentRequest) {
    final request? => mediaFileShownName(_shownAsset, request.path),
    null => null,
  };

  /// The open file as the pool holds it NOW — null with nothing open, or a
  /// file the pool does not hold.
  MediaAsset? get _shownAsset => switch (_currentRequest) {
    final request? => widget.session.repository.currentProject
        ?.mediaAssetByPath(request.path),
    null => null,
  };

  /// The name the plate was last drawn with: the session tells of every
  /// edit, and only one that changes this name redraws the viewer.
  String? _drawnName;

  /// What the open file was carried as when last drawn — whether its page
  /// takes ink (I-114): a file carried or let go while it is open redraws
  /// the viewer, as a rename does.
  String? _drawnCarry;

  void _onSessionChanged() {
    if (mounted &&
        (_shownName != _drawnName ||
            _shownAsset?.carriedAs != _drawnCarry)) {
      setState(() {});
    }
  }

  /// The open document, whatever medium it came from — 🪦there used to be
  /// a `_frames` list AND a `_pdf` handle here, and five places downstream
  /// had to ask which was live. See [ViewerDocument].
  ViewerDocument? _document;

  /// The document's pages and the run that turns them — see
  /// [ViewerPagesAndRun].
  late final ViewerPagesAndRun _pagesAndRun = ViewerPagesAndRun(
    surface: this,
    sound: _sound,
    // The census cannot reach into this State, so the total goes to it —
    // see [RenderCaches.viewerRasterBytesByViewer].
    report: (bytes) =>
        widget.session.renderCaches.viewerRasterBytesByViewer[widget
                .viewerId] =
            bytes,
  );
  PageRasters get _rasters => _pagesAndRun.rasters;
  MediaRun get _run => _pagesAndRun.run;

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
    widget.session.addListener(_onSessionChanged);
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
    rebindListener(oldWidget.session, widget.session, _onSessionChanged);
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
    widget.session.removeListener(_onSessionChanged);
    widget.session.memoryPressureTicks.removeListener(_onMemoryPressure);
    widget.position.removeListener(_onPosition);
    // ⚠️Before [_disposeContent]: it stops the clock, and a transport that
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
    _ownSelection?.dispose();
    _strokeHold.dispose();
    super.dispose();
  }

  void _onRequestChanged() => _load(widget.request.value);

  void _disposeContent() {
    // A clock outliving its document would page a viewer that has none.
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
        setState(() => _message = viewerCouldNotOpen(error));
      }
      return;
    }
    if (!mounted || generation != _generation) {
      await document?.dispose();
      return;
    }
    setState(() {
      if (document == null) {
        _message = viewerNothingOpens(request.kind);
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
          setState(() => _message = viewerCouldNotOpen(error));
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
        setState(() => _message = viewerNothingOpens(request.kind));
        return;
      }
      _takeUp(fresh, request);
    } finally {
      reopened.complete();
    }
  }

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
  TickerProvider get vsync => this;

  @override
  ProjectFrameRate get frameRate =>
      widget.session.projectSettings.projectFrameRate;

  @override
  ViewerDocument? get document => _document;

  @override
  int get page => _page;

  @override
  void turnToPage(int page) => _turnToPage(page);

  @override
  String? get soundPath => _soundPath;

  @override
  ViewerLoudness get loudness => widget.loudness?.value ?? _ownLoudness;

  /// The level of a host that handed none ([MediaViewerTabHost.loudness]).
  ViewerLoudness _ownLoudness = const ViewerLoudness();

  /// The selection channel this viewer's canvas panel runs the cut on —
  /// the one handed in, or one of its own ([MediaViewerTabHost.selection]).
  CanvasSelectionCommands get _selection =>
      widget.selection ?? (_ownSelection ??= CanvasSelectionCommands());

  CanvasSelectionCommands? _ownSelection;

  void _setLoudness(ViewerLoudness next) => setState(() {
    final held = widget.loudness;
    if (held == null) {
      _ownLoudness = next;
    } else {
      held.value = next;
    }
  });

  /// 🚨★★★[PlaybackTransport] — this viewer is one of the things the app
  /// can be playing, so the actuation gate stops it with the same law it
  /// stops the canvas with (유저 09-07 `exclusive`, both directions).
  /// ⛔It answers from the run's clock and stops through [MediaRun.stop]; a
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

  /// What [picker] picks opens here — the dialog with none. Each way in
  /// names its own: the pill's 「파일 열기」 the widget's [filePicker], and
  /// files dropped here the files ([_openDropped]).
  Future<void> _openLooseFile(LooseFilePicker? picker) async {
    // 🚨EVERY PICKER SHOWS EVERY FILE (유저 2026-08-29) — the refusal is a
    // notice after the pick, not a greyed-out file in the dialog. The
    // widget's own [filePicker] seam answers in place of the dialog, and
    // what it answers is refused the same way.
    //
    // 🗣️F-282-Q2 (유저 2026-10-09, 가): the viewer's Open stays a look, and
    // takes the kinds the one door sends to the import window — sound
    // included. ↩️Its list left sound out, 「the one deliberate absence」,
    // after the viewer had learned to open one as its waveform (09-08).
    final path = await openSupportedFile(
      context,
      supportedExtensions: FileTypeGroups.poolMedia.extensions ?? [],
      picker: picker,
    );
    if (path == null || !mounted) {
      return;
    }
    final kind = mediaAssetKindForPath(path);
    if (kind == null) {
      return;
    }
    widget.onRequestPicked?.call(MediaViewerRequest(path: path, kind: kind));
  }

  /// Files dropped here from the OS ([OsFileDropEntrance]), opened as the
  /// 「파일 열기」 opens what it picks.
  void _openDropped(List<String> paths) =>
      unawaited(_openLooseFile(() async => paths));

  /// Whether the file on screen can still be added to the media pool —
  /// false for one already in it, and for nothing at all.
  bool get _canRegister {
    final path = _currentRequest?.path;
    return path != null &&
        widget.onRegisterAsset != null &&
        !(widget.isPathRegistered?.call(path) ?? true);
  }

  Future<void> _registerCurrent() async {
    final path = _currentRequest?.path;
    if (path == null) {
      return;
    }
    await widget.onRegisterAsset?.call(path);
    // This panel does not listen to the session (a viewer that rebuilt on
    // every session notify would be the expensive kind of panel). Ask again
    // ourselves once the import is done, so the button goes quiet the
    // moment its work is.
    if (mounted) {
      setState(() {});
    }
  }

  /// Every widget key in this panel, built from [MediaViewerTabHost.viewerId]
  /// — the ONE place the prefix is applied, so a second viewer cannot end
  /// up sharing a key with the first.
  String _key(String suffix) => '${widget.viewerId}-$suffix';

  /// 🚨★★★**THE PANEL WEARS WHAT ITS DOCUMENT IS** (F-289, 유저 2026-10-06:
  /// 「이 캔버스 베이스패널은 형식에 따라 나누기로하자. 뷰어패널이라도 pdf면
  /// 타임시트나 콘티용지패널이랑 같은 알약쓰고, 한장짜리면 그 알약조차
  /// 없애고, 동영상같은거면 아래에 재생ui 넣고」): a document that RUNS — its
  /// pages advance by themselves, or it sounds ([MediaRun.canPlay]) — gets
  /// the transport under it ([_player]); a book gets the page turner there
  /// instead (F-383); a single picture gets neither ([_transport]).
  ///
  /// ↩️Every document wore the strip on the left edge, and one that ran had
  /// PLAY at the head of it — a movie turned its frames by the page
  /// chevrons.
  bool get _runs => _run.canPlay;

  /// The band under the document stood on — page [pageIndex] of
  /// [pageCount]: the transport of one that runs, the page turner of a
  /// book ([CanvasTransportBand.ofPages] — none below two pages).
  CanvasTransportBand? _transport(
    BuildContext context,
    int pageIndex,
    int pageCount,
  ) => _runs
      ? _player(context)
      : CanvasTransportBand.ofPages(
          context,
          keyPrefix: widget.viewerId,
          page: viewerPage(pageIndex, pageCount),
          onTurnTo: _turnToPage,
        );

  /// The transport under a document that runs. What it counts is the run's
  /// ([MediaRun.frameCount]): a movie's own frames, and a sound's length in
  /// the project's frames — the frames the import window counts the same
  /// sound in.
  CanvasTransportBand _player(BuildContext context) {
    final rate = widget.session.projectSettings.projectFrameRate;
    final frameCount = _run.frameCount(rate);
    return CanvasTransportBand(
      height: TransportBar.heightIn(context, range: false),
      child: TransportBar(
        keyPrefix: _key('transport'),
        frameCount: frameCount,
        currentFrame: _run.frameAt(rate).clamp(0, frameCount - 1),
        playing: _run.playing,
        onSeek: (frame) => _run.seekToFrame(frame, rate),
        onPlayPause: _run.toggle,
        sound: _run.soundCell(onChanged: _setLoudness),
      ),
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
  /// own space. An outline on the desk between pages cuts nothing, and says
  /// so as every cut that finds nothing does ([cutIntoTheHand]).
  void _cutFromPage(CanvasSelectionRegion outline) {
    final book = _book;
    if (book == null) {
      final page = _page;
      _cuts = _cuts.then((_) => _cut(outline, page));
      return;
    }
    final page = _pageUnder(book, outline);
    if (page == null) {
      final slot = widget.cutPieceSlot;
      if (slot != null) {
        cutIntoTheHand(null, slot.hold);
      }
      return;
    }
    final at = book.pageRect(page).topLeft;
    final onPage = outline.translated(dx: -at.dx, dy: -at.dy);
    _cuts = _cuts.then((_) => _cut(onPage, page));
  }

  /// The page of [book] the [outline] covers most — null when it covers
  /// none.
  int? _pageUnder(PageStack book, CanvasSelectionRegion outline) {
    final b = outline.selectedBounds;
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

  Future<void> _cut(CanvasSelectionRegion outline, int page) async {
    final slot = widget.cutPieceSlot;
    final document = _document;
    final pageCount = _pageCount;
    if (!mounted || slot == null) {
      return;
    }
    if (document == null || pageCount == 0) {
      cutIntoTheHand(null, slot.hold);
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
        region: outline,
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
    if (!mounted || generation != _generation) {
      return;
    }
    cutIntoTheHand(piece, slot.hold);
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
  /// otherwise — each asked for at the zoom the view has, or at its own
  /// pixels when it is made of them ([mediaViewerRenderScaleFor]) — none
  /// while [asking] is false (a fit is about to replace the view).
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
  List<({int page, Rect rect, ui.Image? image})> _pagesShown(
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
        final scale = mediaViewerRenderScaleFor(
          coverage,
          document.pageSize(entry.page),
          drawnAtAnySize: document.drawnAtAnySize,
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
        (
          page: entry.page,
          rect: entry.rect,
          image: _rasters.imageOf(entry.page),
        ),
    ];
  }

  /// The ink windows of [pages] — each page's whole picture, of the file the
  /// project carries as [carry].
  List<SheetInkWindow> _inkWindowsOf(
    List<({int page, Rect rect, ui.Image? image})> pages, {
    required String carry,
    required bool drawnAtAnySize,
  }) {
    final scale = viewerInkScale(drawnAtAnySize: drawnAtAnySize);
    return [
      for (final shown in pages)
        viewerInkWindow(
          carry: carry,
          page: shown.page,
          rect: shown.rect,
          scale: scale,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final request = _currentRequest;
    final pageCount = _pageCount;
    final pageIndex = _pageShown;
    _drawnName = _shownName;
    final carry = _shownAsset;
    _drawnCarry = carry?.carriedAs;

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
    // F-382: and a file this viewer has framed before stands as it left it.
    final framing = paper != null && _loadedToken != null && _needsFraming
        ? CanvasAutoFrameRequest(
            token: _loadedToken!,
            rect: book?.pageRect(pageIndex) ?? paper,
            view: switch (request) {
              final shown? => widget.keptFraming?.call(shown.path),
              null => null,
            },
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

    // Zero unless this viewer is the one lying on the app's floor — the
    // tree answers it, as it answers the canvas (`MainCanvasBrushHost`): a
    // viewer in a rail is not under the provider. ↩️The floor's viewer was
    // handed none, so its bars stood under the panels lying on it.
    final floor = CanvasFloorInsets.maybeOf(context);
    final transport = _transport(context, pageIndex, pageCount);

    // I-114: the brush writes on the page of a file the project carries
    // while the switch is on — a sheet's drawing ([SheetStrokeHold] and all).
    final ink = widget.inkController;
    final inkTool = widget.brushTool;
    final inkable = ink != null && inkTool != null && viewerInksOn(carry);
    final drawing = inkable && widget.brushAllowed;
    if (_drawingOn && !drawing) {
      _strokeHold.releaseAfterFrame();
    }
    _drawingOn = drawing;

    /// The panel running [tool] — the workspace's while [inks], the armed
    /// cut's, or none.
    BrushCanvasPanel panelWith(
      ValueListenable<BrushToolState>? tool, {
      bool inks = false,
    }) => BrushCanvasPanel(
      floorCover: floor?.insets ?? EdgeInsets.zero,
      floorRightRailBand: floor?.rightRailBand,
      floorBottomOverlaySpan: floor?.bottomOverlaySpan ?? 0,
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
      // false affordance. ↩️Drawable while the page takes ink (I-114) under
      // a tool a sheet runs (F-420).
      toolCursorsEnabled: inks,
      // F-77 (유저: 「뷰어패널 열린거 없으면 확대나 스크롤바같은 조작 버튼
      // 비활성화」): with no file open there is no view to operate.
      hasContentToView: request != null,
      // 🗣️I-14 (유저 2026-09-11): 「뷰어패널은 기본적으로 드로잉모드
      // 존재안하니 한손가락 핑거시 팬」 — whatever the one-finger slot says,
      // and so a finger drives no tool here: the cut takes a pen or a mouse.
      // ↩️While the page takes ink under a tool a sheet runs (I-114 ·
      // F-420) the finger is a sheet's: the slot's own answer.
      oneFingerAction: inks ? null : CanvasTouchDragAction.navigate,
      // 🗣️F-420 (유저 2026-10-20: 「선택한 도구가 작동하게하도록」), a
      // sheet's law: while the page takes ink, a tool a sheet runs
      // ([sheetRunsTool]) is the panel's — the brush and the eraser in the
      // ink's windows, a shape landed in the window it is pressed in
      // ([SheetShapeScope] in [build]); the armed cut runs as it does with
      // the ink off (F-380); and under any other tool nothing here can act,
      // so a press moves the page (F-80). ↩️While it took ink the panel ran
      // no tool and the windows laid the brush under whatever was in hand.
      brushToolState: tool,
      runsTheSelectedTool: tool != null,
      // ⚠️THE SECOND OF ITS KIND: [SheetCanvasPanel] answers its drawingOn
      // with these same answers — the finger, the press, the tool in hand,
      // the shapes, the hold, and the let-go after the frame in [build].
      // Two, so not shared yet (the rule of three); a third host taking ink
      // lifts them into one.
      contentStrokeActive: drawing ? _strokeHold : null,
      contentShapeTargetAt: _shapes.at,
      contentTakesPressAt: _shapes.takesPressAt,
      // F-179 (유저 2026-09-25: 「타임시트패널등 캔버스 베이스 패널엔
      // 페이스트보드가 없다는 뜻임」): the viewer is one of those panels —
      // F-201 names it one.
      canvasBase: true,
      // F-315: a file is looked at a pixel to a pixel.
      oneToOneOnPill: true,
      onCutContent: widget.cutPieceSlot == null ? null : _cutFromPage,
      // F-380: the cut runs on a channel as the canvas's does — a polygon's
      // vertices are kept there ([MediaViewerTabHost.selection]).
      selectionCommands: _selection,
      autoFrame: framing,
      // 유저 확정 2026-08-13 (⑤): opening a file is the one verb that stays
      // on the pill. Register and swap are a session's worth of taps
      // between them, and every control that stays costs the pill 44px of
      // budget it then takes from the page navigation on a narrow rail.
      // 🗣️I-83-Q1 (유저 2026-10-09): 「알약의 「파일 열기」 옆」 — closing
      // stands beside opening, at that cost; off while nothing is open.
      bottomBarLeading: [
        // At the head of the bar, as on every sheet; off on a file it cannot
        // write on (I-114), in its place.
        if (widget.onBrushAllowedChanged case final flip?)
          sheetBrushSwitch(
            allowed: drawing,
            onChanged: inkable ? flip : null,
            keyPrefix: widget.viewerId,
          ),
        if (widget.onRequestPicked != null)
          AppIconButton(
            keyValue: _key('open-file-button'),
            tooltip: strings.mediaViewerOpenFile,
            icon: const Icon(Icons.file_open_outlined),
            size: AppIconButtonSize.strip,
            onPressed: () => unawaited(_openLooseFile(widget.filePicker)),
          ),
        if (widget.onRequestClosed case final close?)
          AppIconButton(
            keyValue: _key('close-file-button'),
            tooltip: strings.mediaViewerCloseFile,
            icon: const Icon(Icons.close),
            size: AppIconButtonSize.strip,
            onPressed: request == null ? null : close,
          ),
      ],
      transport: transport,
      documentName: _drawnName,
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
            onSelected: () => unawaited(_registerCurrent()),
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
      // the entries when the BAR is built, not when the list opens. So
      // does whether a file is open: the close button is off without one.
      // And the brush switch's two answers.
      bottomBarHostToken: (
        pageIndex,
        pageCount,
        _canRegister,
        request != null,
        drawing,
        inkable,
      ),
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
              child: LayoutBuilder(
                builder: (context, box) {
                  final ratio = EffectiveDevicePixelRatio.of(context);
                  // Snapped ONCE, as a sheet's view is (P8): the pages and
                  // the ink over them land on one device grid.
                  final snapped = renderSnappedViewport(viewport, ratio);
                  final pages = _pagesShown(
                    context,
                    snapped,
                    box.biggest,
                    asking: !framingPending,
                  );
                  final carried = carry?.carriedAs;
                  final inkWindows = ink == null || carried == null
                      ? const <SheetInkWindow>[]
                      : _inkWindowsOf(
                          pages,
                          carry: carried,
                          drawnAtAnySize: document?.drawnAtAnySize ?? false,
                        );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Same shape and same reason as the conte and
                      // envelope pages: a light table that changes when
                      // you page or pan and not otherwise, which was being
                      // re-rastered on every frame the app produced for
                      // any reason at all.
                      StaticRaster(
                        debugLabel: _key('page'),
                        child: CustomPaint(
                          key: ValueKey<String>(_key('page')),
                          painter: ViewportPagesPainter(
                            pages: [
                              for (final shown in pages)
                                (rect: shown.rect, image: shown.image),
                            ],
                            // PDF paper is opaque white; a transparent
                            // image shows the checker-free paper too — the
                            // viewer is a light table, not a compositor.
                            ground: document != null
                                ? ViewportPageGround.paper
                                : ViewportPageGround.none,
                            viewport: snapped,
                            effectiveRatio: ratio,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      // The page's saved ink, over it (I-114) — but where a
                      // live window draws it.
                      if (ink != null && inkWindows.isNotEmpty)
                        RepaintBoundary(
                          child: CustomPaint(
                            key: ValueKey<String>(_key('ink')),
                            painter: ViewerInkPainter(
                              windows: inkWindows,
                              viewport: snapped,
                              effectiveRatio: ratio,
                              inkSurfaceFor: ink.surfaceOf,
                              liveInkKeys: {
                                if (drawing)
                                  for (final window in inkWindows) window.key,
                              },
                              repaint: ink,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      if (drawing)
                        ViewerInkOverlay(
                          key: ValueKey<String>(_key('ink-layer')),
                          keyPrefix: widget.viewerId,
                          controller: ink,
                          windows: inkWindows,
                          brushToolState: inkTool,
                          historyManager: widget.session.historyManager,
                          viewport: snapped,
                          strokeActive: _strokeHold,
                          cacheInvalidationSink: _cacheInvalidationSink,
                        ),
                      // The file still opening, a page on screen not
                      // drawn yet (F-315), or a run parked before a page
                      // that is not there, over the page it stands on —
                      // 🗣️F-499 (유저 2026-10-29): 「멈출땐 화면중앙에 그림은
                      // 유지한채 로딩 ui 띄우도록? 미디어플레이어들이
                      // 하는거처럼」, Q1 「뷰어만」.
                      if (document == null ||
                          pages.any((page) => page.image == null) ||
                          _run.buffering)
                        ViewerPageLoading(
                          key: ValueKey<String>(_key('loading')),
                        ),
                    ],
                  );
                },
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
                  painter: WaveformMarksPainter(
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
        : SlicedValueListenableBuilder<
            BrushToolState,
            (CanvasShapeKind?, bool)
          >(
            valueListenable: brushTool,
            slice: (tool) => (armedCutShape(tool), sheetRunsTool(tool.tool)),
            builder: (context, tool) => drawing && sheetRunsTool(tool.tool)
                ? panelWith(brushTool, inks: true)
                : panelWith(_toolFor(tool)),
          );

    final surface = ColoredBox(
      key: ValueKey<String>(_key('panel')),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      // Where the page ink's layer answers what takes a shape (F-420).
      child: SheetShapeScope(targets: _shapes, child: panel),
    );
    // 🗣️F-378 (유저 2026-10-17: 「윈도우등 os에서 드래그앤 드롭으로 파일을
    // 뷰어패널에 떨어트리면 바로 뷰어패널에서 열리도록. 서브뷰어던
    // 메인뷰어던」): a file dropped here from the OS opens here, as the
    // pill's 「파일 열기」 opens one — and is refused as it would be.
    return OsFileDropEntrance(
      onDrop: _openDropped,
      child: _poolEntrance(surface),
    );
  }

  /// [surface] with the place a pool row is dropped on over it — or as it
  /// is, for a host that takes none.
  Widget _poolEntrance(Widget surface) {
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
