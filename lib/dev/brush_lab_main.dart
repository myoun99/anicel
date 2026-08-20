// The BRUSH LAB (R13): the real app plus an in-app auto-stroker and a
// frame-timing logger — the on-device instrument behind "no lag, ever".
//
//   flutter run -d windows -t lib/dev/brush_lab_main.dart
//
// It boots the production HomePage and replays a real WORKFLOW: cels on six
// frames, onion skin on, strokes alternating brush/eraser while hopping
// between the frames — all through the REAL pointer pipeline
// (WidgetsBinding.handlePointerEvent) aimed at the CANVAS panel (never the
// timesheet's ink plane). Engine FrameTimings are bucketed into
// build/raster percentiles, janky-frame counts and process RSS — the curve
// that test-environment benchmarks cannot see. Nothing here runs in
// production; the entrypoint exists so any future brush regression is one
// command away from a measured verdict.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../src/models/brush_tip_mask.dart';
import '../src/services/persistence/anicel_project_archive.dart';
import '../src/models/canvas_resize_anchor.dart';
import '../src/models/canvas_size.dart';
import '../src/native/qa_native_engine.dart';
import '../src/ui/brush/brush_tool_state.dart';
import '../src/ui/canvas/bitmap_tile_image_cache.dart';
import '../src/ui/canvas/brush_edit_canvas_view.dart';
import '../src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import '../src/ui/editor_workspace.dart';
import '../src/ui/effective_device_pixel_ratio.dart';
import '../src/ui/home_page.dart';
import '../src/ui/theme/app_scroll_behavior.dart';
import '../src/ui/theme/app_theme.dart';
import '../src/ui/ui_scale.dart';
import '../src/ui/ui_scale_binding.dart';

void main() {
  // The lab measures the PRODUCTION pixel pipeline, so it boots the
  // production binding: the UI scale multiplies into the root device
  // matrix, and a lab on the plain binding would quantize against a grid
  // the app does not use.
  AnicelBinding.ensureInitialized();
  runApp(const _BrushLabApp());
}

class _BrushLabApp extends StatelessWidget {
  const _BrushLabApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anicel Brush Lab',
      theme: buildAppTheme(),
      // The lab is the same app with a driver on top — it gets the same
      // scrollbars, or it stops being a place to judge them from.
      scrollBehavior: const AppScrollBehavior(),
      // Same reason: without the scope every `DeviceGrid.of` below falls
      // back to MediaQuery, which reports the RAW view ratio and would
      // disagree with the binding above at any scale but 100%.
      builder: (context, child) => EffectiveDevicePixelRatioScope(
        uiScale: AppUiScale.value.value,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _BrushLabDriver(child: HomePage()),
    );
  }
}

class _BrushLabDriver extends StatefulWidget {
  const _BrushLabDriver({required this.child});

  final Widget child;

  @override
  State<_BrushLabDriver> createState() => _BrushLabDriverState();
}

/// One A/B phase of the lab run: which workflow ingredients are active.
class _LabPhase {
  const _LabPhase(
    this.label, {
    required this.hopFrames,
    required this.onion,
    required this.alternateTools,
    this.hopDissect = 0,
    this.bigBrush = false,
    this.flipMidStroke = false,
    this.heavyBrush = false,
    this.rapidRestrokes = false,
    this.collideSeekOnUp = false,
    this.collideRestroke = false,
    this.fillTaps = false,
    this.scrubCollide = false,
  });

  final String label;
  final bool hopFrames;
  final bool onion;
  final bool alternateTools;

  /// 1 = move the editing frame CURSOR only; 2 = additionally bump
  /// frameSeekCommitted WITHOUT changing the frame (the seek fan-out
  /// rebuild alone, same cel).
  final int hopDissect;

  /// R13-3: the user's reported worst case — a LARGE brush while flipping.
  /// Big strokes dirty many tiles, so every commit invalidates wide and the
  /// prerender warmer has maximal work to collide with.
  final bool bigBrush;

  /// R13-4: flip the frame WHILE the pen is down (the red-screen repro).
  /// The stroke must pin to its original cel and nothing may throw.
  final bool flipMidStroke;

