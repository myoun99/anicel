part of '../editor_workspace.dart';

/// The WORKSPACE LAYOUT PERSISTENCE — restoring the saved layout, saving
/// it after a mutation (debounced), and resetting it — as its own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: two fields of its own and twelve
/// State members shared (the layout pieces it saves). It reaches the
/// State through `_state`.
class _WorkspaceLayoutPersistence {
  _WorkspaceLayoutPersistence(this._state);

  final _EditorWorkspaceState _state;

  /// ⚠️ONE group open per rail. The tool library and the tool settings are
  /// the pair a stroke alternates between and it is tempting to open both,
  /// but two saved heights plus their gap need 648px of rail and a 1000px
  /// window has 589 — so the default would arrive already scrolling, which
  /// is the one thing 「넘칠 때만 스크롤」 exists to avoid. The second button
  /// is one press away and opens at the height it was left at.
  static Set<String> defaultOpenRails() =>
      _EditorWorkspaceState.debugOpenEveryRail
      ? <String>{
          for (var slot = 1; slot <= EditorWorkspace.railSlots; slot += 1) ...[
            EditorWorkspace.railGroupId(right: false, slot: slot),
            EditorWorkspace.railGroupId(right: true, slot: slot),
          ],
          EditorWorkspace.leftGroupId,
          EditorWorkspace.rightGroupId,
          EditorWorkspace.toolLeftGroupId,
          EditorWorkspace.toolRightGroupId,
        }
      : {
          EditorWorkspace.leftGroupId,
          EditorWorkspace.railGroupId(right: true, slot: 2),
        };

  /// Layout persistence: null in tests (see [EditorWorkspace.layoutStore]).
  WorkspaceLayoutStore? _layoutStore;

  Timer? _layoutSaveTimer;

  /// 워크스페이스 초기화: EVERYTHING the workspace remembers, back to the
  /// factory arrangement (the debounced save persists the reset like any
  /// other edit).
  ///
  /// It used to reset the docks, the extents and the locks — which is most
  /// of a layout but not a layout. Which rail groups were OPEN, which edge
  /// the strips were on, how far the floating region was inset, whether it
  /// was collapsed and which edge it sat on all survived the reset, so the
  /// button could not get someone out of an arrangement they disliked.
  /// Every field the save writes is reset here; that is the rule, and it is
  /// why the two lists are worth reading side by side.
  void resetWorkspaceLayout() {
    for (final extent in _state._railExtents.values) {
      extent.reset();
    }
    _state._rebuild(() {
      _state._lockedTabIds = {EditorWorkspace.canvasTabId};
      _state._openRails = defaultOpenRails();
      _state._bottomDockCollapsed = false;
      _state._regionOnTop = false;
    });
    // Back to "nobody has said", which is the 2/3 default — not to 0,
    // which is now an arrangement rather than the absence of one.
    _state._bottomInsetOverride.value = null;
    _state._brushPresetView.value = const BrushPresetViewOptions();
    _state._mutatingLayout(() {
      _state._layout.restore(docks: _EditorWorkspaceState._defaultDocks());
    });
  }

  Future<void> restoreLayout() async {
    final store = _layoutStore;
    if (store == null) {
      return;
    }
    final payload = await store.load();
    if (payload == null || !_state.mounted) {
      return;
    }
    final restored = restoreWorkspaceLayout(
      payload: payload,
      defaults: _EditorWorkspaceState._defaultDocks(),
      // The two rail WIDTHS are extents that are not docks — they belong to
      // the rail, which every group on it shares. Unnamed here they were
      // dropped on every restore, so a widened rail was narrow again at the
      // next launch.
      extraExtentKeys: {
        EditorWorkspace.railWidthKey(right: false),
        EditorWorkspace.railWidthKey(right: true),
      },
    );
    if (restored == null || !_state.mounted) {
      return;
    }
    final openRails = payload['openRails'];
    _state._rebuild(() {
      _state._lockedTabIds = restored.lockedTabIds;
      _state._bottomDockCollapsed = payload['bottomCollapsed'] == true;
      _state._regionOnTop = payload['regionOnTop'] == true;
      final savedInset = payload['bottomInset'];
      if (savedInset is num && savedInset.isFinite && savedInset >= 0) {
        _state._bottomInsetOverride.value = savedInset.toDouble();
      }
      _restoreBrushPresetView(payload['brushPresetView']);
      if (openRails is List) {
        // Filtered against the POOL, not taken on trust: a file written by
        // a build with a different pool size would otherwise leave open
        // ids that name nothing.
        final known = {
          ..._WorkspaceRail._railSlotIds(right: false),
          ..._WorkspaceRail._railSlotIds(right: true),
        };
        _state._openRails = {
          for (final id in openRails)
            if (id is String && known.contains(id)) id,
        };
      }
      _state._layout.restore(
        docks: restored.docks,
        dockExtents: restored.dockExtents,
      );
    });
    for (final entry in _state._railExtents.entries) {
      entry.value.value = restored.railExtents[entry.key];
    }
  }

  /// The tool library's view toggles as the file kept them (F-73 ①). A file
  /// written before they were saved has no such key, and whatever the
  /// workspace holds stands.
  void _restoreBrushPresetView(Object? saved) {
    if (saved is Map) {
      _state._brushPresetView.value = BrushPresetViewOptions.fromJson(
        saved.cast<String, Object?>(),
      );
    }
  }

  /// Debounced fire-and-forget save: layout changes come in bursts (drags,
  /// splitter moves) and persistence must never block or crash the editor.
  void scheduleLayoutSave() {
    final store = _layoutStore;
    if (store == null) {
      return;
    }
    _layoutSaveTimer?.cancel();
    _layoutSaveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(
        store
            .save({
              'layout': _state._layout.toJson(),
              'lockedTabs': _state._lockedTabIds.toList(),
              // Closed panels stay closed across restarts (restore only
              // returns tabs missing WITHOUT this marker to their docks —
              // i.e. panels added by an update).
              'hiddenTabs': [
                for (final entry in _state._panelMenuEntries())
                  if (!entry.visible) entry.tabId,
              ],
              // A rail the user never dragged stays ABSENT rather than
              // saving its current natural size — otherwise a later
              // column change would be pinned to yesterday's geometry.
              'railExtents': {
                for (final entry in _state._railExtents.entries)
                  if (entry.value.value != null) entry.key: entry.value.value,
              },
              // NEW keys rather than a new layout version: an older build
              // reading this file simply does not see them, whereas bumping
              // the version makes that build throw the whole arrangement
              // away (there is no migration code, only a version check).
              'bottomCollapsed': _state._bottomDockCollapsed,
              // ABSENT while the default is in force, the same rule the
              // rail extents follow: writing today's resolved pixels would
              // pin tomorrow's window to this one's width.
              if (_state._bottomInsetOverride.value != null)
                'bottomInset': _state._bottomInsetOverride.value,
              'openRails': _state._openRails.toList(),
              'regionOnTop': _state._regionOnTop,
              'brushPresetView': _state._brushPresetView.value.toJson(),
            })
            .catchError((Object _) {}),
      );
    });
  }

  /// Whether the storyboard tab is the active tab of any section (visible
  /// on screen).
  bool get isStoryboardVisible =>
      _state._layout.activeTabs.contains(EditorWorkspace.storyboardTabId);
}
