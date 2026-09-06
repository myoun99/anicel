part of '../editor_session_manager.dart';

/// VISIBILITY SOLO — showing one layer alone and remembering what the others
/// looked like so leaving solo restores them — as its own object: the
/// snapshot, the cut it was taken in, and the toggles that enter and leave.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and eight
/// session members touched. It reaches the session through `_session`.
class _VisibilitySolo {
  _VisibilitySolo(this._session);

  final EditorSessionManager _session;

  /// The legend eye's SOLO MODE (R4 #7 rework — REAL eye flips, user rule):
  /// engaging it snapshots every row's eye (cut layers + track SE), turns
  /// every non-active eye OFF and the active one ON — the rows show it and
  /// playback/fill follow naturally, exactly like clicking the eyes by
  /// hand (view-ish controller writes, not undoable). Switching the active
  /// layer re-solos; disengaging restores each eye from the snapshot.
  /// Leaving the cut exits the mode (restoring first) — the snapshot is
  /// cut-scoped.
  bool _layerVisibilitySoloEnabled = false;

  Map<LayerId, bool>? _visibilitySoloSnapshot;

  CutId? _visibilitySoloCutId;

  bool get layerVisibilitySoloEnabled => _layerVisibilitySoloEnabled;

  void toggleLayerVisibilitySolo() {
    if (_layerVisibilitySoloEnabled) {
      exitVisibilitySolo();
    } else {
      _layerVisibilitySoloEnabled = true;
      _visibilitySoloCutId = _session.editingSession.activeCutId;
      _visibilitySoloSnapshot = {
        for (final layer in _session.layers) layer.id: layer.isVisible,
      };
      _applyVisibilitySolo();
    }
    _session.notifyChanged();
  }

  /// Re-solos to the CURRENT active layer. Rows born during the solo join
  /// the snapshot with their pre-flip eye so exiting restores them too.
  void _applyVisibilitySolo() {
    final activeId = _session.activeLayerId;
    if (activeId == null) {
      return;
    }
    final stack = _session.layers;
    // 🚨THE ANCESTORS STAY ON. Solo means "show this row alone", and a row
    // inside a folder is not shown by its own eye — turning every OTHER row
    // off turned its folders off with them, so soloing a row inside a folder
    // hid the very thing it was soloing. On the editing canvas that read as
    // "nothing happened"; in playback and export the frame came out EMPTY.
    final keepShown = <LayerId>{
      activeId,
      for (final folder in stack.ancestryOf(
        stack.where((layer) => layer.id == activeId).firstOrNull?.folderId,
      ))
        folder.id,
    };
    // ⛔ONE pass, and the eye is read ONCE per row. Splitting the two
    // batches into two comprehensions read the row's own eye twice, and
    // `hidden_folder_is_hidden_test`'s downward ratchet caught it — that
    // count only goes down, because every extra place that re-derives
    // "is this row shown" is a place a hidden folder can be forgotten.
    final toShow = <LayerId>[];
    final toHide = <LayerId>[];
    for (final layer in stack) {
      _visibilitySoloSnapshot?.putIfAbsent(layer.id, () => layer.isVisible);
      final shouldShow = keepShown.contains(layer.id);
      if (layer.isVisible == shouldShow) {
        continue;
      }
      (shouldShow ? toShow : toHide).add(layer.id);
    }
    // Two batches, not one per row: Solo hides most of the stack and shows
    // a few, and each side is one undo step rather than a screenful.
    _session.layerController.setLayersVisible(layerIds: toShow, visible: true);
    _session.layerController.setLayersVisible(
      layerIds: toHide,
      visible: false,
    );
  }

  void exitVisibilitySolo() {
    _layerVisibilitySoloEnabled = false;
    _visibilitySoloCutId = null;
    final snapshot = _visibilitySoloSnapshot;
    _visibilitySoloSnapshot = null;
    if (snapshot == null) {
      return;
    }
    // Restore through the repository's anywhere seam — rows deleted during
    // the solo have nothing to restore (skip).
    snapshot.forEach((layerId, visible) {
      try {
        _session.repository.updateLayer(
          layerId: layerId,
          update: (layer) => layer.isVisible == visible
              ? layer
              : layer.copyWith(isVisible: visible),
        );
      } on StateError {
        // Layer gone.
      }
    });
  }

  /// Keeps the solo mode consistent after active-layer/cut changes: same
  /// cut → re-solo to the new active row; different cut → exit (restore).
  void syncVisibilitySolo() {
    if (!_layerVisibilitySoloEnabled) {
      return;
    }
    if (_session.editingSession.activeCutId != _visibilitySoloCutId) {
      exitVisibilitySolo();
    } else {
      _applyVisibilitySolo();
    }
  }

  /// Toggles an SE row's solo (pro semantics: multiple solos stack).
  void toggleLayerSolo(LayerId layerId) {
    final next = Set<LayerId>.of(_session.soloedSeLayerIds.value);
    if (!next.remove(layerId)) {
      next.add(layerId);
    }
    _session.soloedSeLayerIds.value = next;
    _session.refreshLiveAudioSchedule();
    _session.notifyChanged();
  }
}
