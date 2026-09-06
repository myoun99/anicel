import 'dart:ui' show Offset;

import '../models/brush_settings.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/stroke.dart';
import '../models/stroke_id.dart';
import '../models/stroke_point.dart';
import '../services/commands/add_stroke_command.dart';
import 'layer_controller.dart';
import 'timeline_controller.dart';
import '../services/history_manager.dart';
import '../services/project_repository.dart';

/// Stroke input on the canvas, and the stroke-aware undo/redo over it.
///
/// A stroke's history entry remembers the FRAME it was drawn on, so an undo
/// from elsewhere first jumps the timeline there (origin: 833e74fc,
/// "Implement Phase 9 timeline layer integration"). Redo does not jump —
/// whether it should is a user question, so the two verbs stay two bodies
/// over one stack type rather than one body under a direction flag.
class CanvasController {
  CanvasController({
    required ProjectRepository repository,
    required HistoryManager historyManager,
    required FrameId frameId,
    LayerController? layerController,
    TimelineController? timelineController,
    BrushSettings? brushSettings,
  }) : _repository = repository,
       _historyManager = historyManager,
       _frameId = frameId,
       _layerController = layerController,
       _timelineController = timelineController,
       _brushSettings = brushSettings ?? BrushSettings();

  final ProjectRepository _repository;
  final HistoryManager _historyManager;
  final FrameId _frameId;
  final LayerController? _layerController;
  final TimelineController? _timelineController;
  final BrushSettings _brushSettings;
  final List<StrokePoint> _activePoints = <StrokePoint>[];
  final _strokeUndo = _StrokeEntryStack();
  final _strokeRedo = _StrokeEntryStack();

  int _strokeSequence = 0;

  FrameId get currentFrameId => _resolveActiveFrame()?.id ?? _frameId;

  List<Stroke> get strokes {
    if (_layerController != null && _timelineController != null) {
      return _resolveActiveFrame()?.strokes ?? const <Stroke>[];
    }

    return _findFrame(currentFrameId)?.strokes ?? const <Stroke>[];
  }

  List<StrokePoint> get activePoints => List.unmodifiable(_activePoints);

  bool get canUndo => _historyManager.canUndo;

  bool get canRedo => _historyManager.canRedo;

  void beginStroke(Offset position) {
    _activePoints
      ..clear()
      ..add(_pointFromOffset(position));
  }

  void updateStroke(Offset position) {
    if (_activePoints.isEmpty) {
      beginStroke(position);
      return;
    }

    _activePoints.add(_pointFromOffset(position));
  }

  void endStroke() {
    if (_activePoints.length < 2) {
      _activePoints.clear();
      return;
    }

    final stroke = Stroke(
      id: StrokeId(_nextStrokeId()),
      points: List<StrokePoint>.unmodifiable(_activePoints),
      brushSettings: _brushSettings,
    );

    final frameId = _resolveActiveFrame()?.id;
    if (frameId == null) {
      _activePoints.clear();
      return;
    }

    _historyManager.execute(
      AddStrokeCommand(
        repository: _repository,
        frameId: frameId,
        stroke: stroke,
      ),
    );
    final timelineController = _timelineController;
    if (timelineController != null) {
      _strokeUndo.push(
        timelineController.currentFrameIndex,
        _historyManager.undoCount,
      );
      _strokeRedo.clear();
    }
    _activePoints.clear();
  }

  void cancelStroke() {
    _activePoints.clear();
  }

  void undo() {
    if (!canUndo) {
      return;
    }

    final topStrokeEntry = _strokeUndo.peekAt(_historyManager.undoCount);
    final timelineController = _timelineController;
    if (topStrokeEntry != null &&
        timelineController != null &&
        timelineController.currentFrameIndex != topStrokeEntry.frameIndex) {
      timelineController.selectFrameIndex(topStrokeEntry.frameIndex);
      return;
    }

    final undoneStrokeEntry = _strokeUndo.popAt(_historyManager.undoCount);
    _historyManager.undo();
    if (undoneStrokeEntry != null) {
      _strokeRedo.push(undoneStrokeEntry.frameIndex, _historyManager.redoCount);
    }
  }

