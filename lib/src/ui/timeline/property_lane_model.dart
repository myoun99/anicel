import 'dart:ui' show Offset;

import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import '../../models/timeline_row_address.dart';
import 'timeline_row_filter.dart';
import 'timeline_section_policy.dart';

/// One property lane under a layer: a NAMED keyed property rendered as its
/// own timeline row. Deliberately generic — transform lanes (Position/
/// Scale/Rotation…) today, layer-FX property lanes on the same base soon.
/// What KIND of value a lane holds, so its editor can be the right control
/// instead of a text box for everything.
///
/// 🚨F-22 (유저 2026-08-24): 「fx의 멤버 편집, **타입에 따라 확실하게 나누기.
/// 지금 싹 다 텍스트임.** … **Bold같은 불리언 타입은 그냥 누르면 전환되는
/// 버튼**이도록」.
///
/// The KIND belongs to the lane, not to the widget: only the provider knows
/// that `name-tag:bold` is a flag, and a switch on lane ids in the row
/// widget would be a second place to keep that knowledge.
enum PropertyLaneValueKind {
  /// The default — a number, typed or scrubbed.
  number,

  /// A flag: the value cell IS the control, and a tap flips it.
  boolean,

  /// A colour: the value cell is a round swatch that opens the shared
  /// picker, the same control every other colour in the app is chosen with.
  ///
  /// ⚠️It carries `none` as well as `#RRGGBB` — the box colour really is
  /// absent when the アフレコ box is off — so the swatch has to be able to
  /// show and to reach a state no colour wheel has. That is the picker's
  /// 「없음」 row (`Q-f22-none`, 유저 답 1번), not a second kind here.
  color,
}

/// ONE editable piece of a lane's value: the number a person types, and the
/// FIXED text that trails it.
typedef PropertyLaneValuePart = ({String number, String unit});

/// A value label split into what is EDITED and what is chrome (F-22 ②③).
///
/// 유저 2026-08-24: 「**단위 같은 고정요소를 편집창에서 제거**」,
/// 「**포지션 등 2요소는 각각 편집**(온점 없이)」.
///
/// The value editor used to be one text box over the whole readout, so
/// editing Scale meant typing `85%` with the percent sign, and editing
/// Position meant typing `120, 45` — comma, space and all — to move one of
/// the two numbers. Neither the unit nor the separator is a value; they are
/// the shape the value is printed in.
///
/// ⚠️Derived from the label rather than declared per lane. The label already
/// says what shape it is (`85%`, `30°`, `12 px`, `120, 45`), and a second
/// declaration would be a second answer to drift from — the exact mistake
/// the rail's column skeleton was built to end. [joinPropertyLaneValueParts]
/// puts it back in the form every lane's parser already accepts, which is
/// what keeps the commit path untouched.
///
/// ⛔A label only SPLITS when every comma-separated piece reads as a number:
/// a text value that happens to contain a comma is one value, not two.
List<PropertyLaneValuePart> propertyLaneValueParts(String label) {
  final pieces = label.split(',');
  final parts = <PropertyLaneValuePart>[];
  for (final piece in pieces) {
    final part = _numberAndUnit(piece.trim());
    if (part == null) {
      return [(number: label, unit: '')];
    }
    parts.add(part);
  }
  return parts.isEmpty ? [(number: label, unit: '')] : parts;
}

/// [propertyLaneValueParts] put back together — the text form the lane's own
/// parser reads, byte for byte what the label was.
String joinPropertyLaneValueParts(List<PropertyLaneValuePart> parts) =>
    parts.map((part) => '${part.number}${part.unit}').join(', ');

/// `85%` → (85, '%'), `12 px` → (12, ' px'), `-3.5` → (-3.5, ''). Null when
/// the text does not lead with a number at all, which is every value that is
/// not one — a colour, a font name, a flag.
PropertyLaneValuePart? _numberAndUnit(String text) {
  var end = 0;
  if (end < text.length && (text[end] == '-' || text[end] == '+')) {
    end += 1;
  }
  final digitsStart = end;
  while (end < text.length && _isDigit(text[end])) {
    end += 1;
  }
  if (end < text.length && text[end] == '.') {
    end += 1;
    while (end < text.length && _isDigit(text[end])) {
      end += 1;
    }
  }
  if (end == digitsStart) {
    return null;
  }
  return (number: text.substring(0, end), unit: text.substring(end));
}

