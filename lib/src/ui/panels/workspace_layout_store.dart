import 'dart:convert';
import 'dart:io';

import '../../services/persistence/app_support_path.dart';
import 'editor_panel_layout.dart';

/// Loads and saves the dockable-panel workspace layout (which tab lives in
/// which dock, dock extents, drag locks).
///
/// Like the brush preset library this is editor/app state, not project
/// data: it lives in an app-support JSON file. A missing or corrupt file
/// simply yields no layout (the workspace keeps its defaults).
class WorkspaceLayoutStore {
  WorkspaceLayoutStore({String? filePath})
    : filePath = filePath ?? defaultWorkspaceLayoutFilePath();

  /// Absolute path of the layout file.
  final String filePath;

  static String defaultWorkspaceLayoutFilePath() =>
      appSupportFilePath('workspace_layout.json');

  static const int layoutVersion = 1;

  /// Reads the saved layout payload; null when missing/corrupt/newer.
  Future<Map<String, Object?>?> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if ((decoded['version'] as int? ?? 0) > layoutVersion) {
        return null;
      }
      return decoded;
    } catch (_) {
      // A corrupt layout must not fail the editor: the defaults win and
      // the file is replaced on the next save.
      return null;
    }
  }

  /// Writes the layout payload, creating the app-data directory as needed.
  Future<void> save(Map<String, Object?> payload) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': layoutVersion, ...payload}),
    );
  }
}

/// A sanitized restored workspace layout.
typedef RestoredWorkspaceLayout = ({
  Map<String, DockGroup?> docks,
  Map<String, double> dockExtents,
  Map<String, double> railExtents,
  Set<String> lockedTabIds,
});

/// One saved splitter number, or null when the file cannot be trusted for
/// it.
///
/// The rail extents were filtered this way from the start; the dock extents
/// were not, and a NEGATIVE one is the reachable half of that. Measured:
/// `jsonDecode` rejects `NaN` and `Infinity` outright, so those cannot come
/// out of the file at all — but `-100` decodes fine, and a negative width
/// reaching `SizedBox` throws a `FlutterError` rather than clamping. A
/// hand-edited or half-written `workspace_layout.json` took the workspace
/// down with it. Zero and absurdly large values are harmless (a collapsed
/// dock, and the side docks' own scale-to-fit), but they are not USEFUL, so
/// falling back to the default is the better answer for them too.
///
/// `isFinite` is here for the callers, not for the file: these are public
/// functions taking a plain map, and nothing about their signature says the
/// map came from JSON.
double? restoredSplitterValue(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) {
    return null;
  }
  return value.toDouble();
}

/// Rail window sizes ([LayerRailId] → logical pixels), sanitized: a rail
/// the user never dragged is simply absent and follows its natural size.
///
/// This rides the workspace layout file rather than a store of its own
/// because it is the same kind of fact as a dock width — a splitter
/// position the user set once and expects to find again.
Map<String, double> restoreRailExtents(Map<String, Object?> payload) {
  final railsJson = payload['railExtents'];
  return <String, double>{
    if (railsJson is Map)
      for (final entry in railsJson.entries)
        if (entry.key is String)
          entry.key as String: ?restoredSplitterValue(entry.value),
  };
}

