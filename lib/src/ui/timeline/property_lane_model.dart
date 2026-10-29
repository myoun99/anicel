import 'dart:ui' show Color, Offset, VoidCallback;

import 'package:flutter/foundation.dart' show Listenable;

import '../../models/frame_id.dart';
import '../../models/key_mark.dart';
import '../../models/key_side.dart' show KeyExit, KeySide, KeySidesEdit;
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/se_name_tag.dart' show SeNameTag;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_row_address.dart';
import '../../models/timeline_run_behavior.dart';
import '../color/color_hex.dart';
import 'lane_graph.dart' show TimelineGraphSeat;
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

  /// One of [PropertyLaneRow.choices]: the value cell is the shared list's
  /// button (`PanelFlyoutButton`), reading the word held and opening the
  /// rest — 🗣️I-132-Q6 (유저 2026-10-27): 「값이 메뉴」. A flag's ring for a
  /// list: nothing between two words to scrub or type through.
  choice,
}

/// A [PropertyLaneValueKind.boolean] lane's word for [on] — what its row
/// reads ([PropertyLaneRow.valueLabel]) and what a press on its ring writes
/// back (the value editor's `parseBoolInput` reads it), from the row and
/// from a rail's bulk-drag alike (F-475).
String flagLaneWord(bool on) => on ? 'on' : 'off';

/// A number SCRUBBED by a drag on its readout ([PropertyLaneRow.scrubValue]):
/// [value] moved by the drag's travel across, half a unit a pixel.
///
/// ⛔THE ONE RATE every one-number lane scrubs at — a rotation, an opacity,
/// an effect's parameter, a name tag's size and tracking. Three of them
/// spelled `value + dx * 0.5` each, and the name tag's lanes, spelling
/// none, could not be scrubbed at all (F-407: 「크기나 자간 변경하려해도 값
/// 변경 안됨」).
double scrubbedNumber(double value, Offset dragDelta) =>
    value + dragDelta.dx * 0.5;

/// An ANGLE scrubbed by a drag on one of its two boxes ([turnsReadoutText]):
/// the turns box's travel (across) by whole turns, the degrees box's
/// (down) by degrees — each at the one rate ([scrubbedNumber]), as a
/// pair's boxes hand theirs.
double scrubbedAngle(double degrees, Offset dragDelta) {
  final turns = scrubbedNumber(0, Offset(dragDelta.dx, 0)).round();
  return scrubbedNumber(degrees, Offset(dragDelta.dy, 0)) + turns * 360;
}

/// A lane colour written the way its own parser reads it back —
/// `#RRGGBB`, or `none` where the lane allows absence.
///
/// ⛔ONE SPELLING. The label a row prints and the text a swatch commits go
/// through this same function, so a colour can never be printed in a form
/// its own lane cannot parse ([[no-copy-to-share]]). `parseArgbInput` is
/// the other half and stays where it is, beside the commit path that has
/// always owned it.
String formatLaneColorValue(int? argb) =>
    argb == null ? 'none' : colorHexOf(argb);

class PropertyLaneRow {
  const PropertyLaneRow({
    required this.laneId,
    required this.label,
    required this.keyMarks,
    this.keyNames = const {},
    this.valueLabel,
    this.valueKind = PropertyLaneValueKind.number,
    this.colorCanBeNone = false,
    this.choices = const [],
    this.choiceValues = const [],
    this.choiceHeld,
    this.scrubValue,
    this.linkable = false,
    this.showsKeyNavigator = true,
    this.isGroupHeader = false,
    this.groupExpanded = false,
    this.groupEnabled,
    this.headsAGraph = false,
    this.previewText,
    this.stretchWords = const [],
    this.curve,
  });

  /// THE LINE a header graph draws this lane by (I-89 ③) — read off the
  /// same reading of its track as [valueLabel], widened to a time between
  /// frames, so the curve and the number printed beside it are one value.
  /// Null on a lane no graph draws: a header, a flag, a colour, a lane
  /// with no value to read.
  final LaneCurve? curve;

