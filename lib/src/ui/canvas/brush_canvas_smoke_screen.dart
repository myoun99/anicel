import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:flutter/material.dart';

import '../../services/brush_stroke_commit_data.dart';
import '../../models/brush_frame_key.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame_composite_cache_key.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_tile_cache_key.dart';
import '../../models/playback_preview_cache_key.dart';
import '../../models/project_id.dart';
import '../../models/track_id.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import 'brush_edit_canvas_input_settings.dart';
import 'interactive_brush_canvas_smoke_host.dart';
import '../input/control_press_claim.dart';

class BrushCanvasSmokeScreen extends StatefulWidget {
  const BrushCanvasSmokeScreen({
    super.key,
    this.layerId = const LayerId('smoke-layer'),
    this.frameId = const FrameId('smoke-frame'),
    this.inputSettings = BrushEditCanvasInputSettings.defaults,
    this.canvasSize,
    this.tileSize = 16,
    this.showTransparentBackground = true,
    this.showDebugStatus = true,
  });

  final LayerId layerId;
  final FrameId frameId;
  final BrushEditCanvasInputSettings inputSettings;
  final CanvasSize? canvasSize;
  final int tileSize;
  final bool showTransparentBackground;
  final bool showDebugStatus;

  @override
  State<BrushCanvasSmokeScreen> createState() => _BrushCanvasSmokeScreenState();
}

class _BrushCanvasSmokeScreenState extends State<BrushCanvasSmokeScreen> {
  late BrushFrameEditingCoordinator _coordinator;
  late BrushEditCanvasInputSettings _inputSettings;
  late _RecordingCacheInvalidationSink _cacheInvalidationSink;
  var _sessionRevision = 0;
  String _debugOperation = 'none';

  @override
  void initState() {
    super.initState();
    _coordinator = _createCoordinator();
    _inputSettings = widget.inputSettings;
    _cacheInvalidationSink = _RecordingCacheInvalidationSink();
  }

  @override
  void didUpdateWidget(covariant BrushCanvasSmokeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.inputSettings != oldWidget.inputSettings) {
      _inputSettings = widget.inputSettings;
    }

