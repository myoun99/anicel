import '../core/collection_equality.dart';
import '../core/frozen_collections.dart';
import 'brush_bitmap_materialization_history_entry.dart';

/// Internal session-local bitmap materialization undo/redo state.
///
/// This is not the production user-facing brush undo source of truth.
/// User-visible brush undo order belongs to UnifiedUndoHistory; this state only
/// supports legacy/dev bitmap surface materialization snapshots while that
/// bridge remains in use.
class BrushBitmapMaterializationHistoryState {
  BrushBitmapMaterializationHistoryState({
    Iterable<BrushBitmapMaterializationHistoryEntry> undoEntries = const [],
    Iterable<BrushBitmapMaterializationHistoryEntry> redoEntries = const [],
  }) : _undoEntries = frozenList<BrushBitmapMaterializationHistoryEntry>(
         undoEntries,
       ),
       _redoEntries = frozenList<BrushBitmapMaterializationHistoryEntry>(
         redoEntries,
       );

  final List<BrushBitmapMaterializationHistoryEntry> _undoEntries;
  final List<BrushBitmapMaterializationHistoryEntry> _redoEntries;

  List<BrushBitmapMaterializationHistoryEntry> get undoEntries => _undoEntries;

  List<BrushBitmapMaterializationHistoryEntry> get redoEntries => _redoEntries;

  bool get canUndo => _undoEntries.isNotEmpty;

  bool get canRedo => _redoEntries.isNotEmpty;

  bool get isEmpty => _undoEntries.isEmpty && _redoEntries.isEmpty;

  int get undoCount => _undoEntries.length;

  int get redoCount => _redoEntries.length;

  BrushBitmapMaterializationHistoryEntry? get latestUndoEntry =>
      _undoEntries.isEmpty ? null : _undoEntries.last;

  BrushBitmapMaterializationHistoryEntry? get latestRedoEntry =>
      _redoEntries.isEmpty ? null : _redoEntries.last;

  BrushBitmapMaterializationHistoryState copyWith({
    Iterable<BrushBitmapMaterializationHistoryEntry>? undoEntries,
    Iterable<BrushBitmapMaterializationHistoryEntry>? redoEntries,
  }) {
    return BrushBitmapMaterializationHistoryState(
      undoEntries: undoEntries ?? _undoEntries,
      redoEntries: redoEntries ?? _redoEntries,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushBitmapMaterializationHistoryState &&
          listEquals(other._undoEntries, _undoEntries) &&
          listEquals(other._redoEntries, _redoEntries);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(_undoEntries), Object.hashAll(_redoEntries));

  @override
  String toString() =>
      'BrushBitmapMaterializationHistoryState(undoEntries: $_undoEntries, '
      'redoEntries: $_redoEntries)';
}
