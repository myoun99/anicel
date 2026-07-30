import 'dart:ui' show Offset;

import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';

/// One property lane under a layer: a NAMED keyed property rendered as its
/// own timeline row. Deliberately generic — transform lanes (Position/
/// Scale/Rotation…) today, layer-FX property lanes on the same base soon.
class PropertyLaneRow {
  const PropertyLaneRow({
    required this.laneId,
    required this.label,
    required this.keyedFrames,
    this.holdOutFrames = const {},
    this.valueLabel,
    this.scrubValue,
    this.showsKeyNavigator = true,
    this.isGroupHeader = false,
    this.groupExpanded = false,
    this.groupEnabled,
  });

  /// Stable id within the owning layer (e.g. 'position', an FX param id).
  final String laneId;

  /// Display name (AE naming for transform lanes).
  final String label;

  /// Frames carrying a key on this property.
  final Set<int> keyedFrames;

  /// Keys whose OUT interpolation is HOLD (drawn as squares, AE-style).
  final Set<int> holdOutFrames;

  /// The property's display value at a frame (AE's blue value column —
  /// already unit-formatted); null hides the value.
  final String Function(int frameIndex)? valueLabel;

  /// AE-style value scrubbing: maps the drag's total delta onto
  /// [currentLabel] and returns the scrubbed value in the SAME text form
  /// the value editor parses (the release commits it through onSetValue).
  /// Generic like [valueLabel] — each lane provider decides which drag axis
  /// drives which component. Null (or a null return) disables scrubbing.
  final String? Function(String currentLabel, Offset dragDelta)? scrubValue;

  /// Whether the label cell shows the keyframe navigator (◀ ◆ ▶). Lanes
  /// without key semantics (the SE audio lane) hide it.
  final bool showsKeyNavigator;

  /// AE-style GROUP HEADER row ('Transform', later 'Effects'): a structural
  /// label leading its member lanes — no keys, no value, no navigator; the
  /// frame band stays a quiet strip.
  final bool isGroupHeader;

  /// Group headers only: whether the group's member lanes are twirled open
  /// (AE-style header collapse — drives the header's chevron; default
  /// collapsed).
  final bool groupExpanded;

  /// Group headers only: the group's own ON/OFF switch, drawn as the shared
  /// `fx` glyph — AE's per-effect eyeball (R6). Null = this group has no
  /// switch (the Transform group; the row's one fx switch covers it).
  final bool? groupEnabled;
}

/// The view-state key of ONE collapsible lane group. A layer twirl-down can
/// hold several group headers now (Transform, plus one per effect), so the
/// expansion set is keyed by (row, group) instead of by row alone — a Blur
/// opened on layer A must not open Transform on layer B.
String laneGroupKey(LayerId layerId, String laneId) =>
    '${layerId.value}|$laneId';

/// One display row of the timeline grids: a layer row or one of its
/// expanded property lanes. Both orientations build their rows from this
/// shared policy (Axis rule: never fork per orientation).
class TimelineDisplayRow {
  const TimelineDisplayRow.layer(
    this.layer, {
    required this.layerIndex,
    this.depth = 0,
    this.aggregateRuns = const [],
    this.members = const [],
  }) : lane = null;

  const TimelineDisplayRow.lane(
    this.layer,
    PropertyLaneRow this.lane, {
    required this.layerIndex,
  }) : depth = 0,
       aggregateRuns = const [],
       members = const [];

  /// The owning layer. A FOLDER row is just a layer row whose layer is a
  /// folder — there is no representative-member hack any more, which is
  /// what let three separate row walks (nav, frame cursor, grid memo)
  /// forget to skip the header and land on the wrong row.
  final Layer layer;

  /// The layer's index in the DISPLAY layer list — section dividers keep
  /// keying off layer positions, not row positions.
  final int layerIndex;

  final PropertyLaneRow? lane;

  /// Folder rows only: the SUBTREE members' exposure union as merged
  /// display runs (the TVP-latest aggregate block — nameless, no comma
  /// edits, no moves; holds included through exposure lengths).
  final List<({int start, int endExclusive})> aggregateRuns;

  /// Folder rows only: the SUBTREE members themselves. R28 #11 — the
  /// aggregate band tints a frame grey when NO member has artwork there,
  /// so it needs the members, not just their exposure union.
  final List<Layer> members;

