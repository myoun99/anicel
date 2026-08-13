import 'dart:ui' show Offset;

import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import '../../models/timeline_row_address.dart';
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
    this.keyNames = const {},
    this.valueLabel,
    this.scrubValue,
    this.showsKeyNavigator = true,
    this.isGroupHeader = false,
    this.groupExpanded = false,
    this.groupEnabled,
    this.previewText,
  });

  /// R5 #7: a group header may show a live PREVIEW of what it draws, in the
  /// region right of the fx column. Two fixed runs — the name and the
  /// dialogue — because a preview's job is to show the LOOK, not the
  /// content: it never reads the block's own text, so it says the same
  /// thing wherever the playhead parks.
  ///
  /// [tagAt] resolves the look at a FRAME, like [valueLabel] does for a
  /// member's readout — so the preview follows every keyed member exactly
  /// as the picture does, instead of freezing the static slot.
  ///
  /// Null on every header that has nothing to preview, which is all of them
  /// but the name tag's.
  final ({String name, String line, SeNameTag Function(int frameIndex) tagAt})?
  previewText;

  /// Stable id within the owning layer (e.g. 'position', an FX param id).
  final String laneId;

  /// Display name (AE naming for transform lanes).
  final String label;

  /// Frames carrying a key on this property.
  final Set<int> keyedFrames;

  /// Keys whose OUT interpolation is HOLD (drawn as squares, AE-style).
  final Set<int> holdOutFrames;

  /// Names on this lane's keys, by frame — "same name, same value" made
  /// visible where the link lives. Frames absent here are unnamed, which
  /// is the ordinary key: a name is what opts one INTO the link.
  final Map<int, String> keyNames;

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

/// [laneGroupKey] read back, for the callers that hold a key and need the
/// row it names — the fold law asks "what am I closing" and the view state
/// only remembers the string.
///
/// The FIRST separator splits it: a lane id never carries one (they are
/// `fx:<id>:<param>` or plain names), while a layer id is opaque and could.
({LayerId layerId, String laneId})? parseLaneGroupKey(String key) {
  final separator = key.indexOf('|');
  if (separator <= 0 || separator == key.length - 1) {
    return null;
  }
  return (
    layerId: LayerId(key.substring(0, separator)),
    laneId: key.substring(separator + 1),
  );
}

/// One display row of the timeline grids: a layer row or one of its
/// expanded property lanes. Both orientations build their rows from this
/// shared policy (Axis rule: never fork per orientation).
class TimelineDisplayRow {
  const TimelineDisplayRow.layer(
    this.layer, {
    required this.layerIndex,
    this.depth = 0,
  }) : lane = null;

  const TimelineDisplayRow.lane(
    this.layer,
    PropertyLaneRow this.lane, {
    required this.layerIndex,
  }) : depth = 0;

  /// The owning layer. A FOLDER row is just a layer row whose layer is a
  /// folder — there is no representative-member hack any more, which is
  /// what let three separate row walks (nav, frame cursor, grid memo)
  /// forget to skip the header and land on the wrong row.
  final Layer layer;

  /// The layer's index in the DISPLAY layer list — section dividers keep
  /// keying off layer positions, not row positions.
  final int layerIndex;

  final PropertyLaneRow? lane;

  // R10: a folder row carried its union runs and its members here, for a
  // private band painter that no longer exists. The union is the band
  // CLONE's own timeline now (the session's folder-band cache), so the row
  // needs nothing a cells row does not — and this walk stopped computing a
  // union per pass on all three of its call sites.

  /// Folder nesting depth (0 = top level) — drives the rail indent for
  /// both folder rows and member rows.
  final int depth;

  bool get isLane => lane != null;

  bool get isFolder => lane == null && layerKindGroupsLayers(layer.kind);

  /// WHICH row this is, in the vocabulary every frame-axis gesture speaks.
  ///
  /// ★The display row list is the app's ONE ordered answer to "what rows are
  /// on screen, in what order", and it already carries what a model walk
  /// cannot know about: the track-owned transition clone the rail inserts,
  /// the lane rows of whatever is twirled open, and their group headers.
  /// Handing that list out as ADDRESSES is what lets selection stop
  /// re-deriving a row list of its own and drifting from what is drawn.
  TimelineRowAddress get address => lane == null
      ? LayerRowAddress(layer.id)
      : LaneRowAddress(layer.id, lane!.laneId);
}

/// Lane key edit hooks — layer-generic on purpose: the camera routes them
/// into its transform track today, and every layer (and FX property) plugs
/// into the same signatures with the layer-transform work.
class PropertyLaneEditCallbacks {
  const PropertyLaneEditCallbacks({
    required this.onToggleKeyAt,
    this.onSetValue,
  });

  /// Adds a key (freezing the property's current value, AE-style) or
  /// removes the existing one — the keyframe navigator's diamond.
  final void Function(Layer layer, PropertyLaneRow lane, int frameIndex)
  onToggleKeyAt;