  /// R15-③ heavy preset: max size + sampled tip mask + dual mask +
  /// canvas texture — the "이상한 브러시" the user actually paints with.
  final bool heavyBrush;

  /// R15-③: pen-up → next pen-down with barely a frame between — the
  /// commit-moment restroke the user reports as the remaining hitch.
  final bool rapidRestrokes;

  /// R16-⑤: input in the SAME frame the commit fires — a seek issued in
  /// the same event turn as pen-up (the "정확히 커밋 타이밍" collision).
  final bool collideSeekOnUp;

  /// R16-⑤: the next pen-down with ZERO settle frames after pen-up.
  final bool collideRestroke;

  /// R16-④: FILL tool taps (empty full-canvas cel + painted cel) with the
  /// tap's wall time and the buildFillDab probe decomposition logged.
  final bool fillTaps;

  /// R17-②: the ruler-scrub × commit collision — pen-up fires a scrub in
  /// the same turn, wiggles, commits the scrub, and the next stroke
  /// starts with barely a frame between.
  final bool scrubCollide;
}

class _BrushLabDriverState extends State<_BrushLabDriver> {
  static const int strokesPerBucket = 30;
  static const int bucketsPerPhase = 3;
  static const int movesPerStroke = 24;
  static const int frameCount = 6;

  /// Attribution ladder: each phase adds ONE ingredient, so the jank delta
  /// between consecutive phases names its cost. The hop-dissection phases
  /// fire the seek's PARTS separately (all public notifiers) to name which
  /// consumer owns the flip hitch.
  static const List<_LabPhase> phases = [
    _LabPhase(
      'strokes-only',
      hopFrames: false,
      onion: false,
      alternateTools: false,
    ),
    _LabPhase(
      'hop-cursor-only',
      hopFrames: false,
      onion: false,
      alternateTools: false,
      hopDissect: 1,
    ),
    _LabPhase(
      'hop-seek-same-frame',
      hopFrames: false,
      onion: false,
      alternateTools: false,
      hopDissect: 2,
    ),
    _LabPhase('hop-full', hopFrames: true, onion: false, alternateTools: false),
    _LabPhase('+onion', hopFrames: true, onion: true, alternateTools: false),
    _LabPhase(
      '+tools(full)',
      hopFrames: true,
      onion: true,
      alternateTools: true,
    ),
    _LabPhase(
      '+bigbrush-flipdraw',
      hopFrames: true,
      onion: true,
      alternateTools: false,
      bigBrush: true,
    ),
    _LabPhase(
      '+flip-mid-stroke',
      hopFrames: true,
      onion: true,
      alternateTools: false,
      flipMidStroke: true,
    ),
    _LabPhase(
      '+HEAVY-brush-flipdraw',
      hopFrames: true,
      onion: true,
      alternateTools: false,
      heavyBrush: true,
    ),
    _LabPhase(
      '+HEAVY-rapid-restrokes',
      hopFrames: false,
      onion: true,
      alternateTools: false,
      heavyBrush: true,
      rapidRestrokes: true,
    ),
    _LabPhase(
      '+HEAVY-collide-seek',
      hopFrames: false,
      onion: true,
      alternateTools: false,
      heavyBrush: true,
      collideSeekOnUp: true,
    ),
    _LabPhase(
      '+HEAVY-collide-restroke',
      hopFrames: false,
      onion: true,
      alternateTools: false,
      heavyBrush: true,
      rapidRestrokes: true,
      collideRestroke: true,
    ),
    _LabPhase(
      '+HEAVY-scrub-collide',
      hopFrames: false,
      onion: true,
      alternateTools: false,
      heavyBrush: true,
      scrubCollide: true,
    ),
    _LabPhase(
      '+fill-taps',
      hopFrames: false,
      onion: false,
      alternateTools: false,
      fillTaps: true,
    ),
  ];

  final List<int> _buildMicros = <int>[];
  final List<int> _rasterMicros = <int>[];
  late final TimingsCallback _timingsCallback;
  int _pointerId = 100;
  int _flutterErrors = 0;