  void redo() {
    if (!canRedo) {
      return;
    }

    final redoneStrokeEntry = _strokeRedo.popAt(_historyManager.redoCount);
    _historyManager.redo();
    if (redoneStrokeEntry != null) {
      _strokeUndo.push(redoneStrokeEntry.frameIndex, _historyManager.undoCount);
    }
  }

  StrokePoint _pointFromOffset(Offset position) {
    return StrokePoint(x: position.dx, y: position.dy);
  }

  String _nextStrokeId() {
    _strokeSequence += 1;
    return 'stroke-${DateTime.now().microsecondsSinceEpoch}-$_strokeSequence';
  }

  List<LayerFrame> layerFramesForCut(CutId cutId) {
    final project = _repository.currentProject;
    if (project == null) {
      return const <LayerFrame>[];
    }

    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id != cutId) {
          continue;
        }

        final timelineController = _timelineController;
        if (timelineController == null) {
          return cut.layers
              .where((layer) => layer.frames.isNotEmpty)
              .map(
                (layer) => LayerFrame(layer: layer, frame: layer.frames.first),
              )
              .toList(growable: false);
        }

        return cut.layers
            .map((layer) {
              final frame = timelineController.resolveFrameForLayer(
                layer: layer,
              );
              if (frame == null) {
                return null;
              }
              return LayerFrame(layer: layer, frame: frame);
            })
            .nonNulls
            .toList(growable: false);
      }
    }

    return const <LayerFrame>[];
  }

  Frame? _resolveActiveFrame() {
    final layerController = _layerController;
    final timelineController = _timelineController;
    if (layerController == null || timelineController == null) {
      return null;
    }

    final layer = layerController.activeLayer;
    if (layer == null) {
      return null;
    }

    return timelineController.resolveFrameForLayer(layer: layer);
  }

  Frame? _findFrame(FrameId frameId) {
    final project = _repository.currentProject;
    if (project == null) {
      return null;
    }

    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          final frame = layer.frameById(frameId);
          if (frame != null) {
            return frame;
          }
        }
      }
    }

    return null;
  }
}

class LayerFrame {
  const LayerFrame({required this.layer, required this.frame});

  final Layer layer;
  final Frame frame;
}

/// One stroke on the history: the frame it was drawn on, and the history
/// DEPTH (the manager's undo count on the undo side, its redo count on the
/// redo side) at which it sat when it was pushed.
class _StrokeHistoryEntry {
  const _StrokeHistoryEntry({required this.frameIndex, required this.depth});

  final int frameIndex;
  final int depth;
}

/// The stroke side of one history stack — undo's or redo's, the same type
/// for both (the mirrored two-stack that KUndo2Stack and Flutter's
/// UndoHistory keep).
///
/// The top entry counts only while its depth still equals the manager's
/// current depth: a non-stroke command pushed above it makes the top stale,
/// and a stale top is nothing (the 2026-09-03 mutation campaign's survivor
/// was this comparison, flipped on the redo side).
class _StrokeEntryStack {
  final _entries = <_StrokeHistoryEntry>[];

  void push(int frameIndex, int depth) {
    _entries.add(_StrokeHistoryEntry(frameIndex: frameIndex, depth: depth));
  }

  /// The top entry when it sits at [depth]; null when the stack is empty or
  /// the top is stale.
  _StrokeHistoryEntry? peekAt(int depth) {
    if (_entries.isEmpty) {
      return null;
    }
    final entry = _entries.last;
    return entry.depth == depth ? entry : null;
  }

  /// Pops and returns the top entry when it sits at [depth]; a stale top
  /// stays where it is and null comes back.
  _StrokeHistoryEntry? popAt(int depth) {
    if (peekAt(depth) == null) {
      return null;
    }
    return _entries.removeLast();
  }

  void clear() => _entries.clear();
}