  /// Folder nesting depth (0 = top level) — drives the rail indent for
  /// both folder rows and member rows.
  final int depth;

  bool get isLane => lane != null;

  bool get isFolder => lane == null && layerKindGroupsLayers(layer.kind);
}

/// Lane key edit hooks — layer-generic on purpose: the camera routes them
/// into its transform track today, and every layer (and FX property) plugs
/// into the same signatures with the layer-transform work.
class PropertyLaneEditCallbacks {
  const PropertyLaneEditCallbacks({
    required this.onToggleKeyAt,
    required this.onMoveKey,
    required this.onRemoveKey,
    required this.onToggleHold,
    this.onSetValue,
  });

  /// Adds a key (freezing the property's current value, AE-style) or
  /// removes the existing one — the keyframe navigator's diamond.
  final void Function(Layer layer, PropertyLaneRow lane, int frameIndex)
  onToggleKeyAt;

  /// A key marker dragged to another frame.
  final void Function(
    Layer layer,
    PropertyLaneRow lane,
    int fromFrame,
    int toFrame,
  )
  onMoveKey;

  final void Function(Layer layer, PropertyLaneRow lane, int frameIndex)
  onRemoveKey;

  /// AE's Toggle Hold Keyframe.
  final void Function(Layer layer, PropertyLaneRow lane, int frameIndex)
  onToggleHold;

  /// A value typed into the lane's value editor: sets/updates a key at the
  /// frame (AE: changing an animated value keys it at the playhead). The
  /// raw input is parsed by the property's own policy; invalid input is
  /// ignored. Null hides the editor.
  final void Function(
    Layer layer,
    PropertyLaneRow lane,
    int frameIndex,
    String input,
  )?
  onSetValue;
}

