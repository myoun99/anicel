import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One stacked region inside a dock: a tab group with its own strip.
class DockSection {
  DockSection({
    required List<String> tabs,
    String? activeTabId,
    double weight = 1,
  }) : _tabs = List.of(tabs),
       _activeTabId = tabs.contains(activeTabId) ? activeTabId! : tabs.first,
       _weight = weight.clamp(_minWeight, double.infinity).toDouble(),
       assert(tabs.isNotEmpty);

  /// No section may be squashed below this share of a unit weight.
  static const double _minWeight = 0.2;

  final List<String> _tabs;
  String _activeTabId;
  double _weight;

  List<String> get tabs => List.unmodifiable(_tabs);
  String get activeTabId => _activeTabId;

  /// Relative share of the dock's stacking axis (splitter-resizable).
  double get weight => _weight;
}

/// Where a tab currently lives.
typedef DockTabLocation = ({String dockId, int sectionIndex, int tabIndex});

/// Which panel tabs live in which dock, stacked into SECTIONS (panel below
/// panel — each section is a tab group with its own strip), in what order,
/// and which tab is active per section. This is pure layout state — the
/// panel definitions (label/icon/content) stay with the workspace that owns
/// the panels.
///
/// Docks may be empty (no sections); the dock UI renders an empty dock as a
/// collapsed drop rail so tabs can still be dragged back. Sections are
/// never empty — removing a section's last tab removes the section.
class EditorPanelLayoutModel extends ChangeNotifier {
  EditorPanelLayoutModel({
    required Map<String, List<DockSection>> docks,
    Map<String, double> dockExtents = const <String, double>{},
  }) : _docks = {
         for (final entry in docks.entries) entry.key: List.of(entry.value),
       },
       _dockExtents = Map.of(dockExtents);

  /// A SEPARATE, finer signal for "a dock changed size".
  ///
  /// The whole workspace — both rails, the full-bleed canvas, the floating
  /// region — is built inside one listener on this model, so a splitter
  /// firing [notifyListeners] on every drag frame rebuilt the canvas panel
  /// once per frame. That is the lag: dragging a divider was repainting the
  /// drawing surface.
  ///
  /// A resize does not change WHAT is docked, only how wide it is, so it
  /// rides its own notifier and only the widgets that actually read an
  /// extent listen to it.
  final ValueNotifier<int> extentRevision = ValueNotifier<int>(0);

  @override
  void dispose() {
    extentRevision.dispose();
    super.dispose();
  }

  final Map<String, List<DockSection>> _docks;

  /// Resizable dock extents (side dock widths, bottom dock height) in
  /// logical pixels; docks without an entry use their built-in size.
  final Map<String, double> _dockExtents;

  static const double _minDockExtent = 160;
  static const double _maxDockExtent = 640;

  Iterable<String> get dockIds => _docks.keys;

  double dockExtent(String dockId, {required double fallback}) =>
      _dockExtents[dockId] ?? fallback;

  /// Adjusts a dock's extent by a drag delta (positive grows the dock).
  ///
  /// [minExtent] is what the dock's own PANELS need along this axis (the
  /// caller knows the tabs; this model does not). It raises the floor above
  /// [_minDockExtent] so the splitter stops where the content stops
  /// shrinking, instead of dragging on past it and cutting the bottom off —
  /// the shrink-floor round's whole point. It never LOWERS the floor, and a
  /// dock too small for its own maximum keeps the maximum.
  void resizeDock(
    String dockId,
    double delta, {
    required double fallback,
    double? minExtent,
  }) {
    final floor = math
        .max(_minDockExtent, minExtent ?? 0)
        .clamp(0.0, _maxDockExtent)
        .toDouble();
    // The CURRENT value is clamped first: a dock restored from a layout
    // saved before this floor existed sits below it, and the host already
    // draws it at the floor. Adding the delta to the stored value instead
    // would make the first drag frame jump.
    final current = dockExtent(
      dockId,
      fallback: fallback,
    ).clamp(floor, _maxDockExtent);
    final next = (current + delta).clamp(floor, _maxDockExtent).toDouble();
    if (next == _dockExtents[dockId]) {
      return;
    }
    _dockExtents[dockId] = next;
    // NOT notifyListeners: see [extentRevision]. A width is not a change of
    // arrangement, and paying for a full workspace rebuild per drag frame is
    // what made the splitter feel heavy.
    extentRevision.value += 1;
  }

