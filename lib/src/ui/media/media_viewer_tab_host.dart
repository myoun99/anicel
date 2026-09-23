import '../widgets/empty_state_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show CanvasTouchDragAction;
import '../../models/canvas_shape_kind.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_piece.dart' show CutPiece;
import '../../models/rgba_image_bytes.dart';
import '../../models/canvas_viewport.dart';
import '../../models/media_asset.dart';
import '../../native/qa_native_engine.dart';
import '../../services/media/held_viewer_document.dart';
import '../../services/media/image_viewer_document.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/video_viewer_document.dart';
import '../../services/media/viewer_document.dart';
import '../../services/straight_rgba_image.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/cut_piece_lift.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/project_lookup.dart' show mediaKindCanCarrySound;
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/brush_tool_state.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../editor_session_manager.dart';
import '../playback/playback_transport.dart';
import '../dialogs/open_file_flow.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import 'audio_viewer_document.dart';
import 'media_asset_drag_data.dart';
import 'media_asset_drop_target.dart';
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
    this.position = 0,
    this.onPositionChanged,
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
  final int position;
  final ValueChanged<int>? onPositionChanged;

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

/// One lazily rendered page: the raster and the scale it was rendered at
/// (stale-while-revalidate — a wrong-scale image still draws while the
/// right one renders).
class _RenderedPage {
  const _RenderedPage({required this.scale, required this.image});

  final double scale;
  final ui.Image image;
}

/// What was last asked of the document for one (page, scale).
///
/// 🚨★★★**LANDED IS NOT A VALUE HERE — IT IS THE ABSENCE OF ONE**, because
/// a landed render lives in the page cache and this map is about what is
/// still owed. What this type exists to separate is the other two, which
/// were both spelled 「not in the set」 before 2026-09-08. See [_renders].
enum _RenderAsk {
  /// Out with the document, no answer yet.
  asking,

  /// The document refused this one. ⛔It is remembered until the play tick
  /// forgets it: asking again the instant it fails is a loop, and never
  /// asking again is a viewer that cannot recover when the frame becomes
  /// readable — and recovery is the law here (유저 2026-08-31, 「로드할때까지
  /// 멈춰있어야지」, which is a WAIT and not a surrender).
  failed,
}