bool _isDigit(String character) {
  final code = character.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// What a key mark on a lane LOOKS like — the AE vocabulary, plus the third
/// answer a UNION needs (F-17).
///
/// An enum rather than the pair of booleans the drawing used to take: with
/// two flags "hold and mixed at once" is a state something can be handed,
/// and a mark cannot be both.
enum PropertyLaneKeyShape {
  /// AE's diamond — this key interpolates (and on a union, they all do).
  smooth,

  /// AE's square — this key holds (and on a union, they all do).
  hold,

  /// A UNION whose members disagree. Never reachable on a member lane.
  mixed,
}

/// A lane colour written the way its own parser reads it back —
/// `#RRGGBB`, or `none` where the lane allows absence.
///
/// ⛔ONE SPELLING. The label a row prints and the text a swatch commits go
/// through this same function, so a colour can never be printed in a form
/// its own lane cannot parse ([[no-copy-to-share]]). `parseArgbInput` is
/// the other half and stays where it is, beside the commit path that has
/// always owned it.
String formatLaneColorValue(int? argb) => argb == null
    ? 'none'
    : '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class PropertyLaneRow {
  const PropertyLaneRow({
    required this.laneId,
    required this.label,
    required this.keyedFrames,
    this.holdOutFrames = const {},
    this.mixedFrames = const {},
    this.keyNames = const {},
    this.valueLabel,
    this.valueKind = PropertyLaneValueKind.number,
    this.colorCanBeNone = false,
    this.scrubValue,
    this.showsKeyNavigator = true,
    this.isGroupHeader = false,
    this.groupExpanded = false,
    this.groupEnabled,
    this.previewText,
  });

  /// See [PropertyLaneValueKind].
  final PropertyLaneValueKind valueKind;

  /// Whether this lane's colour may be ABSENT — only meaningful when
  /// [valueKind] is [PropertyLaneValueKind.color].
  ///
  /// ⛔The lane carries it, so nothing downstream switches on a lane id to
  /// find out: the value cell asks the row it was handed, exactly as it
  /// asks it what kind of value it holds.
  final bool colorCanBeNone;

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

  /// 🚨F-17: UNION headers only — frames whose keyed members DISAGREE about
  /// their interpolation, drawn as a circle (「멤버 타입이 서로 다르면 헤더에
  /// 동그라미」).
  ///
  /// ⛔Always empty on a member lane, and it has to be: a single key holds
  /// or it does not, and there is nothing for it to disagree with. Only a
  /// summary can be mixed.
  ///
  /// ⚠️Never overlaps [holdOutFrames] — [transformKeyMixedUnion] and
  /// [transformKeyHoldUnion] come out of one walk for exactly that reason.
  /// The shape a mark takes is resolved ONCE, by
  /// [PropertyLaneRow.keyShapeAt], so no drawing site can reach a state
  /// where a key is both.
  final Set<int> mixedFrames;

  /// Which mark [frame] draws on this lane.
  ///
  /// ★The one place the three sets become a shape. A widget that took two
  /// booleans could be handed "hold AND mixed"; this cannot be.
  PropertyLaneKeyShape keyShapeAt(int frame) => mixedFrames.contains(frame)
      ? PropertyLaneKeyShape.mixed
      : holdOutFrames.contains(frame)
      ? PropertyLaneKeyShape.hold
      : PropertyLaneKeyShape.smooth;

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

  bool get isFolder => lane == null && layer.kind.groupsLayers;

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

/// The index of [layerId]'s CELLS row (its first non-lane row) in [rows],
/// or -1 — the walk the ↑/↓ nav, the flip HUD and the span resolvers all
/// make before they answer their own question.
int indexOfLayerRow(List<TimelineDisplayRow> rows, LayerId? layerId) {
  for (var index = 0; index < rows.length; index += 1) {
    if (!rows[index].isLane && rows[index].layer.id == layerId) {
      return index;
    }
  }
  return -1;
}

/// Where a walk stands in [rows]: the row addressed [current], or, when
/// that row is not on screen — a track row (the storyboard owns one), a
/// row a filter has hidden — the active layer's own cells row. -1 when
/// neither is drawn.
///
/// The ↑/↓ walk falls back to the active layer's own row in exactly this
/// case, so the flip HUD's window does too rather than pointing at
/// whatever sits at the top; both read it from here.
int indexOfDisplayRow(
  List<TimelineDisplayRow> rows, {
  required TimelineRowAddress? current,
  required LayerId? activeLayerId,
}) {
  final currentIndex = rows.indexWhere((row) => row.address == current);
  return currentIndex >= 0
      ? currentIndex
      : indexOfLayerRow(rows, activeLayerId);
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
  // Indexed once for the same reason the folder questions are (F-30 asks
  // an attach row for its BASE's folder, once per row).
  final layerById = {for (final layer in modelStack) layer.id: layer};
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
    final attachBaseId = attachGroupBaseOf(layer, modelStack);
    if (attachBaseId != null &&
        layer.id != activeLayerId &&
        collapsedAttachBaseIds.contains(attachBaseId)) {
      continue;
    }
    if (!rowFilter.allowsLayerRow(
      layer,
      standing: layer.id == activeLayerId,
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
        // 🚨F-30 (유저 2026-08-24): 「폴더 안 어태치 레이어의 들여쓰기가
        // 어긋난다 — 아래쪽 어태치 레이어의 화살표·버튼 위치가 폴더 바깥
        // 레이어처럼 배치된다」.
        //
        // ⛔An attach row hangs off its BASE, so it is indented with its
        // base — whatever its own `folderId` happens to say. The menu path
        // copies the base's folder in, but a row mounted by DRAG keeps the
        // folder it came from (usually none), and depth read that field
        // straight. Two rows sitting one above the other in the same group
        // then started their leading cluster on different columns.
        //
        // ⚠️Indent is a DISPLAY fact — "what does this row hang off" — and
        // the model's folder membership is a different question. Fixing it
        // by writing the folder onto the attach row would make the model
        // agree by making it say something that is not true (the row is not
        // a member of the folder; its base is).
        //
        // ↩️F-81 (유저 2026-09-11): 「이 아이콘이 어태치폴더의 내부 레이어에
        // 안생김. 로직 다른거같은데 통일해서 법 하나로」. A row INSIDE an attach
        // folder hangs off that folder the way a member hangs off any folder:
        // one level per attach folder above it, on top of the base's indent.
        depth: attachBaseId == null
            ? folders.depthOf(layer.folderId)
            : folders.depthOf((layerById[attachBaseId] ?? layer).folderId) +
                  attachFolderLevelsAbove(layer, modelStack),
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