  /// Shifts extent between two adjacent sections of a dock via a splitter
  /// drag: [delta]/[totalExtent] moves weight from the section below to
  /// the one above (positive delta grows the upper section).
  void resizeSections(
    String dockId,
    int upperSectionIndex, {
    required double delta,
    required double totalExtent,
  }) {
    final sections = _docks[dockId];
    if (sections == null ||
        totalExtent <= 0 ||
        upperSectionIndex < 0 ||
        upperSectionIndex + 1 >= sections.length) {
      return;
    }
    final upper = sections[upperSectionIndex];
    final lower = sections[upperSectionIndex + 1];
    final totalWeight = sections.fold<double>(0, (sum, s) => sum + s._weight);
    final weightDelta = delta / totalExtent * totalWeight;
    final shift = weightDelta
        .clamp(
          DockSection._minWeight - upper._weight,
          lower._weight - DockSection._minWeight,
        )
        .toDouble();
    if (shift == 0) {
      return;
    }
    upper._weight += shift;
    lower._weight -= shift;
    notifyListeners();
  }

  List<DockSection> sectionsIn(String dockId) =>
      List.unmodifiable(_docks[dockId] ?? const <DockSection>[]);

  /// The dock/section/tab position of a tab; null for unknown ids.
  DockTabLocation? locateTab(String tabId) {
    for (final entry in _docks.entries) {
      for (var s = 0; s < entry.value.length; s += 1) {
        final t = entry.value[s]._tabs.indexOf(tabId);
        if (t >= 0) {
          return (dockId: entry.key, sectionIndex: s, tabIndex: t);
        }
      }
    }
    return null;
  }

  /// The active tab of every section in every dock, for visibility checks.
  Iterable<String> get activeTabs sync* {
    for (final sections in _docks.values) {
      for (final section in sections) {
        yield section._activeTabId;
      }
    }
  }

  void selectTab(String dockId, int sectionIndex, String tabId) {
    final sections = _docks[dockId];
    if (sections == null ||
        sectionIndex < 0 ||
        sectionIndex >= sections.length) {
      return;
    }
    final section = sections[sectionIndex];
    if (!section._tabs.contains(tabId) || section._activeTabId == tabId) {
      return;
    }
    section._activeTabId = tabId;
    notifyListeners();
  }

  /// Whether a tab may be dropped into [toDockId]: any known tab may move
  /// to any known dock (panels dock anywhere; an emptied dock collapses).
  bool canMoveTab({required String tabId, required String toDockId}) {
    return locateTab(tabId) != null && _docks.containsKey(toDockId);
  }

  /// Moves a tab into an EXISTING section at [insertIndex] (insertion index
  /// counted in the target section's tabs BEFORE the tab is removed from
  /// its current position). The moved tab becomes the section's active tab.
  void moveTabToSection({
    required String tabId,
    required String toDockId,
    required int toSectionIndex,
    required int insertIndex,
  }) {
    final from = locateTab(tabId);
    final targetSections = _docks[toDockId];
    if (from == null ||
        targetSections == null ||
        toSectionIndex < 0 ||
        toSectionIndex >= targetSections.length) {
      return;
    }
    final sourceSection = _docks[from.dockId]![from.sectionIndex];
    final targetSection = targetSections[toSectionIndex];

    if (identical(sourceSection, targetSection)) {
      var index = insertIndex.clamp(0, sourceSection._tabs.length);
      if (index > from.tabIndex) {
        index -= 1;
      }
      if (index == from.tabIndex) {
        return;
      }
      sourceSection._tabs
        ..removeAt(from.tabIndex)
        ..insert(index, tabId);
      notifyListeners();
      return;
    }

    // Removing the source tab may drop its whole section, shifting the
    // TARGET section index when both live in the same dock.
    var targetIndex = toSectionIndex;
    final removedSection = _removeTab(from);
    if (removedSection &&
        from.dockId == toDockId &&
        from.sectionIndex < targetIndex) {
      targetIndex -= 1;
    }
    final target = _docks[toDockId]![targetIndex];
    target._tabs.insert(insertIndex.clamp(0, target._tabs.length), tabId);
    target._activeTabId = tabId;
    notifyListeners();
  }