    if (widget.layerId != oldWidget.layerId ||
        widget.frameId != oldWidget.frameId ||
        widget.canvasSize != oldWidget.canvasSize ||
        widget.tileSize != oldWidget.tileSize) {
      _resetSession(debugOperation: 'reset');
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey<String>('brush-canvas-smoke-screen'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            key: const ValueKey<String>('brush-canvas-smoke-screen-controls'),
            spacing: 8,
            runSpacing: 8,
            children: [
              ControlPressClaim(
                onPressed: _undo,
                child: TextButton(
                  key: const ValueKey<String>('brush-canvas-smoke-screen-undo'),
                  onPressed: silentPress(_undo),
                  child: const Text('Undo'),
                ),
              ),
              ControlPressClaim(
                onPressed: _redo,
                child: TextButton(
                  key: const ValueKey<String>('brush-canvas-smoke-screen-redo'),
                  onPressed: silentPress(_redo),
                  child: const Text('Redo'),
                ),
              ),
              ControlPressClaim(
                onPressed: () => _resetSession(debugOperation: 'reset'),
                child: TextButton(
                  key: const ValueKey<String>(
                    'brush-canvas-smoke-screen-reset',
                  ),
                  onPressed: silentPress(
                    () => _resetSession(debugOperation: 'reset'),
                  ),
                  child: const Text('Reset'),
                ),
              ),
              ControlPressClaim(
                onPressed: () => _setColor(0xFFFF0000),
                child: TextButton(
                  key: const ValueKey<String>(
                    'brush-canvas-smoke-screen-color-red',
                  ),
                  onPressed: silentPress(() => _setColor(0xFFFF0000)),
                  child: const Text('Red'),
                ),
              ),
              ControlPressClaim(
                onPressed: () => _setColor(0xFF0000FF),
                child: TextButton(
                  key: const ValueKey<String>(
                    'brush-canvas-smoke-screen-color-blue',
                  ),
                  onPressed: silentPress(() => _setColor(0xFF0000FF)),
                  child: const Text('Blue'),
                ),
              ),
              ControlPressClaim(
                onPressed: () => _setColor(0xFF000000),
                child: TextButton(
                  key: const ValueKey<String>(
                    'brush-canvas-smoke-screen-color-black',
                  ),
                  onPressed: silentPress(() => _setColor(0xFF000000)),
                  child: const Text('Black'),
                ),
              ),
            ],
          ),
          InteractiveBrushCanvasSmokeHost(
            key: const ValueKey<String>('brush-canvas-smoke-screen-host'),
            initialSessionState: _coordinator.activeSessionState,
            layerId: widget.layerId,
            frameId: widget.frameId,
            inputSettings: _inputSettings,
            cacheInvalidationSink: _cacheInvalidationSink,
            sessionResetToken: _sessionRevision,
            showTransparentBackground: widget.showTransparentBackground,
            onSourceStrokeCommitted: _handleSourceStrokeCommitted,
          ),
          if (widget.showDebugStatus)
            Text(
              _debugStatusText,
              key: const ValueKey<String>(
                'brush-canvas-smoke-screen-debug-status',
              ),
            ),
        ],
      ),
    );
  }

  CanvasSize get _resolvedCanvasSize =>
      widget.canvasSize ?? const CanvasSize(width: 64, height: 64);

  BrushFrameEditingCoordinator _createCoordinator() {
    final frameKey = BrushFrameKey(
      projectId: const ProjectId('smoke-project'),
      trackId: const TrackId('smoke-track'),
      cutId: const CutId('smoke-cut'),
      layerId: widget.layerId,
      frameId: widget.frameId,
    );

    return BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: _resolvedCanvasSize,
        tileSize: widget.tileSize,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 256,
        deferredBakeRatio: 0.1,
      ),
    );
  }

  String get _debugStatusText {
    return 'operation: $_debugOperation, '
        'cacheInvalidations: ${_cacheInvalidationSink.totalCalls}, '
        'color: ${_colorHex(_inputSettings.color)}';
  }

  String _colorHex(int color) =>
      '0x${color.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}';

  final HistoryManager _history = HistoryManager();

  void _handleSourceStrokeCommitted(BrushStrokeCommitData strokeData) {
    setState(() {
      _history.execute(
        BrushStrokeHistoryCommand(
          coordinator: _coordinator,
          strokeData: strokeData,
          cacheInvalidationSink: _cacheInvalidationSink,
        ),
      );
      _sessionRevision += 1;
      _debugOperation = 'commit';
    });
  }

  void _undo() {
    setState(() {
      if (_history.canUndo) {
        _history.undo();
        _debugOperation = 'undo';
      } else {
        _debugOperation = 'undo-empty';
      }
      _sessionRevision += 1;
    });
  }

  void _redo() {
    setState(() {
      if (_history.canRedo) {
        _history.redo();
        _debugOperation = 'redo';
      } else {
        _debugOperation = 'redo-empty';
      }
      _sessionRevision += 1;
    });
  }

  void _resetSession({required String debugOperation}) {
    setState(() {
      _coordinator = _createCoordinator();
      _history.clear();
      _sessionRevision += 1;
      _cacheInvalidationSink = _RecordingCacheInvalidationSink();
      _debugOperation = debugOperation;
    });
  }

  void _setColor(int color) {
    setState(() {
      _inputSettings = _inputSettings.copyWith(color: color);
    });
  }
}

class _RecordingCacheInvalidationSink implements CacheInvalidationSink {
  final layerTiles = <LayerTileCacheKey>[];
  final frameComposites = <FrameCompositeCacheKey>[];
  final playbackPreviews = <PlaybackPreviewCacheKey>[];
  int brushFrames = 0;

  int get totalCalls =>
      brushFrames +
      layerTiles.length +
      frameComposites.length +
      playbackPreviews.length;

  @override
  void invalidateLayerTile(LayerTileCacheKey key) {
    layerTiles.add(key);
  }

  @override
  void invalidateBrushFrame(BrushFrameCacheInvalidation invalidation) {
    // R19 P3b: undo/redo restore surface snapshots and invalidate the
    // whole frame — counted so the debug status shows them working.
    brushFrames += 1;
  }

  @override
  void invalidateFrameComposite(FrameCompositeCacheKey key) {
    frameComposites.add(key);
  }

  @override
  void invalidatePlaybackPreview(PlaybackPreviewCacheKey key) {
    playbackPreviews.add(key);
  }
}