  /// Group headers only: whether the group's lanes can stand as one HEADER
  /// GRAPH in their place (I-89 ③) — the header wears the graph's button.
  /// The Transform group's and every effect's.
  final bool headsAGraph;

  /// The words written over the line between this lane's keys — each over
  /// the stretch from a key to the next, as an instruction span's name is
  /// written over its span ([LaneStretchWord]). The camera row's moves
  /// (I-73 ⑤); empty on every other lane.
  final List<LaneStretchWord> stretchWords;

  /// See [PropertyLaneValueKind].
  final PropertyLaneValueKind valueKind;

  /// Whether this lane's colour may be ABSENT — only meaningful when
  /// [valueKind] is [PropertyLaneValueKind.color].
  ///
  /// ⛔The lane carries it, so nothing downstream switches on a lane id to
  /// find out: the value cell asks the row it was handed, exactly as it
  /// asks it what kind of value it holds.
  final bool colorCanBeNone;

  /// The words a [PropertyLaneValueKind.choice] lane holds one of, in its
  /// list's order — what its value cell reads ([valueLabel]) and writes
  /// back. Empty on every other lane.
  final List<String> choices;

  /// What a pick of each of [choices] writes back, in their order, where
  /// that is not the word itself: a row parameter's row ids
  /// (`effectLaneRowText`) — two rows may share a name. Empty where each
  /// word writes itself.
  final List<String> choiceValues;

  /// Which of [choiceValues] the lane holds — one at every frame, as a row
  /// parameter holds its row. Null where [choiceValues] is empty: the word
  /// [valueLabel] reads is the one held.
  final String? choiceHeld;

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

  /// The lane's keys by frame, each with the mark it wears (I-89 ②): a
  /// member lane's own ([keyMarksOf]), a group header's the union of its
  /// members' ([unionKeyMarks]).
  ///
  /// ↩️It was the keyed frames beside a set of the holding ones (and, on a
  /// union, a set of the disagreeing ones), and a lane built without the
  /// second set drew every key it held as a diamond — the name tag's flag
  /// lanes did. One map cannot carry a key without its mark.
  final Map<int, KeyMark> keyMarks;

  /// Frames carrying a key on this property.
  Set<int> get keyedFrames => keyMarks.keys.toSet();

  /// The mark [frame]'s key wears — asked only of a frame this lane keys.
  KeyMark keyMarkAt(int frame) => keyMarks[frame]!;

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

  /// Whether this lane's value is two numbers a CHAIN can link — a layer's
  /// Scale. The label cell wears the chain beside the value when the rail
  /// hands it one ([PropertyLaneEditCallbacks.valueLink]).
  ///
  /// ⛔The lane carries it, as it carries [colorCanBeNone]: nothing
  /// downstream switches on a lane id to find out.
  final bool linkable;

