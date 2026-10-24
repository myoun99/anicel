import 'package:flutter/foundation.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';

/// The unworked-block tint's source (R26 #44): the FACT and the EVENT that
/// changes it, in one place.
///
/// Whether a cel holds any picture lives in the brush store, not in the
/// immutable `Layer`, so it is DERIVED state — and derived state needs its
/// own signal or nothing downstream can know it moved. It had none: the
/// timeline only caught up when an unrelated edit announced app-wide, so a
/// freshly drawn block stayed grey until you switched layers or renamed a
/// frame.
///
/// [revision] is that signal. The row painters take it as a repaint
/// listenable and re-read [hasContent]; the grid's tile store takes its
/// value, because a baked tile whose resolver identity is unchanged would
/// otherwise keep serving the old tint back.
///
/// It replaces a pair of parameters threaded side by side through the panel,
/// the grids and the rows — the fact and a per-layer "empty cels" token
/// string rebuilt on every pass. One bundle, and the token's O(frames) join
/// per row per build goes with it.
@immutable
class TimelineCelContentSource {
  const TimelineCelContentSource({
    required this.hasContent,
    required this.cannotRead,
    required this.revision,
  });

  /// Whether the drawing block covering [frameIndex] holds any picture.
  /// True everywhere the tint does not apply (non-drawing sections).
  final bool Function(Layer layer, int frameIndex) hasContent;

  /// Whether the drawing block covering [frameIndex] shows a cel whose
  /// picture data could not be read — the block goes red
  /// (frame-picture-indicator-Q1 b). A file cel answers [hasContent] by
  /// what it is said to hold, so such a block reads as drawn without this.
  final bool Function(Layer layer, int frameIndex) cannotRead;

  /// Bumps whenever [hasContent] or [cannotRead] can have changed anywhere
  /// — and, row by row, where they can have ([CelContentRevision.forRow]).
  final CelContentRevision revision;
}

/// [TimelineCelContentSource.revision]: ONE number that moves whenever an
/// answer can have changed anywhere — what a baked tile is keyed on, and
/// what a listener that shows every row's answers hears — and, for each
/// row, the moves that can have changed THAT row's ([forRow]).
///
/// 🔬one-cel-turning-white-repaints-every-row (2026-10-24, the home page in
/// a widget test): the rows heard the one number, so a first stroke on an
/// empty cel — one block going grey → white — re-recorded all six rows'
/// painters, and a cut with dozens of rows pays that on the stroke's first
/// frame.
abstract interface class CelContentRevision implements ValueListenable<int> {
  /// A revision whose every move can have changed every row's answers —
  /// for a source whose one row shows cels of many rows (the conte row lays
  /// the whole film's cuts on one), and for a test that has no rows to name.
  factory CelContentRevision.everyRow(ValueListenable<int> revision) =
      _EveryRow;

  /// What fires when [row]'s answers can have changed: every move that
  /// names it, and every move that names no rows.
  Listenable forRow(LayerId row);
}

/// A [CelContentRevision] each move of which names the rows it concerns
/// ([bump]) — the session's (`LayerStack.celTintRevision`).
class RowNamingRevision extends ChangeNotifier implements CelContentRevision {
  @override
  int get value => _value;
  int _value = 0;

  /// The listeners of each row's [forRow], while something listens.
  final Map<LayerId, List<VoidCallback>> _rows = {};

  /// Moves the number for a change to the answers of [rows] — of every row
  /// when null.
  void bump({Set<LayerId>? rows}) {
    _value += 1;
    final heard = rows == null
        ? [for (final listeners in _rows.values) ...listeners]
        : [for (final row in rows) ...?_rows[row]];
    for (final listener in heard) {
      listener();
    }
    notifyListeners();
  }

  @override
  Listenable forRow(LayerId row) => _RowHears(this, row);

  @override
  void dispose() {
    _rows.clear();
    super.dispose();
  }
}

/// A row's side of a [RowNamingRevision]: its painter adds a listener when
/// it is attached and removes it when it is detached, so the revision holds
/// a row only while something shows it.
class _RowHears implements Listenable {
  const _RowHears(this._revision, this._row);

  final RowNamingRevision _revision;
  final LayerId _row;

  @override
  void addListener(VoidCallback listener) =>
      _revision._rows.putIfAbsent(_row, () => <VoidCallback>[]).add(listener);

  @override
  void removeListener(VoidCallback listener) {
    final listeners = _revision._rows[_row];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _revision._rows.remove(_row);
    }
  }
}

class _EveryRow implements CelContentRevision {
  const _EveryRow(this._revision);

  final ValueListenable<int> _revision;

  @override
  int get value => _revision.value;

  @override
  void addListener(VoidCallback listener) => _revision.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _revision.removeListener(listener);

  @override
  Listenable forRow(LayerId row) => _revision;
}
