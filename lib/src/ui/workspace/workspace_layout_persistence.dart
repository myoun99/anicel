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
    _state._storyboardTrackLaneHeight.value =
        StoryboardPanel.defaultTrackLaneHeight;
    // Back to "nobody has said", which is the 2/3 default — not to 0,
    // which is now an arrangement rather than the absence of one.
    _state._bottomInsetOverride.value = null;
    _state._brushPresetView.value = const BrushPresetViewOptions();
    _state._brushDetailAt.value = null;
    // The open groups and the docks are ONE change to what the docks show.
    _state._mutatingLayout(() {
      _state._rebuild(() {
        _state._lockedTabIds = {EditorWorkspace.canvasTabId};
        _state._openRails = defaultOpenRails();
        _state._bottomDockCollapsed = false;
        _state._regionOnTop = false;
        _state._brushValuesOnStrip.value = false;
        _state._railToolsOnly.value = false;
      });
      _state._layout.restore(docks: _EditorWorkspaceState._defaultDocks());
      _state._laidFloorTab.value = null;
    });
  }

  /// The arrangement the layout file holds, put in place — answering
  /// whether there was one: false where the file holds none, or none this
  /// build reads, and the workspace stands as it was. With no file to read
  /// (a test) there is nothing to stand by: true, and nothing changes.
  ///
  /// ⚠️No arrangement is the factory one, and at the start the workspace
  /// stands so already — so nothing is put back here: a first read that
  /// lands late would undo what the hand did meanwhile (the storyboard tab
  /// a test had opened, 2026-10-30). Read AGAIN, the workspace may stand
  /// elsewhere, and its reader puts it back ([resetWorkspaceLayout]).
  Future<bool> restoreLayout() async {
    final store = _layoutStore;
    if (store == null) {
      return true;
    }
    final payload = await store.load();
    if (payload == null || !_state.mounted) {
      return false;
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
      return false;
    }
    _state._rebuild(() {
      _state._lockedTabIds = restored.lockedTabIds;
      _state._bottomDockCollapsed = payload['bottomCollapsed'] == true;
      _state._regionOnTop = payload['regionOnTop'] == true;
      _state._brushValuesOnStrip.value =
          payload['brushValuesOnStrip'] == true;
      _state._railToolsOnly.value = payload['railToolsOnly'] == true;
      final savedInset = payload['bottomInset'];
      if (savedInset is num && savedInset.isFinite && savedInset >= 0) {
        _state._bottomInsetOverride.value = savedInset.toDouble();
      }
      _restoreBrushPresetView(payload['brushPresetView']);
      _restoreOpenRails(payload['openRails']);
      _state._layout.restore(
        docks: restored.docks,
        dockExtents: restored.dockExtents,
      );
    });
    // What lay on the floor, as long as it still stands on the top strip
    // ([_EditorWorkspaceState._mutatingLayout] lets go of anything else).
    _state._mutatingLayout(() {
      final laid = payload[_laidFloorTabKey];
      _state._laidFloorTab.value = laid is String ? laid : null;
    });
    for (final entry in _state._railExtents.entries) {
      entry.value.value = restored.railExtents[entry.key];
    }
    _restoreTrackLaneHeight(payload[_storyboardTrackLaneHeightKey]);
    _state._brushDetailAt.value = _restoredPoint(payload[_brushDetailAtKey]);
    return true;
  }

  /// The rails' open slots as the file kept them; absent, they stay as
  /// they stand.
  void _restoreOpenRails(Object? saved) {
    if (saved is! List) {
      return;
    }
    // Filtered against the POOL, not taken on trust: a file written by a
    // build with a different pool size would otherwise leave open ids that
    // name nothing.
    final known = {
      ..._WorkspaceRail._railSlotIds(right: false),
      ..._WorkspaceRail._railSlotIds(right: true),
    };
    _state._openRails = {
      for (final id in saved)
        if (id is String && known.contains(id)) id,
    };
  }

  /// The layout file's key for where the brush detail window was left.
  static const _brushDetailAtKey = 'brushDetailAt';

  /// The layout file's key for the panel laid on the floor out of a top
  /// strip group ([_EditorWorkspaceState._laidFloorTab]) — absent while the
  /// floor holds its own.
  static const _laidFloorTabKey = 'laidFloorTab';

  /// A point as the file kept it — `[x, y]` — or null for anything else,
  /// which opens the window where a window that was never moved opens.
  static Offset? _restoredPoint(Object? saved) => switch (saved) {
    [final num x, final num y] when x.isFinite && y.isFinite => Offset(
      x.toDouble(),
      y.toDouble(),
    ),
    _ => null,
  };

  /// The layout file's key for the V rows' height.
  static const _storyboardTrackLaneHeightKey = 'storyboardTrackLaneHeight';

  /// The V rows' height as the file kept it — the splitter's: absent is the
  /// default, and a file's number is held to the floor like a drag's. The
  /// ceiling is the camera's and the screen's, so it is held there when the
  /// rows are drawn (`_storyboardLaneHeight`), not here.
  void _restoreTrackLaneHeight(Object? saved) {
    _state._storyboardTrackLaneHeight.value = saved is num && saved.isFinite
        ? math.max(StoryboardPanel.minTrackLaneHeight, saved.toDouble())
        : StoryboardPanel.defaultTrackLaneHeight;
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
    // 🪦Chained its writes here once — two in flight interleaved into a
    // file no restore could read (V rows' splitter test, 2026-09-26). Every
    // settings file's writes keep their order now ([saveVersionedSettings]).
    _layoutSaveTimer = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(store.save(_layoutPayload())),
    );
  }

  /// Everything the layout file keeps, as it stands now.
  Map<String, Object?> _layoutPayload() => {
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
    // The V rows' height (the splitter's), absent at the default
    // by the same rule.
    if (_state._storyboardTrackLaneHeight.value !=
        StoryboardPanel.defaultTrackLaneHeight)
      _storyboardTrackLaneHeightKey:
          _state._storyboardTrackLaneHeight.value,
    'openRails': _state._openRails.toList(),
    'regionOnTop': _state._regionOnTop,
    'brushValuesOnStrip': _state._brushValuesOnStrip.value,
    'railToolsOnly': _state._railToolsOnly.value,
    'brushPresetView': _state._brushPresetView.value.toJson(),
    // Absent until the window has been moved, by the rail extents' rule.
    if (_state._brushDetailAt.value case final at?)
      _brushDetailAtKey: [at.dx, at.dy],
    _laidFloorTabKey: ?_state._laidFloorTab.value,
  };
}