  /// Whether the label cell shows the keyframe navigator (◀ ◆ ▶). Lanes
  /// without key semantics (an SE row's one-value Pan) hide it.
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

/// A word over the stretch of a lane from its key on [from] to the next, on
/// [to] — written in its row's key colour (`timelineStretchWordSpan`).
typedef LaneStretchWord = ({int from, int to, String word});

/// A lane as a header graph draws it ([PropertyLaneRow.curve]): the numbers
/// it holds [at] a time — a frame, or a time between two — each drawn in
/// its colour of [parts], in order; the [sides] of each of its keys by
/// frame, which its handles stand for (I-89 ③); and, where its values walk
/// a path (a position's, I-89 ④), the [way] from a key on — the next key
/// that keeps its time, and how far — which a speed graph paces its
/// handles by (I-89-Q5 B). Null where they lerp, from each key to the next.
typedef LaneCurve = ({
  List<Color> parts,
  List<double> Function(double time) at,
  Map<int, ({KeySide incoming, KeyExit outgoing})> sides,
  ({int to, double length})? Function(int from)? way,
});

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
  }) : lane = null,
       graph = null,
       folded = false;

  const TimelineDisplayRow.lane(
    this.layer,
    PropertyLaneRow this.lane, {
    required this.layerIndex,
    this.graph,
    this.folded = false,
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

  /// The open HEADER GRAPH this lane is drawn in (I-89 ③), or null — a
  /// lane of a group whose graph is shut, every header, every layer row.
  final TimelineGraphSeat? graph;

  /// Whether this lane is FOLDED to a thin strip under a graph enlarged
  /// over it (I-89 ③D) — what it, or the other graph it is drawn in,
  /// stands while that graph has the panel. Every header and every layer
  /// row stand whole (the mock's 5판).
  final bool folded;

  /// This lane as a header graph draws it — the same row, drawn in its
  /// group's graph where [seat] is one, and [folded] where one enlarged
  /// over it says so.
  TimelineDisplayRow seatedIn(
    TimelineGraphSeat? seat, {
    bool folded = false,
  }) => TimelineDisplayRow.lane(
    layer,
    lane!,
    layerIndex: layerIndex,
    graph: seat,
    folded: folded,
  );

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

/// THE CHAIN a [PropertyLaneRow.linkable] lane wears: whether it is on,
/// what says so changed — the switch is flipped from elsewhere too — and
/// the press that flips it. Its name is the chain's own
/// (`ScaleChainButton`): one switch, one name.
typedef PropertyLaneValueLink = ({
  Listenable changes,
  bool Function() isOn,
  VoidCallback toggle,
});

/// What a header graph's key drag writes into the keys the lane selection
/// holds as it carries them (I-3 ②): each key's value as its lane's value
/// editor reads it ([PropertyLaneEditCallbacks.onSetValue]), by lane and
/// by frame, and whether a Scale's two numbers are chained
/// ([PropertyLaneEditCallbacks.valueLink]) — the value editor's write,
/// key by key.
typedef LaneKeyValues = ({
  Map<String, Map<int, String>> inputs,
  bool scaleLinked,
});

/// Where a header graph's box puts down each key it holds where they do
/// not all go alike — one corner of it pulled alone (graph-box-handles-more
/// ⓐ): by lane and by frame, the frame each key lands on.
typedef LaneKeyLandings = Map<String, Map<int, int>>;

/// Lane key edit hooks — layer-generic on purpose: the camera routes them
/// into its transform track today, and every layer (and FX property) plugs
/// into the same signatures with the layer-transform work.
class PropertyLaneEditCallbacks {
  const PropertyLaneEditCallbacks({
    required this.onToggleKeyAt,
    this.onSetValue,
    this.onPreviewValue,
    this.onEndPreview,
    this.onSetKeySides,
    this.onPreviewKeySides,
    this.valueLink,
    this.keyedNow,
    this.valueNow,
  });

  /// Adds a key (freezing the property's current value, AE-style) or
  /// removes the existing one — the keyframe navigator's diamond.
  final void Function(Layer layer, PropertyLaneRow lane, int frameIndex)
  onToggleKeyAt;

  /// Whether [lane] of [layer] holds a key at [frameIndex] as the document
  /// stands NOW — what the ◆ shows, read where a rail's bulk-drag spreads
  /// what a press just set (F-475): a row built at the last frame still
  /// carries the keys from before the press. Null where the rail reads
  /// none.
  final bool? Function(Layer layer, PropertyLaneRow lane, int frameIndex)?
  keyedNow;

  /// [lane]'s value at [frameIndex] as the document stands NOW, written as
  /// its row writes it ([PropertyLaneRow.valueLabel]) — read as [keyedNow]
  /// is.
  final String? Function(Layer layer, PropertyLaneRow lane, int frameIndex)?
  valueNow;

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

  /// A value being SCRUBBED: what [onSetValue] would write, to be SHOWN
  /// while the drag lasts (F-195) — the label reads it back through the
  /// row gate like every other panel showing the row, so it follows the
  /// hand with the picture instead of ahead of it.
  final void Function(
    Layer layer,
    PropertyLaneRow lane,
    int frameIndex,
    String input,
  )?
  onPreviewValue;

  /// A scrub that went away without a release: what [onPreviewValue]
  /// showed is dropped — and what [onPreviewKeySides] showed.
  final VoidCallback? onEndPreview;

  /// A header graph's handle let go (I-89 ③): the key of [lane] at
  /// [frameIndex] — and every key the lane range covers, when it holds that
  /// one — eased as [sides] say.
  final void Function(
    Layer layer,
    PropertyLaneRow lane,
    int frameIndex,
    KeySidesEdit sides,
  )?
  onSetKeySides;

  /// A handle mid-drag: what [onSetKeySides] would write, to be SHOWN while
  /// the drag lasts, as [onPreviewValue] shows a scrub.
  final void Function(
    Layer layer,
    PropertyLaneRow lane,
    int frameIndex,
    KeySidesEdit sides,
  )?
  onPreviewKeySides;

  /// The chain of the lanes whose value is a linked pair — null leaves it
  /// off their rows.
  final PropertyLaneValueLink? valueLink;

  /// These edits, landing on [layer] whichever row hands them over — a row
  /// that wears a layer under an address of its own (the storyboard's
  /// camera row, whose lanes are those of the camera of the cut it stands
  /// in, I-73 ④ⓔ) edits that layer.
  PropertyLaneEditCallbacks landingOn(Layer layer) {
    final setValue = onSetValue;
    final previewValue = onPreviewValue;
    final setKeySides = onSetKeySides;
    final previewKeySides = onPreviewKeySides;
    final keyed = keyedNow;
    final value = valueNow;
    return PropertyLaneEditCallbacks(
      onToggleKeyAt: (_, lane, frameIndex) =>
          onToggleKeyAt(layer, lane, frameIndex),
      onSetValue: setValue == null
          ? null
          : (_, lane, frameIndex, input) =>
                setValue(layer, lane, frameIndex, input),
      onPreviewValue: previewValue == null
          ? null
          : (_, lane, frameIndex, input) =>
                previewValue(layer, lane, frameIndex, input),
      onEndPreview: onEndPreview,
      onSetKeySides: setKeySides == null
          ? null
          : (_, lane, frameIndex, sides) =>
                setKeySides(layer, lane, frameIndex, sides),
      onPreviewKeySides: previewKeySides == null
          ? null
          : (_, lane, frameIndex, sides) =>
                previewKeySides(layer, lane, frameIndex, sides),
      valueLink: valueLink,
      keyedNow: keyed == null
          ? null
          : (_, lane, frameIndex) => keyed(layer, lane, frameIndex),
      valueNow: value == null
          ? null
          : (_, lane, frameIndex) => value(layer, lane, frameIndex),
    );
  }
}

/// [folder]'s row as the grids render it — its BAND: the folder carrying, as
/// an ordinary timeline, the blocks its [members] make together
/// ([folderAggregateRuns]) and, where none of them stands a block, the
/// ghosts they project ([folderGhostRuns]).
///
/// Its entries resolve to no Frame on purpose: nothing composites a folder
/// band, it only paints. A ghost is stamped the way a row's own is, so the
/// shared cells painter draws a hold's dash here as it does there. The
/// stamp's SIDE is the row's business — a band paints the mode, and
/// nothing reads its side.
Layer folderBandOf(Layer folder, Iterable<Layer> members) {
  final runs = folderAggregateRuns(members);
  FrameId celAt(int start) => FrameId('band:${folder.id.value}:$start');
  final band = folder.copyWith(
    timeline: {
      for (final run in runs)
        run.start: TimelineExposure.drawing(
          celAt(run.start),
          length: run.endExclusive - run.start,
        ),
      for (final ghost in folderGhostRuns(members, runs))
        ghost.start: TimelineExposure.drawing(
          celAt(ghost.start),
          length: ghost.endExclusive - ghost.start,
          ghostOf: TimelineRunEdgeGhost(
            side: TimelineRunEdgeSide.end,
            mode: ghost.mode,
          ),
        ),
    },
  );
  folderBandStandsFor(band, members);
  return band;
}

/// The rows [band] is made of — what a drag in flight re-reads it from
/// (`rowShownWhileMoved`); null for every layer that is no band.
///
/// 🐛folder-band-lags-a-comma-drag (10-27): a folder's row is what its rows
/// hold (F-311), so it follows the hand as they do — and it did for a block
/// MOVE alone, whose drag laid the bands in its own preview. A comma drag
/// and a file held over a row put their one row there, and the folder stood
/// where it was until the release. So the band says what it stands for,
/// as a mirror says its base (`attachedDisplayBaseOf`), and whatever reads
/// a row as a drag shows it reads a folder's from its rows.
List<Layer>? folderBandRowsOf(Layer band) => _bandRows[band];

/// Notes that [band] stands for [rows]: [folderBandOf]'s own, and a cache's
/// that keeps a band while the rows under it changed and its blocks did not.
void folderBandStandsFor(Layer band, Iterable<Layer> rows) =>
    _bandRows[band] = List.unmodifiable(rows);

/// The rows each band stands for, held weakly like the bands themselves.
final Expando<List<Layer>> _bandRows = Expando('folder band rows');

/// The folder row's aggregate band (the TVP-latest display): the UNION of
/// the subtree members' BLOCKS merged into runs. Nameless, and no comma
/// edits.
///
/// ↩️F-311 (유저 2026-10-06): it was 「pure display … no moves」, and the
/// union took every entry a member's timeline holds.
///  · 「폴더의 블록 드래그로 이동할 수 있게. 내부 전체적으로 이동하는 느낌」 —
///    a run is what a drag on the folder's row carries now: the rows the
///    folder holds ride it (`rowsHeldByFolderRowsOf`).
///  · 「지금 성질 홀드로하면 폴더에서 콘티블록마냥 블록 꽉 채워지는데, 그거말고
///    홀드면 홀드 점선 그대로 사용하도록. 왜냐하면 홀드면 사실 뒤가 빈공간인데
///    블록 드래그 이동하기 번거로우니까. 그래서 실제 존재하는 블록만 제대로
///    하고싶은것. 리피트의 고스트프레임도 마찬가지」 — a GHOST is an entry of
///    the timeline and no block of the row: merged in like one, a hold ran
///    the folder's block to the end of the cut. What the members project
///    there is [folderGhostRuns].
List<({int start, int endExclusive})> folderAggregateRuns(
  Iterable<Layer> members,
) => _mergedRuns([
  for (final member in members)
    for (final entry in member.timeline.entries)
      if (entry.value.length != null && !entry.value.ghost)
        (start: entry.key, endExclusive: entry.key + entry.value.length!),
]);

/// What a folder's band shows where none of its rows stands a block and
/// one projects a ghost — beside [runs], its blocks: a hold's stretch, then
/// a repeat's where no hold reaches (the order the rows' own rederive lays
/// them in).
List<({int start, int endExclusive, TimelineRunEdgeMode mode})>
folderGhostRuns(
  Iterable<Layer> members,
  List<({int start, int endExclusive})> runs,
) {
  List<({int start, int endExclusive})> projected(TimelineRunEdgeMode mode) =>
      _mergedRuns([
        for (final member in members)
          for (final entry in member.timeline.entries)
            if (entry.value.ghostOf?.mode == mode)
              (start: entry.key, endExclusive: entry.key + entry.value.length!),
      ]);
  final holds = _runsOutside(projected(TimelineRunEdgeMode.hold), runs);
  final repeats = _runsOutside(
    projected(TimelineRunEdgeMode.repeat),
    _mergedRuns([...runs, ...holds]),
  );
  return [
    for (final (:start, :endExclusive) in holds)
      (
        start: start,
        endExclusive: endExclusive,
        mode: TimelineRunEdgeMode.hold,
      ),
    for (final (:start, :endExclusive) in repeats)
      (
        start: start,
        endExclusive: endExclusive,
        mode: TimelineRunEdgeMode.repeat,
      ),
  ];
}

/// The stretches of [runs] that [taken] leaves free — each list in order,
/// no two of its runs meeting.
List<({int start, int endExclusive})> _runsOutside(
  List<({int start, int endExclusive})> runs,
  List<({int start, int endExclusive})> taken,
) {
  final free = <({int start, int endExclusive})>[];
  for (final run in runs) {
    var from = run.start;
    for (final other in taken) {
      if (other.endExclusive <= from) {
        continue;
      }
      if (other.start >= run.endExclusive) {
        break;
      }
      if (other.start > from) {
        free.add((start: from, endExclusive: other.start));
      }
      from = other.endExclusive;
    }
    if (from < run.endExclusive) {
      free.add((start: from, endExclusive: run.endExclusive));
    }
  }
  return free;
}

/// [intervals] as runs: in order, every two that meet or overlap made one.
List<({int start, int endExclusive})> _mergedRuns(
  Iterable<({int start, int endExclusive})> intervals,
) {
  final inOrder = [...intervals]..sort((a, b) => a.start.compareTo(b.start));
  final runs = <({int start, int endExclusive})>[];
  for (final interval in inOrder) {
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
  return laneAsPreviewed(committed, lanesForLayer(previewLayer));
}

/// [committed] as [previewed] — the lanes re-derived from a preview — show
/// it: the lane with its id. The storyboard's labels re-derive their own
/// lists and take the same answer here.
PropertyLaneRow laneAsPreviewed(
  PropertyLaneRow committed,
  Iterable<PropertyLaneRow> previewed,
) {
  for (final lane in previewed) {
    if (lane.laneId == committed.laneId) {
      return lane;
    }
  }
  // A preview that drops the lane entirely (nothing does today) leaves the
  // committed row standing rather than blanking mid-drag.
  return committed;
}

/// Why a layer's row is OFF THE SCREEN — the one answer the grids draw by
/// ([buildTimelineDisplayRows]) and the standing law lands by
/// (`Standing.keepStandingShown`).
///
/// 🚨F-169 (유저 2026-09-24): 「보이는거만 선택가능하고 안보이는거 선택되는
/// 상황엔 다른 보이는레이어 선택하도록」. The rows answered 「which rows show」
/// with an exemption for whatever stood, and the session's hand-off answered
/// 「which row stands」 without asking which rows showed — so a delete handed
/// the standing row into a folded attach group, and the group looked unfolded.
enum LayerRowHiddenBy {
  /// Its section is hidden (the toolbar's SE/CAMERA toggles).
  section,

  /// Its attach group is twirled shut (UI-R20 #9).
  attachFold,

  /// The row filter refuses it (R2).
  filter,

  /// A folder above it is collapsed (R27 #24).
  folderFold,
}

/// [layer]'s row: null when it is on screen, otherwise the FIRST of the
/// rail's reasons that hides it, asked in [LayerRowHiddenBy]'s order.
///
/// [folders] indexes the MODEL stack and [attachBaseId] is
/// [attachGroupBaseOf] against it — the row builder needs that base again
/// for the indent, so it is asked once, outside.
///
/// [standingLayerId] is the row the FILTER spares — a filter never hides
/// the row you are editing ([TimelineRowFilter.allowsRow]). The folds and
/// the sections spare nothing: ↩️an attach group used to spare its active
/// row the same way (UI-R20 #9), and that exemption is what put a handed-off
/// row on the screen inside a shut group (F-169). Nothing stands inside a
/// fold now — the standing law hands off to the fold's head, or opens it.
LayerRowHiddenBy? layerRowHiddenBy(
  Layer layer, {
  required LayerFolderIndex folders,
  required LayerId? attachBaseId,
  Set<TimelineSection> hiddenSections = const {},
  TimelineRowFilter rowFilter = TimelineRowFilter.none,
  Set<LayerId> collapsedAttachBaseIds = const {},
  LayerId? standingLayerId,
  bool Function(LayerId layerId)? fxEnabledOf,
}) {
  if (hiddenSections.contains(timelineSectionForLayerKind(layer.kind))) {
    return LayerRowHiddenBy.section;
  }
  if (attachBaseId != null && collapsedAttachBaseIds.contains(attachBaseId)) {
    return LayerRowHiddenBy.attachFold;
  }
  if (!rowFilter.allowsLayerRow(
    layer,
    standing: layer.id == standingLayerId,
    fxEnabled: fxEnabledOf?.call(layer.id) ?? true,
  )) {
    return LayerRowHiddenBy.filter;
  }
  // R27 #24: a collapsed folder folds ALL its members, the active layer
  // included. The old active-layer exemption meant folding a folder
  // whose member was selected simply didn't look folded; the folder row
  // takes the selection instead (EditorSessionManager.toggleLayerCollapsed).
  if (folders.subtreeCollapsed(layer.folderId)) {
    return LayerRowHiddenBy.folderFold;
  }
  return null;
}

/// Builds the grid's display rows: every layer row [layerRowHiddenBy]
/// leaves on screen, plus the property lane rows of layers whose twirl-down
/// is expanded. Both orientations consume the same policy (Axis rule).
///
/// [activeLayerId] is the row the filter spares; [fxEnabledOf] resolves
/// the session-level fx state the filter's fx-only facet reads.
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
  // 🚨F-249 (유저 2026-10-01): 「과거 결정 번복. 역시 변형 펼칠땐 어태치레이어의
  // 밑이아니라 레이어의 밑에 오도록 하고싶음. 즉 기준레이어 fx펼치면
  // 기준레이어 밑에 fx행오도록」 — a layer's lanes follow ITS OWN row, a
  // base's as much as an attach row's.
  //
  // ↩️R26 #36 (07-22) held a base's lanes back until its trailing attach
  // rows were laid (base → attach rows → lanes), because the attach group
  // is unsplittable. The group stays one for the fold and for a drop
  // (`newRowPlacement`, `layer_drop_policy`); where the lanes sit is no
  // longer that rule's question.

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
    final attachBaseId = attachGroupBaseOf(layer, modelStack);
    if (layerRowHiddenBy(
          layer,
          folders: folders,
          attachBaseId: attachBaseId,
          hiddenSections: hiddenSections,
          rowFilter: rowFilter,
          collapsedAttachBaseIds: collapsedAttachBaseIds,
          standingLayerId: activeLayerId,
          fxEnabledOf: fxEnabledOf,
        ) !=
        null) {
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
    for (final lane in lanesForLayer(layer)) {
      rows.add(TimelineDisplayRow.lane(layer, lane, layerIndex: index));
    }
  }
  return List.unmodifiable(rows);
}

/// [rows] — the timeline's, built by [buildTimelineDisplayRows] — with each
/// lane RUN flipped to the near side of its owner's row and reversed: the
/// x-sheet's.
///
/// R9 #23/#24 — ONE rule for where a twirled-down lane sits: **further
/// from the layer means applied later**. On the horizontal axis "further"
/// is DOWN, so the lanes follow their layer in pipeline order (effects,
/// then Transform last). On the x-sheet the rows are COLUMNS and the
/// user's direction is LEFTWARD, so the same list stands BEFORE the layer
/// and reversed — the last-applied lane ends up furthest left. Deciding
/// the two separately is how they came to disagree in the first place.
///
/// ⚠️Flipped AFTER the rows' graphs are seated (I-89 ③D): a seat lists
/// its lanes as the rail draws them, so the sheet's graph — the strip a
/// folded one thins to, the order its lines are drawn in — is the
/// timeline's turned on its side. Seated after, a folded graph's strip
/// was its first lane's on the timeline and its last's on the sheet.
///
/// ↩️It moved the run past the owner's WHOLE attach group, mirroring R26
/// #36 on the horizontal axis. F-249 (유저 2026-10-01) put a base's lanes
/// right under its own row there, so here they sit right beside it.
List<TimelineDisplayRow> laneRunsMovedAhead(List<TimelineDisplayRow> rows) {
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
    // A run follows its owner's row, so the owner is the row just laid.
    final owner = out.lastIndexWhere(
      (row) => !row.isLane && row.layer.id == ownerId,
    );
    out.insertAll(owner < 0 ? out.length : owner, run.reversed);
  }
  return List.unmodifiable(out);
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