  @override
  void initState() {
    super.initState();
    _timingsCallback = (List<FrameTiming> timings) {
      for (final timing in timings) {
        _buildMicros.add(timing.buildDuration.inMicroseconds);
        _rasterMicros.add(timing.rasterDuration.inMicroseconds);
      }
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    // Framework errors (the mid-stroke-flip red screen class) must be
    // COUNTED, not just splashed on screen — the bucket line reports them.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _flutterErrors += 1;
      _log('FLUTTER ERROR ${details.exception}');
      previousOnError?.call(details);
    };
    unawaited(_run());
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    super.dispose();
  }

  Future<void> _run() async {
    // Let the workspace restore/settle before driving it.
    await Future<void>.delayed(const Duration(seconds: 3));
    final workspaceElement = _findByType<EditorWorkspace>();
    if (workspaceElement == null) {
      _log('ABORT: EditorWorkspace not found');
      return;
    }
    final workspace = workspaceElement.widget as EditorWorkspace;
    final session = workspace.session;
    final brushTool = workspace.brushTool;
    _log('lab starting (phase-ladder mode)');
    // The load-fallback discipline is SILENT by design — the lab must not
    // be: a stale/missing DLL would quietly measure the Dart path.
    _log('native engine loaded: ${QaNativeEngine.instance != null}');

    // Optional worst-case canvas (R19: the user's 8000x8000 report):
    // --dart-define=BRUSH_LAB_CANVAS=8000 resizes the active cut before
    // the ladder runs, so every phase measures at that scale.
    const labCanvas = int.fromEnvironment('BRUSH_LAB_CANVAS');
    if (labCanvas > 0) {
      session.resizeActiveCutCanvas(
        CanvasSize(width: labCanvas, height: labCanvas),
        anchor: CanvasResizeAnchor.topLeft,
      );
      await _settleFrames(6);
      _log('lab canvas: ${labCanvas}x$labCanvas');
    }

    // Author a cel on each workflow frame.
    for (var frame = 0; frame < frameCount; frame += 1) {
      session.selectFrameIndex(frame);
      await _settleFrames(2);
      if (session.activeBrushEditorSelection == null) {
        session.createDrawingAtCurrentFrame();
        await _settleFrames(4);
      }
    }
    if (_canvasView() == null) {
      _log('ABORT: canvas-panel interactive view not found');
      return;
    }

    var strokeIndex = 0;
    for (final phase in phases) {
      // Per-layer onion (UI-R17 #5): the lab toggles the active layer.
      final onionLayer = session.activeLayer;
      if (onionLayer != null &&
          session.isLayerOnionSkinEnabled(onionLayer.id) != phase.onion) {
        session.toggleLayerOnionSkin(onionLayer.id);
      }
      if (phase.fillTaps) {
        await _runFillTaps(session, brushTool);
        // R27 repro: fill -> cut round trip -> decode coverage samples.
        await _runFillCutRoundTrip(session, brushTool);
        continue;
      }
      if (brushTool != null) {
        // HEAVY preset (R15-③): max size + sampled tip + dual + texture —
        // the worst realistic brush, per the user's testing directive.
        // Rebuilt from defaults so lighter phases really CLEAR the masks
        // (copyWith(null) keeps old values).
        brushTool.value = BrushToolState.defaults.copyWith(
          tool: CanvasTool.brush,
          size: phase.bigBrush || phase.heavyBrush
              ? BrushToolState.maxSize
              : BrushToolState.defaultSize,
          tipMask: phase.heavyBrush ? _labNoiseMask('lab-tip', 128) : null,
          dualMask: phase.heavyBrush ? _labNoiseMask('lab-dual', 64) : null,
          textureMask: phase.heavyBrush
              ? _labNoiseMask('lab-texture', 64)
              : null,
        );
      }
      session.selectFrameIndex(0);
      await _settleFrames(4);

      for (var bucket = 0; bucket < bucketsPerPhase; bucket += 1) {
        _buildMicros.clear();
        _rasterMicros.clear();
        final watch = Stopwatch()..start();
        for (var s = 0; s < strokesPerBucket; s += 1) {
          strokeIndex += 1;

          if (phase.hopFrames) {
            // Hop frames like real animation work (exercises the session
            // LRU too: 6 frames > the 4-session budget).
            session.selectFrameIndex(strokeIndex % frameCount);
            await _settleFrames(2);
          } else if (phase.hopDissect == 1) {
            session.editingFrameCursor.value = strokeIndex % frameCount;
            await _settleFrames(1);
            session.editingFrameCursor.value = 0;
            await _settleFrames(1);
          } else if (phase.hopDissect == 2) {
            session.editingFrameCursor.value = 0;
            session.frameSeekCommitted.value += 1;
            await _settleFrames(2);
          }

          if (phase.alternateTools && brushTool != null) {
            final tool = strokeIndex.isEven
                ? CanvasTool.brush
                : CanvasTool.eraser;
            if (brushTool.value.tool != tool) {
              brushTool.value = brushTool.value.copyWith(tool: tool);
              await _settleFrames(1);
            }
          }

          final canvas = _canvasView();
          if (canvas == null) {
            _log('ABORT: canvas lost mid-run');
            return;
          }
          final rect = _rectOf(canvas).deflate(30);
          final start = Offset(
            rect.left + (strokeIndex * 17.0) % (rect.width - 120),
            rect.top + (strokeIndex * 11.0) % (rect.height - 80),
          );
          await _stroke(
            start,
            // R13-4 repro: flip the frame at the stroke's midpoint with
            // the pen still down — the stroke must pin to its cel.
            midStrokeAction: phase.flipMidStroke
                ? () => session.selectFrameIndex((strokeIndex + 1) % frameCount)
                : null,
            // R15-③/R16-⑤: the commit-moment restroke — one frame (rapid)
            // or ZERO frames (collide) between pen-up and next pen-down.
            settleAfter: phase.collideRestroke || phase.scrubCollide
                ? 0
                : phase.rapidRestrokes
                ? 1
                : 6,
            // R16-⑤: a seek in the SAME event turn as the pen-up commit;
            // R17-②: a ruler SCRUB in that turn instead.
            onUpSameTurn: phase.collideSeekOnUp
                ? () => session.selectFrameIndex((strokeIndex + 1) % frameCount)
                : phase.scrubCollide
                ? () => session.scrubFrameIndex((strokeIndex + 1) % frameCount)
                : null,
          );
          if (phase.scrubCollide) {
            // The ruler wiggle right after the commit, released on the
            // SAME frame — then the next stroke starts immediately (the
            // user's "그리고 나서 룰러 확인하고 다시 그리기" loop).
            await _settleFrames(1);
            session.scrubFrameIndex(strokeIndex % frameCount);
            await _settleFrames(1);
            session.commitFrameScrub();
            await _settleFrames(1);
          }
        }
        watch.stop();
        _logBucket(phase.label, bucket, watch.elapsedMilliseconds);
      }
    }
    _log('lab DONE');
  }

