part of 'frame_picture_view.dart';

/// 🚨★★★A CEL DRAWN ON LIVE, SHOWN BY THE ENGINE ON A SCREEN OF ITS OWN
/// (board the-screen-premultiplies-ram-tiles-to-show-them (A)): [painter]'s
/// cel as it stands — the stroke in flight on it with it — laid by the
/// engine ([EngineStackScreen]) and shown through a texture of its own, by
/// the box a frame's picture goes up through ([_RenderFrameScreen]). Each
/// change is laid where it lands ([StackedFrame.movedSince] →
/// [EngineStackScreen.compose] over that alone), and no picture of a tile
/// is made on this thread.
///
/// ↩️A sheet's ink drew each tile's picture, which for a tile the engine
/// keeps was its pixels read back, premultiplied on the CPU and uploaded
/// again — at every step of a stroke for each tile the step changed.
///
/// No picture store keeps it, nothing makes it ahead and no run plays it:
/// a sheet's ink is no cut's frame, so none of [FramePictureView]'s keys,
/// only its screen.
class LiveCelScreen extends StatefulWidget {
  const LiveCelScreen({
    super.key,
    required this.cel,
    required this.painter,
    required this.viewport,
    this.placement,
    required this.panel,
  });

  /// The cel [painter] draws.
  final BrushFrameKey cel;

  /// The cel as the brush view writing on it shows it live: its surface,
  /// and the stroke in flight over it ([BitmapSurfacePainter.overlayModel]).
  final BitmapSurfacePainter painter;

  /// The cel's pixels to this screen's box.
  final CanvasViewport viewport;

  /// Where the cel is laid in its own pixels before [viewport] shows it —
  /// none where it lies as it is.
  final LayerPlacement? placement;

  /// Where the panel lies over this screen's box, in the box's own space:
  /// what of the cel the screen holds ([_holdsOver]). The box is the
  /// window's own, laid with the paper — so a pan moves it, and draws
  /// nothing.
  final Rect panel;

  /// Whether a window at [box] on a panel of [panel] — the panel's space —
  /// is worth a screen: within the margin a screen spares past the panel's
  /// edge ([_screenMargin]), so one comes up before it is seen.
  static bool meets(Rect box, Size panel, double devicePixelRatio) =>
      box.overlaps(
        (Offset.zero & panel).inflate(_screenMargin / devicePixelRatio),
      );

  @override
  State<LiveCelScreen> createState() => _LiveCelScreenState();

  /// What the engine keeps for every cel shown so, on the screens of all
  /// of them up now ([EngineStackScreen.bytes]): no store keeps them, so
  /// the census reads them here.
  static int get keptBytes => _LiveCelScreenState._up.fold(
    0,
    (sum, state) => sum + (state._laidOn?.screen.bytes ?? 0),
  );
}

class _LiveCelScreenState extends State<LiveCelScreen> implements _FrameFeed {
  /// The screens up now, for what they keep ([LiveCelScreen.keptBytes]).
  static final Set<_LiveCelScreenState> _up = {};

  late StackedFrame _frame = _stood();

  /// The screen the cel is laid on, and the engine tools it was made with
  /// — made again on the app's next engine.
  ({EngineStackScreen screen, EngineFrameTools tools})? _laidOn;

  /// What of the cel the screen holds, to measure its next change from —
  /// null where nothing is laid on it, or what moved cannot be told: all
  /// of it is laid at the next paint.
  LiveSurfaceTokens? _held;

  /// Where the cel moved since it was last laid.
  Rect? _moved;

  /// Counts the lays of the whole cel, so one that failed late is known
  /// from one laid since.
  int _wholeLays = 0;

  /// The place this screen shows in, where one marks its frames' waits.
  FramesWaiting? _place;

  /// Ticks when the engine's tools open.
  final ValueNotifier<int> _repaint = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _up.add(this);
    if (appEngineFrameToolsOpen == null) {
      unawaited(
        appEngineFrameTools.then<void>(
          (_) {
            if (mounted) {
              _repaint.value += 1;
            }
          },
          onError: (Object error, StackTrace stack) =>
              _report((error, stack), 'opening the engine a cel is shown on'),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _place = FrameWaitPlace.of(context);
  }

  @override
  void didUpdateWidget(LiveCelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.painter, widget.painter) ||
        oldWidget.cel != widget.cel ||
        oldWidget.placement != widget.placement) {
      // Measured against what the screen holds at the next paint: a
      // painter handed anew over the same tiles moves nothing.
      _frame = _stood();
    }
  }