/// Builds the grid's display rows: every layer row, plus the property lane
/// rows of layers whose twirl-down is expanded. Sections listed in
/// [hiddenSections] contribute NO rows at all (the toolbar's SE/CAMERA
/// visibility toggles — the layers themselves are untouched); both
/// orientations consume the same policy (Axis rule).
///
/// [rowFilter] additionally hides individual layer rows failing its
/// predicate (R2 row filter, a VIEW state); [activeLayerId] is exempt so a
/// filter can never hide the layer you're editing. [fxEnabledOf] resolves
/// the session-level fx state the filter's fx-only facet reads.
///
/// The folder row's aggregate band (the TVP-latest display): the UNION of
/// the subtree members' exposure intervals merged into runs. Pure display
/// — nameless, no comma edits, no moves.
List<({int start, int endExclusive})> folderAggregateRuns(
  Iterable<Layer> members,
) {
  final intervals = <({int start, int endExclusive})>[
    for (final member in members)
      for (final entry in member.timeline.entries)
        if (entry.value.length != null)
          (start: entry.key, endExclusive: entry.key + entry.value.length!),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final runs = <({int start, int endExclusive})>[];
  for (final interval in intervals) {
    if (runs.isNotEmpty && interval.start <= runs.last.endExclusive) {
      if (interval.endExclusive > runs.last.endExclusive) {
        runs[runs.length - 1] = (
          start: runs.last.start,
          endExclusive: interval.endExclusive,
        );
      }
    } else {
      runs.add(interval);
    }
  }
  return runs;
}

/// [collapsedAttachBaseIds] folds ATTACH GROUPS (UI-R20 #9): attach rows
/// whose base is listed contribute no rows — same VIEW-state contract as
/// the hidden sections, and the active layer is exempt here too (folding
/// the group never hides the attach row you're working on).
List<TimelineDisplayRow> buildTimelineDisplayRows({
  required List<Layer> layers,
  required Set<LayerId> expandedLayerIds,
  required List<PropertyLaneRow> Function(Layer layer) lanesForLayer,
  Set<TimelineSection> hiddenSections = const {},
  TimelineRowFilter rowFilter = TimelineRowFilter.none,
  Set<LayerId> collapsedAttachBaseIds = const {},
  LayerId? activeLayerId,
  bool Function(LayerId layerId)? fxEnabledOf,

  /// The MODEL stack, when [layers] is a display-ordered copy: folder
  /// membership is resolved against it so nesting reads the same in every
  /// orientation. Defaults to [layers].
  List<Layer>? stack,
}) {
  final rows = <TimelineDisplayRow>[];
  // R26 #36: the attach group is unsplittable — a base's transform lanes
  // WAIT here until the group's trailing attach rows have been laid, so
  // the order reads base → attach rows → lanes in every orientation
  // (attach rows preceding the base in display order are unaffected: the
  // group already ends at the base there).
  final pendingLanes = <TimelineDisplayRow>[];
  LayerId? pendingLaneBaseId;
  void flushPendingLanes() {
    rows.addAll(pendingLanes);
    pendingLanes.clear();
    pendingLaneBaseId = null;
  }

  // Folder rows need no synthesis: they are IN the stack, already sitting
  // directly above their members. All that is left is the nesting indent,
  // the collapse fold and the aggregate band the folder row paints.
  //
  // Indexed ONCE for the whole pass. The three folder questions below run
  // per layer, and asked straight off the stack each of them re-scans it:
  // that made this loop O(n²·depth) with a list and a set allocated per
  // probe — and it runs in build(), where a session notify puts it on
  // every chrome rebuild.
  final modelStack = stack ?? layers;
  final folders = LayerFolderIndex(modelStack);
  for (var index = 0; index < layers.length; index += 1) {
    final layer = layers[index];
    // An ORGANIZER folder row ([연출]/[작감]… inside an attach group)
    // belongs to its base's group: the group fold hides it and the lane
    // deferral treats it as part of the attach run.
    final organizerBaseId = attachOrganizerBaseOf(layer, modelStack);
    // The attach run ends at the first layer that is NOT an attach (or
    // organizer folder) of the pending base (row-emission skips below
    // never end it: a folded attach row still belongs to the group).
    if (pendingLaneBaseId != null &&
        layer.attachedToLayerId != pendingLaneBaseId &&
        organizerBaseId != pendingLaneBaseId) {
      flushPendingLanes();
    }
    if (hiddenSections.contains(timelineSectionForLayerKind(layer.kind))) {
      continue;
    }
    final attachBaseId = layer.attachedToLayerId ?? organizerBaseId;
    if (attachBaseId != null &&
        layer.id != activeLayerId &&
        collapsedAttachBaseIds.contains(attachBaseId)) {
      continue;
    }
    if (rowFilter.isActive &&
        layer.id != activeLayerId &&
        !rowFilter.allows(
          layer,
          fxEnabled: fxEnabledOf?.call(layer.id) ?? true,
        )) {
      continue;
    }
    // R27 #24: a collapsed folder folds ALL its members, the active layer
    // included. The old active-layer exemption meant folding a folder
    // whose member was selected simply didn't look folded; the folder row
    // takes the selection instead (EditorSessionManager.toggleLayerCollapsed).
    if (folders.subtreeCollapsed(layer.folderId)) {
      continue;
    }
    final isFolder = layerKindGroupsLayers(layer.kind);
    final subtreeMembers = isFolder
        ? folders.subtreeMembersOf(layer.id)
        : const <Layer>[];
    rows.add(
      TimelineDisplayRow.layer(
        layer,
        layerIndex: index,
        depth: folders.depthOf(layer.folderId),
        aggregateRuns: isFolder
            ? folderAggregateRuns(subtreeMembers)
            : const [],
        members: subtreeMembers,
      ),
    );
    if (!expandedLayerIds.contains(layer.id)) {
      continue;
    }
    // R26 #36: with trailing attach rows ahead, the lanes go PENDING and
    // land after the group; otherwise they follow the layer row exactly
    // as before. An attach layer's own lanes always emit in place (it
    // has no attach children of its own).
    final defer =
        layer.attachedToLayerId == null &&
        index + 1 < layers.length &&
        layers[index + 1].attachedToLayerId == layer.id;
    for (final lane in lanesForLayer(layer)) {
      final laneRow = TimelineDisplayRow.lane(layer, lane, layerIndex: index);
      if (defer) {
        pendingLanes.add(laneRow);
        pendingLaneBaseId = layer.id;
      } else {
        rows.add(laneRow);
      }
    }
  }
  flushPendingLanes();
  return List.unmodifiable(rows);
}