  /// The CANVAS panel's interactive view — scoped under the main canvas
  /// brush host so the timesheet's ink plane can never be mistaken for it.
  Element? _canvasView() {
    final host = _findByKey(const ValueKey<String>('main-canvas-brush-host'));
    if (host == null) {
      return null;
    }
    Element? result;
    void visit(Element element) {
      if (result != null) {
        return;
      }
      if (element.widget is InteractiveBrushEditCanvasView) {
        result = element;
        return;
      }
      element.visitChildren(visit);
    }

    host.visitChildren(visit);
    return result;
  }

  /// R16-④: measured fill taps — an EMPTY full-canvas cel (the user's
  /// exact repro: "빈 프레임에 그냥 칠하기") alternating with a painted
  /// one, undone between taps so every tap floods the full region. The
  /// wall time prints per tap; the [labProbe]s inside buildFillDab print
  /// the decomposition.
  Future<void> _runFillTaps(
    dynamic session,
    ValueNotifier<BrushToolState>? brushTool,
  ) async {
    session.selectFrameIndex(7);
    await _settleFrames(2);
    if (session.activeBrushEditorSelection == null) {
      session.createDrawingAtCurrentFrame();
      await _settleFrames(4);
    }
    if (brushTool != null) {
      brushTool.value = BrushToolState.defaults.copyWith(tool: CanvasTool.fill);
      await _settleFrames(2);
    }
    for (var tap = 0; tap < 6; tap += 1) {
      final frame = tap.isOdd ? 0 : 7;
      session.selectFrameIndex(frame);
      await _settleFrames(4);
      final canvas = _canvasView();
      if (canvas == null) {
        _log('fill-taps ABORT: canvas lost');
        return;
      }
      final position = _rectOf(canvas).center + Offset(6.0 * tap, 0);
      final watch = Stopwatch()..start();
      final pointer = _pointerId++;
      _event(
        PointerDownEvent(
          pointer: pointer,
          kind: PointerDeviceKind.stylus,
          position: position,
          pressure: 0.8,
        ),
      );
      _event(
        PointerUpEvent(
          pointer: pointer,
          kind: PointerDeviceKind.stylus,
          position: position,
        ),
      );
      await _settleFrames(3);
      watch.stop();
      _log(
        'FILL tap#$tap frame=$frame '
        '(${frame == 7 ? 'EMPTY full-canvas' : 'painted'}) '
        '${watch.elapsedMilliseconds}ms wall',
      );
      session.historyManager.undo();
      await _settleFrames(4);
    }
    if (brushTool != null) {
      brushTool.value = BrushToolState.defaults.copyWith(
        tool: CanvasTool.brush,
      );
      await _settleFrames(2);
    }
  }

