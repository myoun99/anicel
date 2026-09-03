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
  final List<_StrokeUndoEntry> _strokeUndoEntries = <_StrokeUndoEntry>[];
  final List<_StrokeRedoEntry> _strokeRedoEntries = <_StrokeRedoEntry>[];

  int _strokeSequence = 0;

  FrameId get currentFrameId => _resolveCurrentFrameId() ?? _frameId;

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

    final frameId = _resolveCurrentFrameId();
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
      _strokeUndoEntries.add(
        _StrokeUndoEntry(
          frameIndex: timelineController.currentFrameIndex,
          undoCount: _historyManager.undoCount,
        ),
      );
      _strokeRedoEntries.clear();
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

    final topStrokeEntry = _nextUndoableStrokeEntry();
    final timelineController = _timelineController;
    if (topStrokeEntry != null &&
        timelineController != null &&
        timelineController.currentFrameIndex != topStrokeEntry.frameIndex) {
      timelineController.selectFrameIndex(topStrokeEntry.frameIndex);
      return;
    }

    final undoneStrokeEntry = _popUndoableStrokeEntry();
    _historyManager.undo();
    if (undoneStrokeEntry != null) {
      _strokeRedoEntries.add(
        _StrokeRedoEntry(
          frameIndex: undoneStrokeEntry.frameIndex,
          redoCount: _historyManager.redoCount,
        ),
      );
    }
  }

  void redo() {
    if (!canRedo) {
      return;
    }

    final redoneStrokeEntry = _popRedoableStrokeEntry();
    _historyManager.redo();
    if (redoneStrokeEntry != null) {
      _strokeUndoEntries.add(
        _StrokeUndoEntry(
          frameIndex: redoneStrokeEntry.frameIndex,
          undoCount: _historyManager.undoCount,
        ),
      );
    }
  }

  _StrokeUndoEntry? _nextUndoableStrokeEntry() {
    if (_strokeUndoEntries.isEmpty) {
      return null;
    }

    final entry = _strokeUndoEntries.last;
    if (entry.undoCount != _historyManager.undoCount) {
      return null;
    }

    return entry;
  }

  _StrokeUndoEntry? _popUndoableStrokeEntry() {
    final entry = _nextUndoableStrokeEntry();
    if (entry == null) {
      return null;
    }

    return _strokeUndoEntries.removeLast();
  }

  _StrokeRedoEntry? _popRedoableStrokeEntry() {
    if (_strokeRedoEntries.isEmpty) {
      return null;
    }

    final entry = _strokeRedoEntries.last;
    if (entry.redoCount != _historyManager.redoCount) {
      return null;
    }

    return _strokeRedoEntries.removeLast();
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

  FrameId? _resolveCurrentFrameId() {
    final layerController = _layerController;
    final timelineController = _timelineController;
    if (layerController == null || timelineController == null) {
      return null;
    }

    final layer = layerController.activeLayer;
    if (layer == null) {
      return null;
    }

    final resolvedFrame = timelineController.resolveFrameForLayer(layer: layer);
    if (resolvedFrame != null) {
      return resolvedFrame.id;
    }

    return null;
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

class _StrokeUndoEntry {
  const _StrokeUndoEntry({required this.frameIndex, required this.undoCount});

  final int frameIndex;
  final int undoCount;
}

class _StrokeRedoEntry {
  const _StrokeRedoEntry({required this.frameIndex, required this.redoCount});

  final int frameIndex;
  final int redoCount;
}