  @override
  void dispose() {
    _up.remove(this);
    _place?.says(this, waits: false);
    ShownCels.instance.hide(this);
    _laidOn?.screen.free();
    _repaint.dispose();
    super.dispose();
  }

  /// The cel as one row on no paper, the painter's.
  StackedFrame _stood() => StackedFrame.of(
    [
      CompositeLeaf(
        CanvasActiveLayerRow(
          opacity: 1,
          frameKey: widget.cel,
          placement: widget.placement,
        ),
      ),
    ],
    page: (
      canvasSize: widget.painter.surface.canvasSize,
      pasteboardReach: PasteboardReach.none,
      paintPaper: false,
      paperBackground: ProjectBackground.defaultBackground,
    ),
    storedRowOf: (_) => null,
    bareRowOf: (_) => null,
    live: (
      rows: (
        activeSurfacePainter: widget.painter,
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  );

  @override
  void _catchUp() {
    final held = _held;
    if (held == null) {
      return;
    }
    final moved = _frame.movedSince(held);
    if (!moved.located) {
      _held = null;
      _moved = null;
      return;
    }
    _held = moved.now;
    if (moved.dirty case final dirty? when !dirty.isEmpty) {
      _moved = _moved?.expandToInclude(dirty) ?? dirty;
    }
  }

  @override
  bool _hasAFrame(StackedFrame? asItStands) =>
      asItStands != null && appEngineFrameToolsOpen != null;

  @override
  void _show(
    StackedFrame? frame,
    GpuTarget target,
    (int, int) size,
    _OnTheTexture on,
  ) {
    final (:viewport, :devicePixelRatio, :corner) = on;
    final screen = _screen();
    if (_held == null) {
      final lay = _wholeLays += 1;
      _laid(screen.compose(frame!), whole: lay);
      _held = frame.tokens;
      _moved = null;
    } else if (_moved case final moved?) {
      _laid(screen.compose(frame!, changed: moved));
      _moved = null;
    }
    screen.show(
      target,
      size,
      viewport: viewport,
      devicePixelRatio: devicePixelRatio,
      corner: corner,
    );
  }

  /// The screen the cel is laid on, made on the engine's tools open now —
  /// nothing on it yet where it is made anew.
  EngineStackScreen _screen() {
    final tools = appEngineFrameToolsOpen!;
    if (_laidOn case (:final screen, tools: final made)
        when identical(made, tools)) {
      return screen;
    }
    _laidOn?.screen.free();
    _held = null;
    final screen = EngineStackScreen(tools.composite, tools.letters);
    _laidOn = (screen: screen, tools: tools);
    return screen;
  }

  /// Reports a lay that failed once the GPU had it, and lays the whole cel
  /// again at the next paint — the screen keeps no canvas it failed on.
  /// [whole] is the count of a whole cel's lay, which a later one makes
  /// moot.
  void _laid(Future<void> laid, {int? whole}) => unawaited(
    laid.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (whole == null || whole == _wholeLays) {
          _held = null;
        }
        _report((error, stack), 'laying a cel drawn on live');
      },
    ),
  );

  /// 🗣️gpu-canonical-store-Q12 (유저 2026-11-10): 「캔버스 자리에 준비 중
  /// 표시를 둔다」 — the one answer of [FramePictureView._waitsAtPaint], for
  /// the ways a cel's screen is kept from the screen: the engine's tools
  /// still to be opened, or kernels still to be compiled.
  @override
  void _waitsAtPaint({required bool refused}) => _place?.says(
    this,
    waits: appEngineFrameToolsOpen == null || refused,
  );

  @override
  Widget build(BuildContext context) {
    // It says which cel it shows — the one the steps of an undo are read
    // ahead for — and that it draws no picture of a tile: the engine lays
    // the cel from its tiles, as the drawing canvas's stack does
    // (`BrushCanvasPanel`).
    ShownCels.instance.show(this, widget.cel.cel, pictured: null);
    return _FrameScreen(
      view: this,
      shown: null,
      asItStands: _frame,
      ground: null,
      cutAtCanvas: null,
      viewport: widget.viewport,
      devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      panel: widget.panel,
      repaint: Listenable.merge([_repaint, _frame.changes]),
      overlays: null,
      together: null,
      leftUp: null,
    );
  }
}