  /// Moves a tab into a NEW section of its own at [atSectionIndex]
  /// (insertion position in the dock's section stack, counted BEFORE the
  /// tab is removed from its current position) — panel below panel.
  void moveTabToNewSection({
    required String tabId,
    required String toDockId,
    required int atSectionIndex,
  }) {
    final from = locateTab(tabId);
    final targetSections = _docks[toDockId];
    if (from == null || targetSections == null) {
      return;
    }
    // Lifting a lone-section tab next to its own slot rebuilds the same
    // stack — skip the phantom mutation.
    if (from.dockId == toDockId &&
        _docks[toDockId]![from.sectionIndex]._tabs.length == 1 &&
        (atSectionIndex == from.sectionIndex ||
            atSectionIndex == from.sectionIndex + 1)) {
      return;
    }

    var targetIndex = atSectionIndex;
    final removedSection = _removeTab(from);
    if (removedSection &&
        from.dockId == toDockId &&
        from.sectionIndex < targetIndex) {
      targetIndex -= 1;
    }
    final sections = _docks[toDockId]!;
    sections.insert(
      targetIndex.clamp(0, sections.length),
      DockSection(tabs: [tabId]),
    );
    notifyListeners();
  }

  /// Hides a panel: removes its tab from the layout entirely (empty
  /// sections are pruned; a dock may collapse). Reopen via [addTab].
  void removeTab(String tabId) {
    final from = locateTab(tabId);
    if (from == null) {
      return;
    }
    _removeTab(from);
    notifyListeners();
  }

  /// Re-opens a hidden panel INTO [dockId]'s one section; no-op when the tab
  /// is already placed or the dock is unknown.
  ///
  /// It used to append a NEW section, which is how a group quietly grew a
  /// second tab strip and a splitter — the old free-form dock tree, rebuilt
  /// one panel-menu click at a time. Now that a dock is a rail BUTTON's
  /// group, one dock is one section: reopening joins the strip that is
  /// already there, and a section is created only when the group is empty.
  void addTab(String tabId, {required String toDockId}) {
    final sections = _docks[toDockId];
    if (sections == null || locateTab(tabId) != null) {
      return;
    }
    if (sections.isEmpty) {
      sections.add(DockSection(tabs: [tabId]));
    } else {
      final first = sections.first;
      sections[0] = DockSection(
        tabs: [...first.tabs, tabId],
        activeTabId: first.activeTabId,
        weight: first.weight,
      );
    }
    notifyListeners();
  }

  /// Serializes the whole dock layout (tabs, active tabs, section weights,
  /// dock extents) for persistence.
  Map<String, Object?> toJson() => {
    'docks': {
      for (final entry in _docks.entries)
        entry.key: [
          for (final section in entry.value)
            {
              'tabs': section._tabs,
              'active': section._activeTabId,
              'weight': section._weight,
            },
        ],
    },
    'extents': _dockExtents,
  };

  /// Replaces the whole layout with a restored one (e.g. from the saved
  /// workspace file).
  void restore({
    required Map<String, List<DockSection>> docks,
    Map<String, double> dockExtents = const <String, double>{},
  }) {
    _docks
      ..clear()
      ..addAll({
        for (final entry in docks.entries) entry.key: List.of(entry.value),
      });
    _dockExtents
      ..clear()
      ..addAll(dockExtents);
    notifyListeners();
  }

  /// Removes a tab from its location; empty sections are dropped. Returns
  /// whether the whole section was removed.
  bool _removeTab(DockTabLocation from) {
    final sections = _docks[from.dockId]!;
    final section = sections[from.sectionIndex];
    section._tabs.removeAt(from.tabIndex);
    if (section._tabs.isEmpty) {
      sections.removeAt(from.sectionIndex);
      return true;
    }
    // If the moved tab was the section's active one, fall back to the
    // nearest remaining neighbour.
    if (!section._tabs.contains(section._activeTabId)) {
      section._activeTabId =
          section._tabs[from.tabIndex.clamp(0, section._tabs.length - 1)];
    }
    return false;
  }
}