  // 2026-08-08: `onMoveKey` left with the key marker's own drag. Re-timing
  // a key is the lane SELECTION's move now — select the span, then drag it
  // — which is the rule the frame blocks have always followed. The camera
  // row was the last holdout, and only because the move path had no arm
  // for the track its lanes actually edit.
  //
  // R10 R3: `onRemoveKey` and `onToggleHold` left with the key marker's
  // context menu. Delete now lives on the Frame ▾ menu, which reaches a
  // lane row through `currentRow` (R10 #19); the hold toggle keeps its
  // checkbox in the camera key dialog and is waiting on Edit Instance for
  // the general case.

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

/// The lane a row shows RIGHT NOW: re-derived from [previewLayer] when a
/// drag has one staged, the committed [row]'s lane otherwise.
///
/// R10. The rows are built once per host pass, so `row.lane` carries the
/// keys, the hold flags and the value text of the COMMITTED layer. The
/// drag-preview gate already hands every row builder the previewed layer,
/// but a lane row was still reading its stale lane off the row — so a lane
/// key move drew its band and printed its value where the keys used to be
/// until the pointer came up. Re-deriving through the SAME [lanesForLayer]
/// the rows were built with is what keeps the preview and the commit from
/// drifting; the storyboard's V-track strips have always done this
/// (`_laneOfTrack` against the previewed transform).
PropertyLaneRow previewedLaneRow({
  required TimelineDisplayRow row,
  required Layer previewLayer,
  required List<PropertyLaneRow> Function(Layer layer) lanesForLayer,
}) {
  final committed = row.lane!;
  if (identical(previewLayer, row.layer)) {
    return committed;
  }
  for (final lane in lanesForLayer(previewLayer)) {
    if (lane.laneId == committed.laneId) {
      return lane;
    }
  }
  // A preview that drops the lane entirely (nothing does today) leaves the
  // committed row standing rather than blanking mid-drag.
  return committed;
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

  /// R9 #23/#24 — ONE rule for where a twirled-down lane sits: **further
  /// from the layer means applied later**.
  ///
  /// On the horizontal axis "further" is DOWN, so the lanes follow their
  /// layer in pipeline order (effects, then Transform last) and this stays
  /// false. On the x-sheet the rows are COLUMNS and the user's direction is
  /// LEFTWARD, so the same list is emitted BEFORE the layer and reversed —
  /// the last-applied lane ends up furthest left. Deciding the two
  /// separately is how they came to disagree in the first place.
  bool lanesPrecedeLayer = false,
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
    rows.add(
      TimelineDisplayRow.layer(
        layer,
        layerIndex: index,
        depth: folders.depthOf(layer.folderId),
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
  if (!lanesPrecedeLayer) {
    return List.unmodifiable(rows);
  }
  return List.unmodifiable(_laneRunsMovedAhead(rows, modelStack));
}

/// Flips each lane RUN to the far side of its owner's attach group and
/// reverses it — the x-sheet's leftward reading of "further means later"
/// (R9 #23).
///
/// It moves the run past the WHOLE group, mirroring R26 #36: the group is
/// unsplittable, so where the horizontal axis pushes the lanes past its
/// end, the x-sheet pushes them past its start.
List<TimelineDisplayRow> _laneRunsMovedAhead(
  List<TimelineDisplayRow> rows,
  List<Layer> modelStack,
) {
  final out = <TimelineDisplayRow>[];
  var index = 0;
  while (index < rows.length) {
    if (!rows[index].isLane) {
      out.add(rows[index]);
      index += 1;
      continue;
    }
    final ownerId = rows[index].layer.id;
    final run = <TimelineDisplayRow>[];
    while (index < rows.length &&
        rows[index].isLane &&
        rows[index].layer.id == ownerId) {
      run.add(rows[index]);
      index += 1;
    }
    var insertAt = out.length;
    while (insertAt > 0) {
      final candidate = out[insertAt - 1];
      if (candidate.isLane) {
        break;
      }
      final layer = candidate.layer;
      final belongs =
          layer.id == ownerId ||
          layer.attachedToLayerId == ownerId ||
          attachOrganizerBaseOf(layer, modelStack) == ownerId;
      if (!belongs) {
        break;
      }
      insertAt -= 1;
    }
    out.insertAll(insertAt, run.reversed);
  }
  return out;
}

/// 🚨T13 — where a lane SELECTION SPAN ends, given the rows the rail draws.
///
/// 유저 2026-08-13: 「se행의 네임태그에선 이번엔 행 하나만 선택범위 작동가능.
/// 다른 행 걸쳐서 선택불가. 트랜스폼이랑 같은 fx 아닌가? **왜 이렇게 또 규칙이
/// 다르지? 제발 규칙다른거 그만좀하자**」.
///
/// ⛔It used to be a WHITELIST living inside the timeline host: a span could
/// only end on a transform member lane or an effect parameter lane, and
/// everything else — the name-tag group and its seven members, the SE audio
/// lane, every group header — was "crossed silently". So a drag inside the
/// name-tag group never moved its head off the anchor and the selection
/// folded to the one row it started on.
///
/// ★The span verb for those rows already existed and was UNREACHABLE:
/// `seNameTagLaneSpan` is a complete twin of `transformLaneSpan`. Nothing was
/// missing except permission.
///
/// ★So the rule is the same one ③ and ⑨ put everywhere else — **the rows the
/// rail draws are the rows a span may end on** — and it is a pure function
/// here rather than a private method on a host, because a policy that decides
/// what may be selected is not a widget's business.
///
/// [rowDelta] is how many rows the pointer has crossed, signed. Null means
/// the head stays where it is: the drag has not left the anchor row, or it
/// ran off the end of the list and there is nothing further to reach.
String? resolveLaneSpanHead({
  required List<PropertyLaneRow> lanes,
  required String anchorLaneId,
  required int rowDelta,
}) {
  if (rowDelta == 0) {
    return null;
  }
  final anchor = lanes.indexWhere((lane) => lane.laneId == anchorLaneId);
  if (anchor < 0) {
    return null;
  }
  final step = rowDelta > 0 ? 1 : -1;
  String? head;
  for (var moved = 1; moved <= rowDelta.abs(); moved += 1) {
    final index = anchor + moved * step;
    if (index < 0 || index >= lanes.length) {
      // Past the end: the span stops at the farthest row it actually
      // reached, rather than snapping back to the anchor.
      break;
    }
    head = lanes[index].laneId;
  }
  return head;
}