  /// R27 repro (user bug): 8K fill -> switch to another cut -> return.
  /// The store rematerializes the cel (all-new tile objects), so the
  /// editable painter must re-decode the whole canvas via budgeted
  /// chunks. Coverage samples every 500ms show whether convergence
  /// completes or stalls (the reported top-left-only display).
  Future<void> _runFillCutRoundTrip(
    dynamic session,
    ValueNotifier<BrushToolState>? brushTool,
  ) async {
    session.selectFrameIndex(7);
    await _settleFrames(2);
    if (session.activeBrushEditorSelection == null) {
      session.createDrawingAtCurrentFrame();
      await _settleFrames(4);
    }
    if (brushTool != null) {
      brushTool.value = BrushToolState.defaults.copyWith(tool: CanvasTool.fill);
      await _settleFrames(2);
    }
    final canvas = _canvasView();
    if (canvas == null) {
      _log('fill-roundtrip ABORT: canvas lost');
      return;
    }
    final position = _rectOf(canvas).center;
    final pointer = _pointerId++;
    _event(
      PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
        pressure: 0.8,
      ),
    );
    _event(
      PointerUpEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
      ),
    );
    // Let commit + settling + decode fully converge on the fill.
    for (var i = 0; i < 8; i += 1) {
      await _settleFrames(15);
    }
    _log('fill-roundtrip: filled, coverage ${_undecodedCount()}');

    final originalCutId = session.requireActiveCut.id;
    session.duplicateActiveCut();
    await _settleFrames(20);
    _log(
      'fill-roundtrip: after duplicate active=${session.requireActiveCut.id} '
      '(original=$originalCutId)',
    );
    session.selectCut(originalCutId);
    await _settleFrames(6);
    session.selectFrameIndex(7);
    await _settleFrames(6);
    for (var sample = 0; sample < 8; sample += 1) {
      await _settleFrames(30); // ~500ms per sample at 60fps.
      _log('fill-roundtrip sample#$sample undecoded=${_undecodedCount()}');
    }

    // Variant C — the USER'S EXACT RECIPE (R27): cut1 stays at ITS
    // size, a DUPLICATED cut2 resizes to 8000², gets a fresh frame +
    // fill, then cut1 -> cut2 round trip. Cut switches between
    // DIFFERENT-SIZED cuts run the host's global store resize - the
    // suspected bug engine.
    try {
      final cut1 = session.requireActiveCut.id;
      final smallSize = session.requireActiveCut.canvasSize;
      session.duplicateActiveCut(); // cut2 (active), same size as cut1.
      await _settleFrames(10);
      final cut2 = session.requireActiveCut.id;
      session.resizeActiveCutCanvas(
        const CanvasSize(width: 8000, height: 8000),
        anchor: CanvasResizeAnchor.topLeft,
      );
      await _settleFrames(10);
      session.selectFrameIndex(3);
      await _settleFrames(2);
      if (session.activeBrushEditorSelection == null) {
        session.createDrawingAtCurrentFrame();
        await _settleFrames(4);
      }
      final canvasC = _canvasView();
      if (canvasC == null) {
        _log('fill-roundtrip C ABORT: canvas lost');
        return;
      }
      final positionC = _rectOf(canvasC).center;
      final pointerC = _pointerId++;
      _event(
        PointerDownEvent(
          pointer: pointerC,
          kind: PointerDeviceKind.stylus,
          position: positionC,
          pressure: 0.8,
        ),
      );
      _event(
        PointerUpEvent(
          pointer: pointerC,
          kind: PointerDeviceKind.stylus,
          position: positionC,
        ),
      );
      for (var i = 0; i < 8; i += 1) {
        await _settleFrames(15);
      }
      _log(
        'fill-roundtrip C: filled on $cut2 (small=$smallSize) '
        'coverage ${_undecodedCount()} ${_contentSummary()}',
      );
      session.selectCut(cut1);
      await _settleFrames(12);
      session.selectCut(cut2);
      await _settleFrames(6);
      session.selectFrameIndex(3);
      await _settleFrames(6);
      for (var sample = 0; sample < 8; sample += 1) {
        await _settleFrames(30);
        _log(
          'fill-roundtrip C sample#$sample undecoded=${_undecodedCount()} '
          '${_contentSummary()}',
        );
      }
    } catch (error) {
      _log('fill-roundtrip C ABORT: $error');
    }

    // Variant B (R27): SAVED project + zero hot budget — the cel
    // free-drops to its FILE ref on the way out and rematerializes
    // from the .anicel on return (the R22-C tier the user's session
    // likely exercised via autosave).
    try {
      final savePath =
          '${Directory.systemTemp.path}/r27_repro_'
          '${DateTime.now().microsecondsSinceEpoch}$anicelProjectSuffix';
      await session.saveProjectToFile(savePath);
      session.brushFrameStore.hotCelByteBudget = 0;
      _log('fill-roundtrip B: saved + hot budget 0');
      session.duplicateActiveCut(); // Jumps to the copy = walk away.
      await _settleFrames(10);
      await session.brushFrameStore.drainTiering();
      session.selectCut(originalCutId);
      await _settleFrames(6);
      session.selectFrameIndex(7);
      await _settleFrames(6);
      for (var sample = 0; sample < 8; sample += 1) {
        await _settleFrames(30);
        _log('fill-roundtrip B sample#$sample undecoded=${_undecodedCount()}');
      }
    } catch (error) {
      _log('fill-roundtrip B ABORT: $error');
    }

    if (brushTool != null) {
      brushTool.value = BrushToolState.defaults.copyWith(
        tool: CanvasTool.brush,
      );
      await _settleFrames(2);
    }
  }

  /// The editable surface's geometry + how many tiles sit fully BEYOND
  /// a default-sized rect (2340x1654) — distinguishes "data truncated
  /// to the small canvas" from "display stalled" (R27 Variant C).
  String _contentSummary() {
    final element = _findByType<BrushEditCanvasView>();
    if (element == null) {
      return 'no-view';
    }
    final view = element.widget as BrushEditCanvasView;
    final surface = view.sessionState.canvasState.currentSurface;
    var beyond = 0;
    for (final tile in surface.tiles.values) {
      if (tile.coord.x * surface.tileSize >= 2340 ||
          tile.coord.y * surface.tileSize >= 1654) {
        beyond += 1;
      }
    }
    return 'canvas=${surface.canvasSize.width}x'
        '${surface.canvasSize.height} tiles=${surface.tiles.length} '
        'beyondSmallRect=$beyond';
  }

  /// Tiles of the editable view's CURRENT surface without a decoded
  /// image — nonzero steady state = the display bug.
  String _undecodedCount() {
    final element = _findByType<BrushEditCanvasView>();
    if (element == null) {
      return 'no-view';
    }
    final view = element.widget as BrushEditCanvasView;
    final tiles = view.sessionState.canvasState.currentSurface.tiles.values;
    var undecoded = 0;
    var total = 0;
    for (final tile in tiles) {
      total += 1;
      if (BitmapTileImageCache.instance.imageFor(tile) == null) {
        undecoded += 1;
      }
    }
    return '$undecoded/$total';
  }

  Future<void> _stroke(
    Offset start, {
    VoidCallback? midStrokeAction,
    int settleAfter = 6,
    VoidCallback? onUpSameTurn,
  }) async {
    final pointer = _pointerId++;
    _event(
      PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: start,
        pressure: 0.8,
      ),
    );
    var position = start;
    for (var move = 0; move < movesPerStroke; move += 1) {
      await _nextFrame();
      if (midStrokeAction != null && move == movesPerStroke ~/ 2) {
        midStrokeAction();
      }
      // Two samples per frame, like real pen input outpacing vsync.
      for (var sample = 0; sample < 2; sample += 1) {
        final previous = position;
        position += const Offset(3.5, 2.0);
        _event(
          PointerMoveEvent(
            pointer: pointer,
            kind: PointerDeviceKind.stylus,
            position: position,
            delta: position - previous,
            pressure: 0.8,
          ),
        );
      }
    }
    _event(
      PointerUpEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: position,
      ),
    );
    // R16-⑤: the collision — more work injected in the SAME event turn
    // the pen-up commit just ran in.
    onUpSameTurn?.call();
    // Let the pen-up fan-out (commit, decode burst, settle) land inside
    // the bucket's timings.
    await _settleFrames(settleAfter);
  }

  /// Deterministic pseudo-noise mask (biased 96..255 so coverage never
  /// vanishes) — the lab's stand-in for sampled/dual/texture brush tips.
  static BrushTipMask _labNoiseMask(String id, int size) {
    final alpha = Uint8List(size * size);
    var seed = 0x9E3779B9;
    for (var index = 0; index < alpha.length; index += 1) {
      seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
      alpha[index] = 96 + ((seed >> 16) % 160);
    }
    return BrushTipMask(id: id, size: size, alpha: alpha);
  }

  void _event(PointerEvent event) {
    WidgetsBinding.instance.handlePointerEvent(event);
  }

  Future<void> _settleFrames(int count) async {
    for (var i = 0; i < count; i += 1) {
      await _nextFrame();
    }
  }

  Future<void> _nextFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    return completer.future;
  }

  void _logBucket(String phase, int bucket, int elapsedMs) {
    final build = List<int>.of(_buildMicros)..sort();
    final raster = List<int>.of(_rasterMicros)..sort();
    String pct(List<int> sorted, double p) {
      if (sorted.isEmpty) {
        return '-';
      }
      final index = ((sorted.length - 1) * p).round();
      return (sorted[index] / 1000.0).toStringAsFixed(1);
    }

    final jank =
        raster.where((r) => r > 16000).length +
        build.where((b) => b > 16000).length;
    _log(
      '$phase bucket ${(bucket + 1) * strokesPerBucket} strokes | '
      'frames ${build.length} in ${elapsedMs}ms | '
      'build p50 ${pct(build, 0.5)} p95 ${pct(build, 0.95)} '
      'worst ${pct(build, 1.0)}ms | '
      'raster p50 ${pct(raster, 0.5)} p95 ${pct(raster, 0.95)} '
      'worst ${pct(raster, 1.0)}ms | '
      'jank>16ms $jank | '
      'errors $_flutterErrors | '
      'rss ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(0)}MB',
    );
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[brush-lab] $message');
  }

  Element? _findByKey(Key key) {
    Element? result;
    void visit(Element element) {
      if (result != null) {
        return;
      }
      if (element.widget.key == key) {
        result = element;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return result;
  }

  Element? _findByType<T extends Widget>() {
    Element? result;
    void visit(Element element) {
      if (result != null) {
        return;
      }
      if (element.widget is T) {
        result = element;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return result;
  }

  Rect _rectOf(Element element) {
    final box = element.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