class _MediaViewerTabHostState extends State<MediaViewerTabHost>
    implements PlaybackTransport {
  /// Commit sink required by the panel API; the viewer never invalidates
  /// playback caches.
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  MediaViewerRequest? get _currentRequest => widget.request.value;

  /// The open document, whatever medium it came from — 🪦there used to be
  /// a `_frames` list AND a `_pdf` handle here, and five places downstream
  /// had to ask which was live. See [ViewerDocument].
  ViewerDocument? _document;
  final Map<int, _RenderedPage> _pageCache = {};

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

  /// The render scale the last build chose. The buffer measures readiness
  /// in the unit [_pageCache] is keyed by, and only build knows the zoom —
  /// the timer that asks cannot work it out.
  double? _renderScale;

  /// True while the playhead is parked waiting for its cushion to refill.
  /// ⛔Reset with the cache: it is a fact about a document that is gone.
  bool _buffering = false;
  String? _message;

  /// What this device affords the page cache, and where a memory warning
  /// puts it — see [ViewerRasterBudget].
  ///
  /// ⚠️Built with the State, so a test that wants a tight one sets
  /// [ViewerRasterBudget.debugPageBytesOverride] BEFORE the panel mounts;
  /// pumping the same widget again reuses this State and this budget.
  final ViewerRasterBudget _budget = ViewerRasterBudget(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
  );

  /// What a cut's read holds while it is out (I-14): billed to [_budget]
  /// beside the page cache, and reported to the census with it.
  int _cutReadBytes = 0;

  /// The cut in flight — the next waits its turn rather than racing it for
  /// the budget.
  Future<void> _cuts = Future<void>.value();

  /// Drops cached pages, farthest from the one on screen first, until the
  /// cache fits [ViewerRasterBudget.byteBudget].
  ///
  /// 🚨[keeping] is never evicted. A raster that has just LANDED for a
  /// page already paged away from is itself the farthest entry, and an
  /// eviction that could drop it would throw away the render it was
  /// called to install — the old count-based drain excluded it for the
  /// same reason.
  ///
  /// ⚠️Bytes, not entries. Four pages meant a quarter of a gigabyte for a
  /// big PDF and under a megabyte for thumbnails; the bound has to be in
  /// the unit that runs out.
  /// How far a cached page is from being wanted again.
  ///
  /// 🚨**PLAYBACK ONLY MOVES FORWARD**, so a page already shown is never
  /// wanted again and is farther than any page ahead. Measuring both with
  /// `abs()` — which is what stood here — made the read-ahead buffer evict
  /// ITSELF to keep frames that had just been displayed: a page five ahead
  /// and a page five behind tied, and the tie went to whichever the map
  /// listed first.
  ///
  /// ⚠️Paging by hand is a different question and keeps `abs()`: someone
  /// stepping through a PDF is as likely to go back as forward.
  int _evictionDistance(int page) {
    if (!_playing) {
      return (page - _page).abs();
    }
    return page >= _page ? page - _page : _pageCount + (_page - page);
  }

  int _evictToBudget({required int keeping}) {
    var total = 0;
    for (final page in _pageCache.values) {
      total += ViewerRasterBudget.costOf(page.image);
    }
    // A cut's read is billed beside the pages (I-14), so they make room.
    while (total + _cutReadBytes > _budget.byteBudget &&
        _pageCache.length > 1) {
      // Two or more entries and at most one of them is [keeping], so a
      // candidate always exists and it is always in the map. Asserted with
      // `!` rather than guarded: a guard here would answer an impossible
      // case by silently LEAVING the cache over budget, which is the one
      // outcome this method exists to prevent.
      final farthest = _pageCache.keys
          .where((page) => page != keeping)
          .reduce(
            (a, b) => _evictionDistance(a) >= _evictionDistance(b) ? a : b,
          );
      final dropped = _pageCache.remove(farthest)!;
      total -= ViewerRasterBudget.costOf(dropped.image);
      dropped.image.dispose();
    }
    // The census cannot reach into this State, so the total goes to it —
    // see [RenderCaches.viewerRasterBytesByViewer]. Every path
    // that changes the cache ends here or in [_disposeContent].
    widget.session.renderCaches.viewerRasterBytesByViewer[widget.viewerId] =
        total + _cutReadBytes;
    return total;
  }

  /// The OS said memory is tight. The session already stood its own caches
  /// down; this is the viewer's share.
  void _onMemoryPressure() {
    if (!_budget.respondToMemoryPressure()) {
      return;
    }
    setState(() => _evictToBudget(keeping: _page));
  }

  /// Read-only here — the workspace holds it (see
  /// [MediaViewerTabHost.position]) and [_turnToPage] asks it to move.
  int get _page => widget.position;

  /// Guards every async landing against a newer load.
  int _generation = 0;

  /// The timer turning pages while playing, and null while stopped —
  /// 🚨the ONLY thing that says whether this viewer is playing, so a
  /// second flag cannot disagree with it ([[make-the-invariant-unrepresentable]]).
  ///
  /// ⚠️Write it through the setter below and nowhere else. [_playingFlips]
  /// has to fire for the actuation gate, and a notifier poked at the call
  /// sites would be exactly the second flag this comment forbids — here it
  /// cannot be written except by the assignment that changes the timer.
  Timer? _playTimerField;

  Timer? get _playTimer => _playTimerField;

  set _playTimer(Timer? timer) {
    _playTimerField?.cancel();
    _playTimerField = timer;
    _playingFlips.value = timer != null;
  }

  /// [isActiveListenable]: fires when this viewer starts or stops, and on
  /// nothing else — never per turned page (the gate wraps the whole editor).
  final ValueNotifier<bool> _playingFlips = ValueNotifier<bool>(false);

  /// This viewer's sound, or silence if the app has no audio device.
  ///
  /// ⚠️Built lazily against the session's conform store — the SAME store
  /// the timeline plays out of, so a file conformed for one is conformed
  /// for the other and nothing is decoded twice.
  late final ViewerSound _sound = widget.sound ?? ViewerSound(
    conformStore: widget.session.audioConformStore,
    resolveOutputDeviceName: () => widget
        .session
        .appSettings
        .audioSyncSettings
        .value
        .outputDeviceName,
  );

  /// Where the sound has got to, in seconds — the playhead's position on
  /// the waveform.
  ///
  /// 🚨It is read from the DEVICE every tick, never counted up here: the
  /// device counts samples handed to the hardware, so a playhead that
  /// follows it cannot drift from what is being heard. A local counter
  /// would be a second clock, and the timeline's transport spends its
  /// whole header explaining why there is only ever one.
  double _soundSeconds = 0;

  /// What has been asked of the document, one entry per (page, scale) —
  /// landings remove their own entry, so a stale landing can never wipe a
  /// newer one.
  ///
  /// 🚨★★★**A RENDER HAS THREE OUTCOMES AND THIS USED TO HAVE ROOM FOR
  /// TWO.** It was a `Set`, so ABSENT answered both 「nobody has asked」 and
  /// 「the last ask failed, so asking again right now is fine」 — and the
  /// failure arm below cleared the marker inside a `setState`. That rebuild
  /// re-entered `build`, which asks for the same page again, which fails
  /// again, which rebuilds: measured at eleven asks for one unreadable frame
  /// across three ticks, throttled by nothing but how fast the decoder can
  /// say no. On the tablets this app is written for
  /// ([[old-device-support-policy]]) that is a spinning CPU under a picture
  /// that is not moving.
  final Map<(int, double), _RenderAsk> _renders = {};

  /// Whether a render is out with the document right now.
  ///
  /// ⛔Not `_renders.isNotEmpty`: a FAILED entry is remembered until the
  /// next tick, and counting it as in-flight would stop the read-ahead from
  /// ever issuing anything again.
  bool get _rendering =>
      _renders.values.any((ask) => ask == _RenderAsk.asking);

  /// Token that changes once per successfully LOADED document — drives
  /// the panel's auto-reframe so a preserved deep zoom/pan from the
  /// previous asset can never leave the new one entirely off-screen.
  Object? _loadedToken;

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
    if (oldWidget.position != widget.position) {
      // 🚨★★★**TURNING A PAGE IS ASKING AGAIN**, and until now only a RUN
      // was. `_onPlayTick` was the sole place a refusal was forgotten, and
      // it exists only while `_playTimer` does — which needs a document
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
      _renders.removeWhere((_, ask) => ask == _RenderAsk.failed);
    }
  }

  @override
  void dispose() {
    widget.request.removeListener(_onRequestChanged);
    widget.session.memoryPressureTicks.removeListener(_onMemoryPressure);
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
    _playingFlips.dispose();
    super.dispose();
  }

  void _onRequestChanged() => _load(widget.request.value);

  void _disposeContent() {
    // A timer outliving its document would page a viewer that has none.
    _stopPlaying();
    for (final page in _pageCache.values) {
      page.image.dispose();
    }
    _pageCache.clear();
    _buffering = false;
    _renderScale = null;
    widget.session.renderCaches.viewerRasterBytesByViewer[widget.viewerId] = 0;
    _renders.clear();
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
    final strings = AppText.strings;
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
        // 🚨WHY, under the sentence that says WHAT. The engines answer with
        // a reason — 「this file has no readable video stream」, 「no decoder
        // for this codec」 — and this arm used to drop it on the floor, so
        // every unreadable file looked identical to every other one.
        // ⚠️The detail is the engine's own words and is not translated; the
        // export path made the same call with the encoder's.
        setState(() => _message = '${strings.mediaViewerLoadFailed}\n$error');
      }
      return;
    }
    if (!mounted || generation != _generation) {
      await document?.dispose();
      return;
    }
    setState(() {
      if (document == null) {
        // The honest-absence states, and each says WHICH absence: a build
        // without a PDF rasterizer or without a video reader is a missing
        // engine the user can act on (a different build), while audio has
        // no picture at all and never will. ⛔One message for all three
        // would send someone hunting for a codec they do not need.
        _message = switch (request.kind) {
          MediaAssetKind.pdf => strings.mediaViewerNoPdfRenderer,
          MediaAssetKind.video => strings.mediaViewerNoVideoDecoder,
          // 🪦Audio moved off this line in 2026-09-08: it HAS a picture now
          // (its waveform), so an absence here is a conform that could not
          // be built — a file this build cannot decode, which is the same
          // sentence a missing video reader gets.
          MediaAssetKind.audio => strings.mediaViewerNoAudioDecoder,
          MediaAssetKind.image => strings.mediaViewerCannotDisplay,
        };
      } else {
        _document = document;
        _loadedToken = generation;
      }
    });
    // The page request goes out on the build this setState causes; the
    // record lands after it, so the NEXT open of this document sees it.
    _rememberFramed();
  }

  /// Opens whatever [request] names, or null when this medium has nothing
  /// to show — the one place that knows which document a kind makes.
  ///
  /// 🚨★★★**WHERE THE BYTES ARE IS ASKED ONCE, NOT PER KIND** (유저
  /// 2026-09-11: 「막힌부분 파일 뭐든 관계없이 법 하나로 통일해서
  /// 해결하도록」). An arm here names only how its medium DECODES; where the
  /// bytes are is [_openOnItsBytes]'s one question for every kind that reads
  /// them.
  Future<ViewerDocument?> _openDocument(MediaViewerRequest request) async {
    switch (request.kind) {
      case MediaAssetKind.image:
        return _openOnItsBytes(request.path, ImageViewerDocument.open);
      case MediaAssetKind.pdf:
        return _openOnItsBytes(request.path, PdfRenderService.open);
      case MediaAssetKind.video:
        return _openOnItsBytes(request.path, VideoViewerDocument.open);
      case MediaAssetKind.audio:
        // 🪦This used to read 「Sound has no picture — the one medium that
        // stays absent」. 유저 2026-09-08: 「오디오파일도 열려야하고 …
        // 오디오는 그래서 파형을 보이게한다던가」. The picture of a sound is
        // its waveform, and the conform that draws one is the same conform
        // playback already builds — so this asks for it rather than making
        // anything.
        final peaks = await widget.session.audioConformStore.ensurePeaksFor(
          request.path,
        );
        return peaks == null
            ? null
            : AudioViewerDocument(
                peaks: peaks,
                color: AudioViewerDocument.ink,
              );
    }
  }

  /// [open] on [path]'s bytes, wherever the project keeps them
  /// ([ProjectFile.holdMediaBytes]: its own copy first, then the file it came
  /// from), HELD until the document has closed ([HeldViewerDocument]) — a
  /// PDF reads a page at a time and a movie a frame at a time, and no save
  /// may move or remove the bytes under them meanwhile.
  ///
  /// 🚨★★★**THE CARRIED COPY WINS OVER THE ORIGINAL, FOR EVERY KIND.**
  /// Carrying means 「품은 순간 데이터를 가지고있고 불변이었으면좋겠어서」
  /// (유저 2026-08-30), so an original edited or deleted after the import
  /// changes nothing the viewer shows.
  /// 🪦Images and PDFs used to read the ORIGINAL only, so a carried one
  /// whose original was gone — or a project opened on another machine —
  /// could not be viewed at all (card `carried-image-pdf-cannot-be-viewed`).
  /// 🪦And a movie read the original whenever it was still there: 「⛔The
  /// original wins whenever it is still there: an OS opening a file for
  /// itself beats any range wrapped around one」. It does, and it showed the
  /// EDITED file for a carried movie whose original had changed since.
  Future<ViewerDocument?> _openOnItsBytes(
    String path,
    Future<ViewerDocument?> Function(MediaByteSource source) open,
  ) async {
    final held = await widget.session.projectFile.holdMediaBytes(path);
    final ViewerDocument? document;
    try {
      document = await open(held.source);
    } on Object {
      held.release();
      rethrow;
    }
    if (document == null) {
      held.release();
      return null;
    }
    return HeldViewerDocument(document, held.release);
  }

  // --- Lazy rendering (§6-m: the visible page at the current zoom) ------

  void _ensurePageRendered(int pageIndex, double scale) {
    final document = _document;
    if (document == null) {
      return;
    }
    final cached = _pageCache[pageIndex];
    if (cached != null && cached.scale == scale) {
      return;
    }
    // One entry PER (page, scale): a shared single slot got wiped by
    // whichever render landed first, and the wipe re-issued duplicates
    // of work already queued on PDFium's serial worker.
    //
    // 🚨An entry of EITHER kind stops the ask — in flight means 「already
    // out」 and failed means 「not until the clock says so」. See [_renders].
    if (_renders.containsKey((pageIndex, scale))) {
      return;
    }
    _renders[(pageIndex, scale)] = _RenderAsk.asking;
    final generation = _generation;
    final pageSize = document.pageSize(pageIndex);
    unawaited(() async {
      final image = await decodedImageStillWanted(
        document.renderPage(
          pageIndex,
          width: (pageSize.width * scale).round().clamp(1, 1 << 13).toInt(),
          height: (pageSize.height * scale).round().clamp(1, 1 << 13).toInt(),
        ),
        wanted: () => mounted && generation == _generation,
        // ⛔NO `setState` on this road. Nothing the eye can see changed — the
        // page that was not there is still not there — and the rebuild is
        // exactly what made a refused frame ask again immediately, and
        // again, for as long as it kept being refused. The retry belongs to
        // the play tick, which is the clock that actually needs the frame.
        onFailed: () {
          if (mounted && generation == _generation) {
            _renders[(pageIndex, scale)] = _RenderAsk.failed;
          }
        },
      );
      if (image == null) {
        return;
      }
      setState(() {
        _renders.remove((pageIndex, scale));
        _pageCache[pageIndex]?.image.dispose();
        _pageCache[pageIndex] = _RenderedPage(scale: scale, image: image);
        _evictToBudget(keeping: pageIndex);
      });
    }());
  }

  // --- Paging ------------------------------------------------------------

  int get _pageCount => _document?.pageCount ?? 0;

  void _turnToPage(int page) {
    final count = _pageCount;
    final next = count <= 0 ? 0 : page.clamp(0, count - 1);
    if (next != _page) {
      widget.onPositionChanged?.call(next);
    }
  }

  /// Whether this document turns its own pages — 유저 2026-08-29:
  /// 「비디오 … 불러와서 재생가능하게」. It asks the DOCUMENT, so an
  /// animated GIF gets the same button a movie does; nothing here knows
  /// what a movie is.
  bool get _turnsItsOwnPages =>
      (_document?.framesPerSecond ?? 0) > 0 && _pageCount > 1;

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

  /// Whether there is anything to PLAY: pages that advance by themselves,
  /// or sound. 유저 2026-09-08: 「뷰어 소리 내는 범위는 싹 다야」 — so a
  /// waveform, which turns no pages at all, still gets the button.
  bool get _canPlay => _turnsItsOwnPages || _soundPath != null;

  bool get _playing => _playTimer != null;

  // --- The playback buffer (a player, not a slideshow) --------------------

  /// How much movie the read-ahead tries to keep ready, in SECONDS.
  ///
  /// 유저 2026-08-31: 「10초? 5초? **메모리 제한에 맞춰서 알아서** 로드하고」
  /// — so this is a ceiling, not the number that usually decides. On any
  /// document big enough to matter [_bufferAheadPages] hits the byte budget
  /// first, and the budget is the one that knows the device.
  static const double _bufferAheadSeconds = 5;

  /// Frames of read-ahead this document affords: whichever of the time
  /// window and the memory budget runs out first, and zero when nothing is
  /// playing (paging by hand needs no cushion).
  ///
  /// 🚨The budget has to hold the frame being LOOKED AT as well, so the
  /// read-ahead gets what is left after it. Without that subtraction the
  /// buffer fetches exactly enough to evict its own oldest entry, and the
  /// eviction re-issues the render it just dropped.
  int _bufferAheadPages() {
    final document = _document;
    final scale = _renderScale;
    if (document == null || scale == null || !_playing) {
      return 0;
    }
    final fps = document.framesPerSecond ?? 0;
    final size = document.pageSize(_page);
    final bytes = estimatedImageBytes(
      (size.width * scale).round().clamp(1, 1 << 13).toInt(),
      (size.height * scale).round().clamp(1, 1 << 13).toInt(),
    );
    final affordable = bytes <= 0 ? 0 : (_budget.byteBudget ~/ bytes) - 1;
    final window = (fps * _bufferAheadSeconds).round();
    return math.max(0, math.min(affordable, window));
  }

  /// How many consecutive frames from [from] are ready to draw at the scale
  /// the last build chose.
  int _readyFramesFrom(int from) {
    final scale = _renderScale;
    if (scale == null) {
      return 0;
    }
    var ready = 0;
    while (from + ready < _pageCount) {
      final cached = _pageCache[from + ready];
      if (cached == null || cached.scale != scale) {
        break;
      }
      ready += 1;
    }
    return ready;
  }

  /// What the buffer must hold before a parked playhead moves again.
  ///
  /// 유저 2026-08-31: 「로드가 안되고있으면 5초분만큼? 로드될떄까지 멈추는?」
  /// — resuming on ONE ready frame is the stutter this replaces: play a
  /// frame, run dry, park, play a frame. It is the SAME cushion
  /// [_bufferAheadPages] fills, capped by what is left of the movie so the
  /// last seconds do not become unplayable.
  int _resumeAfterFrames() =>
      math.min(_bufferAheadPages(), _pageCount - _page - 1);

  /// Issues the NEXT missing raster the playhead will need, one at a time.
  ///
  /// ⛔Not all of them at once: both decoders behind [ViewerDocument] are
  /// serial (PDFium runs one worker, and the video decoder's fast path is
  /// sequential reads), so a hundred outstanding requests would finish in
  /// the same order and the same time while holding a hundred futures. Each
  /// landing rebuilds, which issues the next — the queue walks forward on
  /// its own.
  void _fillPlaybackBuffer() {
    final scale = _renderScale;
    if (scale == null || _rendering) {
      return;
    }
    final ahead = _bufferAheadPages();
    for (var offset = 1; offset <= ahead; offset += 1) {
      final page = _page + offset;
      if (page >= _pageCount) {
        return;
      }
      final cached = _pageCache[page];
      if (cached == null || cached.scale != scale) {
        _ensurePageRendered(page, scale);
        return;
      }
    }
  }

  void _stopPlaying() {
    _playTimer = null;
    _buffering = false;
    // ⚠️Unconditional: [ViewerSound.stop] is idempotent, and every path out
    // of a run — the button, the actuation gate, a new file, a closed tab —
    // comes through here. A sound left playing under a stopped viewer is
    // the one failure this panel cannot show on screen.
    //
    // 🪦This line carried a 「MUTANT SURVIVES HERE」 note for one round: the
    // bench has no audio device, so nothing could be left playing and
    // deleting it changed nothing. The note was right about the bench and
    // wrong about the conclusion — the answer was a SEAM, not a shrug.
    // `MediaViewerTabHost.sound` is that seam, and the mutant dies now.
    _sound.stop();
  }

  /// One tick of a run that has SOUND and no pages: move the playhead to
  /// wherever the device has got to.
  ///
  /// 🚨★★★**THE PICTURE FOLLOWS THE SOUND, NEVER A COUNTER.** The device
  /// counts samples handed to the hardware, so a playhead read from it
  /// cannot drift from what is being heard however late this tick runs.
  /// Counting up here instead would be a second clock, which is the exact
  /// thing the timeline's device transport exists to avoid.
  void _followTheSound() {
    if (!mounted) {
      return;
    }
    final at = _sound.positionSeconds;
    if (at == null || _sound.ended) {
      // Ran out: a viewer that kept ticking on a silent device would say
      // 「재생 중」 to the actuation gate forever.
      setState(_stopPlaying);
      return;
    }
    setState(() => _soundSeconds = at);
  }

  /// 🚨★★★[PlaybackTransport] — this viewer is one of the things the app
  /// can be playing, so the actuation gate stops it with the same law it
  /// stops the canvas with (유저 09-07 `exclusive`, both directions).
  /// ⛔It answers from [_playTimer] and stops through [_stopPlaying]; a
  /// separate "am I playing" for the gate would be the per-surface check
  /// the gate exists to avoid.
  @override
  bool get isPlaying => _playing;

  @override
  void stop() {
    if (!_playing) {
      return;
    }
    setState(_stopPlaying);
  }

  @override
  ValueListenable<bool> get isActiveListenable => _playingFlips;

  /// How often a run of THIS document has something to do: once per
  /// frame while pages advance, and otherwise once per screen frame,
  /// which is all a playhead sliding along a waveform needs. Null = there
  /// is nothing to run.
  Duration? get _playTickPeriod {
    final fps = _document?.framesPerSecond ?? 0;
    if (_turnsItsOwnPages) {
      return Duration(microseconds: (1000000 / fps).round().clamp(1, 1000000));
    }
    return _soundPath == null ? null : const Duration(milliseconds: 16);
  }

  void _togglePlaying() {
    if (_playing) {
      setState(_stopPlaying);
      return;
    }
    final period = _playTickPeriod;
    if (period == null) {
      return;
    }
    final soundPath = _soundPath;
    setState(() {
      // From the top when the playhead is already at the end: pressing play
      // on the last frame has to DO something, and the only sensible
      // something is to play it again.
      if (_page >= _pageCount - 1) {
        _turnToPage(0);
      }
      if (soundPath != null) {
        _soundSeconds = 0;
        _sound.play(soundPath, fromSeconds: 0);
      }
      // ⛔A run with neither pages to turn nor sound coming out is a timer
      // saying 「재생 중」 to the actuation gate while nothing happens — and
      // the gate would then eat the next press for it. Standing down is
      // silent BY DESIGN (no audio device, a conform still landing), so
      // this is the shape that keeps a stand-down from becoming a lie.
      if (!_turnsItsOwnPages && !_sound.isCarrying) {
        return;
      }
      _playTimer = Timer.periodic(period, (_) => _onPlayTick());
    });
  }

  /// One tick of a run.
  ///
  /// 🚨★★★**AND THE RETRY CLOCK.** A frame the decoder refused is forgotten
  /// here and nowhere else, so it is asked for again at the rate the movie
  /// actually needs it — once per frame time — instead of as fast as the
  /// decoder can keep saying no. See [_renders] for what that cost.
  ///
  /// ⛔The fill has to be driven from here rather than left to the next
  /// build: while the buffer is dry [_turnThePage] returns WITHOUT a
  /// `setState`, so a parked viewer rebuilds for nothing and the walk
  /// forward would have no one to start it. That is why forgetting the
  /// failure is not enough on its own.
  void _onPlayTick() {
    if (!mounted) {
      return;
    }
    _renders.removeWhere((_, ask) => ask == _RenderAsk.failed);
    if (_turnsItsOwnPages) {
      _turnThePage();
    } else {
      _followTheSound();
    }
    _fillPlaybackBuffer();
  }

  /// 🚨★★★**THE PLAYHEAD WAITS. IT DOES NOT WALK PAST A FRAME THAT IS NOT
  /// THERE — AND NEITHER DOES THE SOUND.**
  ///
  /// This used to be 「best effort, deliberately」: the page advanced on the
  /// clock and whichever raster had landed was drawn. What that produced
  /// was a picture standing still while the playhead moved — and a held
  /// picture cannot be told apart from a hold the animator DREW, which is
  /// the one judgement this panel exists to support. 유저 2026-08-31:
  /// 「유지하지말고 로드할때까지 멈춰있어야지」, and 「그림을 유지한다는게
  /// 아니라 그 곳에 멈춘다는거야」.
  ///
  /// ⚠️The CANVAS does the opposite and that is also right: it judges
  /// TIMING against sound, so it holds real time and drops frames —
  /// `AudioPlaybackSync` says so in one line, 「frames drop, time never
  /// stretches」.
  ///
  /// 🪦That last paragraph used to end 「This is a player looking at
  /// reference, where nothing is riding on the clock, so it buffers」, and
  /// as of 2026-09-08 something IS riding on it: the movie's own
  /// soundtrack. The law did not change — it reached further. A buffer
  /// that runs dry now holds the SOUND at the same instant, so the two
  /// stutter together and come back in step; letting the sound run on
  /// would leave the picture to catch up by dropping frames, which is the
  /// behaviour this surface was given its law to refuse.
  void _turnThePage() {
    if (_page >= _pageCount - 1) {
      setState(_stopPlaying);
      return;
    }
    final ready = _readyFramesFrom(_page + 1);
    if (_buffering) {
      // ⛔Not「one frame is ready, go」: that plays a frame, runs dry
      // and parks again, which is a stutter rather than playback.
      if (ready < _resumeAfterFrames()) {
        return;
      }
      _sound.resume(_soundSeconds);
      setState(() => _buffering = false);
    } else if (ready < 1) {
      // Remember where the sound was, because that is where BOTH pick up.
      _soundSeconds = _sound.positionSeconds ?? _soundSeconds;
      _sound.hold();
      setState(() => _buffering = true);
      return;
    }
    _turnToPage(_page + 1);
  }

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
      page: (
        index: pageIndex,
        count: pageCount,
        readout: '${pageIndex + 1} / $pageCount',
      ),
      onTurnTo: _turnToPage,
      leading: [
        // 🚨PLAY sits with the page controls, not in a strip of its own:
        // playing IS turning pages, and the user asked for 「최대한 통일」.
        // ⛔It is present only when the document turns its own pages — the
        // same rule this whole strip already follows (유저 확정 ⑥: a still
        // image gets no strip rather than a permanently disabled one).
        if (_canPlay)
          AppIconButton(
            keyValue: _key('play-button'),
            tooltip: _playing ? strings.menuPause : strings.menuPlay,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            size: AppIconButtonSize.strip,
            onPressed: _togglePlaying,
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
  static BrushToolState? _toolStateFor(BrushToolState workspaceTool) {
    final shape = armedCutShape(workspaceTool);
    return shape == null
        ? null
        : _cutTools.putIfAbsent(
            shape,
            () => BrushToolState.defaults.copyWith(
              tool: CanvasTool.cut,
              cutShape: shape,
            ),
          );
  }

  static final Map<CanvasShapeKind, BrushToolState> _cutTools = {};

  /// A finished cut outline over the page on screen: read its box at the
  /// page's OWN size and hold it as the cut tool's piece.
  ///
  /// 🗣️유저 2026-09-11: 「원본크기로 잘라냄」 — 「34%의 크기가 스탬프
  /// 크기값이 100%이 되는게 아니라, 제대로 100% 해상도만큼」. The outline
  /// arrives in document units whatever the zoom, and the read is in those
  /// same units, so the piece is the source's own pixels and the stamp's
  /// 100% is that size.
  void _cutFromPage(CanvasSelectionShape shape) {
    _cuts = _cuts.then((_) => _cut(shape));
  }

  Future<void> _cut(CanvasSelectionShape shape) async {
    final slot = widget.cutPieceSlot;
    final document = _document;
    final pageCount = _pageCount;
    if (!mounted || slot == null || document == null || pageCount == 0) {
      return;
    }
    final pageIndex = _page.clamp(0, pageCount - 1);
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
      _cutReadBytes = bytes;
      held = _evictToBudget(keeping: pageIndex);
    });
    if (held + bytes > _budget.byteBudget) {
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
      _cutReadBytes = 0;
      _evictToBudget(keeping: _page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final request = _currentRequest;
    final pageCount = _pageCount;
    final pageIndex = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);

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
    final waveformSeconds = _turnsItsOwnPages || _soundPath == null
        ? null
        : widget.session.audioConformStore.durationSecondsFor(_soundPath!);

    // The lazy render for the visible page, at the current zoom's tier.
    //
    // 🚨★★★**IMAGES COME THROUGH HERE NOW.** They used to skip the tier
    // entirely and draw a decode of the ORIGINAL file, which is the 17×
    // the card measured. Nothing about the tier was image-specific — it
    // was only ever written inside an `if (pdf)`.
    ui.Image? pageImage;
    if (document != null && pageCount > 0) {
      // 🚨The tier is chosen from DEVICE coverage, not from the render
      // zoom. The viewer is a document view, so R11 excludes it from the
      // UI scale by DIVIDING its render zoom when the scale goes up — so
      // reading the raw zoom made raising the interface LOWER the tier
      // while the page deliberately stayed the same size on screen: same
      // dimensions, visibly softer, and the only thing the user changed was
      // how big the chrome is.
      final zoom = widget.viewport?.zoom ?? 1.0;
      final scale = viewerRenderScaleFor(
        CanvasZoomScale.of(context).display(zoom),
        docSize,
      );
      // 🚨THE SCALE AXIS ONLY. [_RenderedPage] says a wrong-SCALE image
      // draws while the right one renders — a blurrier render of the SAME
      // page is not a lie about which frame this is.
      //
      // 🪦A page-axis twin stood here and drew the LAST page when this
      // one's raster had not landed. It was answering the white flashes
      // 유저 2026-08-31 reported 「첫 재생때 … 흰 화면이 엄청나게
      // 깜빡이면서 재생됨」, and it answered them by making the picture lie
      // instead. The flashes are gone for the right reason now: the
      // playhead does not reach a frame that is not there, so what is on
      // screen is the frame the playhead is on.
      _renderScale = scale;
      _ensurePageRendered(pageIndex, scale);
      _fillPlaybackBuffer();
      pageImage = _pageCache[pageIndex]?.image;
    }

    final message = request == null ? strings.mediaViewerEmpty : _message;

    BrushCanvasPanel panelWith(BrushToolState? toolState) => BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: CanvasSize(
        width: docSize.width.ceil().clamp(1, 1 << 14).toInt(),
        height: docSize.height.ceil().clamp(1, 1 << 14).toInt(),
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
      brushToolState: toolState ?? BrushToolState.defaults,
      // F-80: with no cut armed nothing here can act on a press, so it
      // moves the page instead.
      runsTheSelectedTool: toolState != null,
      onCutContent: widget.cutPieceSlot == null ? null : _cutFromPage,
      // Reframe ONCE per loaded document: the workspace-owned viewport
      // survives asset switches, and a deep zoom/pan from a large scan
      // would otherwise leave a small next document entirely off-screen
      // — a blank panel this viewer promises never to show.
      // 🚨THE TOKEN IS THE DOCUMENT, NOT THE LOAD. It used to be this
      // State's own load counter, and a State dies with the panel — so
      // reopening minted a fresh one and the fit ran again over a view the
      // user had set. What the slot remembers is what makes 「once per
      // document」 true across a close.
      autoFrame: message == null && _loadedToken != null && _needsFraming
          ? CanvasAutoFrameRequest(
              token: _loadedToken!,
              rect: Rect.fromLTWH(0, 0, docSize.width, docSize.height),
            )
          : null,
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
      fitFocusRect: message == null
          ? Rect.fromLTWH(0, 0, docSize.width, docSize.height)
          : null,
      contentOverride: (context, viewport) => Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
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
              child: StaticRaster(
                debugLabel: _key('page'),
                child: CustomPaint(
                  key: ValueKey<String>(_key('page')),
                  painter: _MediaPagePainter(
                    image: pageImage,
                    docSize: docSize,
                    // PDF paper is opaque white; a transparent image
                    // shows the checker-free paper too — the viewer is a
                    // light table, not a compositor.
                    paperFill: document != null,
                    viewport: viewport,
                    effectiveRatio: EffectiveDevicePixelRatio.of(context),
                  ),
                  child: const SizedBox.expand(),
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
                    atSeconds: _soundSeconds,
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
            builder: (context, tool) => panelWith(_toolStateFor(tool)),
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
    required this.image,
    required this.docSize,
    required this.paperFill,
    required this.viewport,
    required this.effectiveRatio,
  });

  /// The page raster; null draws the paper alone (a PDF page still
  /// rendering).
  final ui.Image? image;

  /// Document space — the image draws scaled INTO this rect, so a
  /// higher-tier PDF raster stays sharp under zoom.
  final ui.Size docSize;

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
    final docRect = Rect.fromLTWH(0, 0, docSize.width, docSize.height);
    if (paperFill) {
      canvas.drawRect(docRect, Paint()..color = const Color(0xFFFFFFFF));
    }
    final page = image;
    if (page != null) {
      canvas.drawImageRect(
        page,
        Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
        docRect,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  Object get props => (image, docSize, paperFill, viewport, effectiveRatio);
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