/// Rebuilds a dock layout from a saved payload, validated against the
/// CURRENT panel set given by [defaults]: unknown tab ids are dropped,
/// duplicates keep their first occurrence, and known tabs missing from the
/// saved layout rejoin their default dock's group. Returns null when the
/// payload has no usable layout.
///
/// ⚠️A dock's tabs are read as a FLAT list however the file spells them.
/// Layouts saved while docks could be split into stacked sections have a
/// list of sections per dock; every one of them folds into the dock's one
/// group, in file order. That is not a migration so much as the shape of
/// the answer now — there is nowhere else for a second section to go, and
/// dropping it would silently close panels the user had open.
RestoredWorkspaceLayout? restoreWorkspaceLayout({
  required Map<String, Object?> payload,
  required Map<String, DockGroup?> defaults,
  Set<String> extraExtentKeys = const <String>{},
}) {
  final layoutJson = payload['layout'];
  if (layoutJson is! Map) {
    return null;
  }
  final docksJson = layoutJson['docks'];
  if (docksJson is! Map) {
    return null;
  }

  final knownTabs = <String>{
    for (final group in defaults.values) ...?group?.tabs,
  };

  final seen = <String>{};
  final tabsByDock = <String, List<String>>{
    for (final dockId in defaults.keys) dockId: <String>[],
  };
  final activeByDock = <String, String>{};
  for (final entry in docksJson.entries) {
    final dockId = entry.key;
    if (dockId is! String || !tabsByDock.containsKey(dockId)) {
      continue;
    }
    // One group per dock, written as a map; a list is a layout from when a
    // dock could be split, and every section in it joins the same strip.
    final groupsJson = switch (entry.value) {
      final List list => list,
      final Map map => [map],
      _ => const [],
    };
    for (final groupJson in groupsJson) {
      if (groupJson is! Map) {
        continue;
      }
      final tabsJson = groupJson['tabs'];
      if (tabsJson is! List) {
        continue;
      }
      final tabs = <String>[
        for (final tab in tabsJson)
          if (tab is String && knownTabs.contains(tab) && seen.add(tab)) tab,
      ];
      if (tabs.isEmpty) {
        continue;
      }
      tabsByDock[dockId]!.addAll(tabs);
      // The FIRST section's active tab wins: it is the one the user was
      // looking at in the strip that survives as the group's strip.
      final active = groupJson['active'];
      if (active is String && tabs.contains(active)) {
        activeByDock.putIfAbsent(dockId, () => active);
      }
    }
  }

  // Panels the user CLOSED stay closed; anything else missing from the
  // save (panels added by an app update) rejoins its default dock's group,
  // so an update-added tab slips into the existing strip invisibly.
  final hiddenJson = payload['hiddenTabs'];
  final hiddenTabs = <String>{
    if (hiddenJson is List)
      for (final tab in hiddenJson)
        if (tab is String) tab,
  };
  for (final entry in defaults.entries) {
    final group = entry.value;
    if (group == null) {
      continue;
    }
    tabsByDock[entry.key]!.addAll([
      for (final tab in group.tabs)
        if (!hiddenTabs.contains(tab) && seen.add(tab)) tab,
    ]);
  }

  final docks = <String, DockGroup?>{
    for (final entry in tabsByDock.entries)
      entry.key: entry.value.isEmpty
          ? null
          : DockGroup(tabs: entry.value, activeTabId: activeByDock[entry.key]),
  };

  // ⚠️Not every saved extent names a DOCK. A rail's shared width is stored
  // under a key of its own ('rail-L' / 'rail-R') because it belongs to the
  // rail rather than to any one group on it — and this filter, which only
  // ever knew about dock ids, threw it away on every single restore. The
  // side panels came back at the default width every launch and the drag
  // that widened them looked like it had never been saved. The caller names
  // the keys that are extents but not docks; everything else is still junk.
  final extentsJson = layoutJson['extents'];
  final dockExtents = <String, double>{
    if (extentsJson is Map)
      for (final entry in extentsJson.entries)
        if (entry.key is String &&
            (docks.containsKey(entry.key) ||
                extraExtentKeys.contains(entry.key)))
          entry.key as String: ?restoredSplitterValue(entry.value),
  };

  final lockedJson = payload['lockedTabs'];
  final lockedTabIds = <String>{
    if (lockedJson is List)
      for (final tab in lockedJson)
        if (tab is String && knownTabs.contains(tab)) tab,
  };

  return (
    docks: docks,
    dockExtents: dockExtents,
    railExtents: restoreRailExtents(payload),
    lockedTabIds: lockedTabIds,
  );
}
