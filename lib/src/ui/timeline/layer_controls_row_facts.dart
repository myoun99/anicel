import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/attached_layer_resolve.dart'
    show attachRowWearsBaseComposite;
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart' show LayerFxState;
import '../../models/timeline_row_address.dart';
import '../text/app_strings.dart' show AppText;
import 'berth_row.dart';
import 'lane_graph.dart' show LaneGraphsView, TimelineGraphSeat;
import 'lane_graph_seats.dart' show laneGraphHeadedBy;
import 'layer_label_controls.dart' show LayerRailColumnWidths;
import 'layer_rail_columns.dart' show LayerRailOptionalColumns;
import 'layer_row_drag.dart' show LayerRowDragInputs;
import 'memo_token.dart';
import 'property_lane_model.dart' show PropertyLaneRow, TimelineDisplayRow;
import 'row_berths.dart';
import 'timeline_drag_preview.dart' show TimelineDragPreview;
import 'timeline_grid_hooks.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_layer_controls_row.dart';

/// What a layer's CONTROLS ROW is built from — every fact it SHOWS, read off
/// a grid's hooks for one display row.
///
/// 🚨ONE reading for the timeline's rail and the x-sheet's header strip
/// (F-244). The two built the same row, rotated, each from its own
/// spelling of these facts — the fold twirl's copy was found the same way
/// ([timelineGroupFoldFor]) — and only the rail kept its rows: the x-sheet
/// built every header again at every commit (8,276 elements on 24 layers,
/// fifteen times the timeline's).
///
/// 🚨Also the key of the memo both grids keep ([KeptLayerControlsRows]): a
/// row is kept while these hold. ⛔A fact the row takes and this leaves out
/// is a row kept across a change of it — the rail's own key had left out
/// four the row was given (a reference row's shortfall, an attach row's
/// base composite, a folder member's opacity override, the rail's column
/// widths). The row's VERBS are not facts: a host wires the same verbs for
/// its whole life, and a kept row calls them through the hooks it was
/// built with, each asking the session at the event. ⛔Nor is whether the
/// row is the one stood on: a stand changes one colour on two rows, and it
/// reaches the plate past the memo ([RailStand]).
///
/// Zoom-independent by construction (UI-R7 #1): nothing here reads
/// frameCellWidth, so zoom steps always hit. The row reads the four
/// metrics below and no other — a fifth read joins them here.
typedef LayerControlsRowFacts = ({
  // What the row SHOWS gates content, not the Layer's identity: a
  // timesheet edit rebuilds the edited layer's instance while every
  // rail-visible field stays put (see the completeness contract on
  // [ControlsRowFace]).
  ControlsRowFace layer,
  bool hasLanes,
  bool lanesExpanded,
  int depth,
  bool hasGroupFold,
  bool groupFoldExpanded,
  LayerFxState fxState,
  bool onionSkinEnabled,
  // The rows the pictures are shared with — a fresh list every build, so
  // compared by what it holds ([ByList]).
  ByList<String> linkPartners,
  // The cut the row's cut is in the other timelines, when the row is one
  // they share (a 동기컷, I-150-Q3) — compared like [linkPartners].
  ByList<String> syncPartners,
  // Solo is SESSION state, not a Layer field, so the layer comparison
  // cannot see it: the speaker's accent tint went stale the moment
  // solo moved anywhere but this row. It has always been shown here —
  // R10 R3 only made it settable from every rail, which is what turned
  // a latent staleness into one a user would hit.
  bool soloed,
  // The arrow reads the STACK (a folder's direction is its position
  // against its base), so the Layer comparison cannot see it change.
  AttachedPlacement? attachArrow,
  bool isReferenceSourceShort,
  bool wearsBaseComposite,
  // I-89 ③: whether the row heads a header graph — the camera row, the
  // row being its own Transform group (㉙) — and whether it stands open:
  // view state, which the Layer cannot see. Not WHICH graph: its key is
  // spelled with the layer's id, so the row reads it at the press, of the
  // layer it stands for then (I-57 ㉣).
  bool headsGraph,
  bool graphOpen,
  ByIdentity<ValueListenable<({Set<LayerId> layerIds, double opacity})?>?>
  opacityDragPreview,
  double layerRowHeight,
  double layerControlsWidth,
  double sectionLabelGutterWidth,
  LayerRailColumnWidths railColumns,
  // The extent the row is laid out at along its axis — the x-sheet
  // header's natural one; null on the rail, where the row sizes itself.
  double? mainExtent,
  // R27 #6: the blend chip prints a LANGUAGE-dependent name — a language
  // switch must invalidate the memo like any other visible fact. Read from
  // [AppText.language] when the token is made (F-170), not handed down.
  // ⛔MUTANT SURVIVES HERE (2026-09-23): a fixed language in this slot left
  // `a_language_that_lands_late_reaches_every_word_test` green — the chip
  // reads the theme, so it rebuilds itself when the app root rebuilds for
  // the language, memo or no memo. Kept because the memo's own rule is that
  // every visible fact is in its token, and a row word that stopped reading
  // the theme would keep the last language's without it.
  AppLanguage language,
});

/// A grid as its controls rows see it: what it reads them from, and how it
/// stands them — the rail as it is, the x-sheet's header strip turned on
/// its side ([axis] vertical, [keyPrefix] `xsheet`, each header laid out
/// at [mainExtent]; null on the rail, where the row sizes itself).
///
/// One record for the facts and the row, so the two cannot be read off
/// different hooks or metrics.
typedef LayerControlsRowGrid = ({
  TimelineGridHooks hooks,
  List<Layer> layers,
  TimelineGridMetrics metrics,
  Axis axis,
  String keyPrefix,
  double? mainExtent,
});

/// The facts of [row]'s controls row as [grid] tells them. [fold] and
/// [hasLanes] are the grid's to answer — each asks them its own way of the
/// same rules ([timelineGroupFoldFor], the lanes it draws).
LayerControlsRowFacts layerControlsRowFacts(
  TimelineDisplayRow row,
  LayerControlsRowGrid grid, {
  required TimelineGroupFold fold,
  required bool hasLanes,
}) {
  final hooks = grid.hooks;
  final id = row.layer.id;
  final graphKey = laneGraphHeadedBy(row.layer, null);
  return (
    layer: ControlsRowFace(row.layer),
    hasLanes: hasLanes,
    lanesExpanded: hooks.expandedLaneLayerIds.contains(id),
    depth: row.depth,
    hasGroupFold: fold.has,
    groupFoldExpanded: fold.expanded,
    fxState: hooks.layerFxStateOf?.call(id) ?? LayerFxState.on,
    onionSkinEnabled: hooks.layerOnionSkinEnabledOf?.call(id) ?? false,
    linkPartners: ByList(hooks.layerLinkPartnersOf?.call(id) ?? const []),
    syncPartners: ByList(hooks.layerSyncPartnersOf?.call(id) ?? const []),
    soloed: hooks.isLayerSoloed?.call(id) ?? false,
    attachArrow: hooks.attachArrowPlacementOf?.call(id),
    isReferenceSourceShort: hooks.layerSourceIsShortOf?.call(id) ?? false,
    wearsBaseComposite: attachRowWearsBaseComposite(row.layer, grid.layers),
    headsGraph: graphKey != null,
    graphOpen:
        graphKey != null && hooks.laneGraphs.open.containsKey(graphKey),
    opacityDragPreview: ByIdentity(hooks.opacityDragPreview),
    layerRowHeight: grid.metrics.layerRowHeight,
    layerControlsWidth: grid.metrics.layerControlsWidth,
    sectionLabelGutterWidth: grid.metrics.sectionLabelGutterWidth,
    railColumns: grid.metrics.railColumns,
    mainExtent: grid.mainExtent,
    language: AppText.language,
  );
}

/// [row]'s controls row, built from [facts] and wired to [grid]'s verbs
/// ([fold] is the twirl the facts were read with, for its verb).
Widget layerControlsRowFrom(
  LayerControlsRowFacts facts,
  TimelineDisplayRow row,
  LayerControlsRowGrid grid,
  TimelineGroupFold fold,
) {
  final hooks = grid.hooks;
  return TimelineLayerControlsRow(
    axis: grid.axis,
    keyPrefix: grid.keyPrefix,
    mainExtent: facts.mainExtent,
    layer: row.layer,
    wearsBaseComposite: facts.wearsBaseComposite,
    metrics: grid.metrics,
    onSelectLayer: hooks.onSelectLayer,
    // T10: the rail row and the frame cells take the SAME settled-tap
    // clear, because 「행이든 뭐든 동일하게」.
    onSettledPress: hooks.onSettledPress,
    labelDoubleClick: hooks.labelDoubleClick,
    onToggleLayerVisibility: hooks.onToggleLayerVisibility,
    onLayerOpacityChanged: hooks.onLayerOpacityChanged,
    onLayerOpacityChangeEnd: hooks.onLayerOpacityChangeEnd,
    onToggleLayerTimesheet: hooks.onToggleLayerTimesheet,
    fxState: facts.fxState,
    onToggleLayerFx: hooks.onToggleLayerFx,
    onionSkinEnabled: facts.onionSkinEnabled,
    onToggleLayerOnionSkin: hooks.onToggleLayerOnionSkin,
    onLayerMarkSelected: hooks.onLayerMarkSelected,
    onToggleLayerClip: hooks.onToggleLayerClip,
    onOpenLayerMixer: hooks.onOpenLayerMixer,
    onOpenLayerReference: hooks.onOpenLayerReference,
    onOpenLayerLinks: hooks.onOpenLayerLinks,
    onOpenCameraPath: hooks.onOpenCameraPath,
    isReferenceSourceShort: facts.isReferenceSourceShort,
    isLayerSoloed: facts.soloed,
    attachArrowPlacement: facts.attachArrow,
    hasLanes: facts.hasLanes,
    lanesExpanded: facts.lanesExpanded,
    onToggleLanes: hooks.onToggleLayerLanes,
    depth: facts.depth,
    // One fold twirl: a folder folds its members, an attach base folds
    // its attach rows — the one answer both grids ask for.
    hasGroupFold: facts.hasGroupFold,
    groupFoldExpanded: facts.groupFoldExpanded,
    onToggleGroupFold: fold.onToggle,
    opacityDragPreview: facts.opacityDragPreview.value,
    linkPartners: facts.linkPartners.value,
    syncPartners: facts.syncPartners.value,
    onLayerBlendModeSelected: hooks.onLayerBlendModeSelected,
    laneGraphVerbs: hooks.laneGraphVerbs,
    headsGraph: facts.headsGraph,
    graphOpen: facts.graphOpen,
  );
}

/// What a LANE's controls row is built from — its name, keys and value on
/// the rail, a column's header turned on its side on the sheet
/// ([TimelineLaneControlsRow]) — read off a grid's hooks for one display
/// row: ONE reading for both grids, as a layer's row has.
///
/// 🚨Card a-rail-lane-row-is-drawn-again-on-every-host-pass (2026-11-07):
/// lane rows were built again at every pass of their host — a runway step
/// past the cut's end, a notify that changed nothing — and a row's tick
/// layer, handed a new child, was laid out and painted again: the row's
/// still region threw its image away and took another (🔬the six lane rows
/// of one twirled-open layer, at one runway step). ↩️They stood unkept
/// because their lane models were new objects at every pass; a host that
/// hands its lanes back as the same objects while what they are read from
/// holds ([KeptTimelineLanes]) makes a lane a fact by identity, as a
/// listenable is. A host that reads them anew builds its lane rows anew,
/// as every pass did before.
///
/// ⛔As a layer row's, its VERBS are not facts. The row reads the four
/// metrics below and no other.
typedef LaneControlsRowFacts = ({
  // The lane is made of its layer, and the row's drag gate previews the
  // layer.
  ByIdentity<Layer> layer,
  ByIdentity<PropertyLaneRow> lane,
  TimelineGraphSeat? seat,
  bool folded,
  double layerRowHeight,
  double layerControlsWidth,
  double sectionLabelGutterWidth,
  LayerRailColumnWidths railColumns,
  double? mainExtent,
  LayerRailOptionalColumns optionalColumns,
  LaneGraphsView laneGraphs,
  // What the row listens to itself: the preview its gate reads, the frame
  // it reads its value at and the row stood on.
  ByIdentity<ValueListenable<TimelineDragPreview?>?> dragPreview,
  ByIdentity<ValueListenable<int>> frameCursor,
  ByIdentity<ValueListenable<TimelineRowAddress?>?> currentRow,
});

/// The facts of [row]'s lane controls row as [grid] tells them.
LaneControlsRowFacts laneControlsRowFacts(
  TimelineDisplayRow row,
  LayerControlsRowGrid grid,
) {
  final hooks = grid.hooks;
  return (
    layer: ByIdentity(row.layer),
    lane: ByIdentity(row.lane!),
    seat: row.graph,
    folded: row.folded,
    layerRowHeight: grid.metrics.layerRowHeight,
    layerControlsWidth: grid.metrics.layerControlsWidth,
    sectionLabelGutterWidth: grid.metrics.sectionLabelGutterWidth,
    railColumns: grid.metrics.railColumns,
    mainExtent: grid.mainExtent,
    optionalColumns: hooks.optionalRailColumns,
    laneGraphs: hooks.laneGraphs,
    dragPreview: ByIdentity(hooks.dragPreview),
    frameCursor: ByIdentity(hooks.frameCursor),
    currentRow: ByIdentity(hooks.currentRowHooks?.currentRow),
  );
}

/// What a kept lane controls row was built from: its facts and what its
/// drag wrapper was built from.
typedef LaneControlsRowInputs = ({
  LaneControlsRowFacts facts,
  LayerRowDragInputs drag,
});

/// What a kept controls row was built from: its facts and what its drag
/// wrapper was built from.
typedef LayerControlsRowInputs = ({
  LayerControlsRowFacts facts,
  // F-244: the row's DRAG wrapper is kept with it, so a commit that moved
  // no row rebuilds no wrapper (it rebuilt all of them, ~170 elements on
  // 24 rows) — keyed on what the wrapper is built from, which its own
  // module answers ([layerRowDragInputs]: the host's hooks, bound once
  // there, the span verb and the caret line it paints).
  LayerRowDragInputs drag,
});

/// What a grid keeps of its layers' controls rows, berth by berth
/// ([KeptByBerth]): each row as built, and the drag wrapper around it.
///
/// 🚨I-57 ㉣ (10-13): TWO keeps, because the two are built from different
/// things. The row is built from what it SHOWS — its facts name no layer
/// ([ControlsRowFace]) — so a cut switch that puts a row of the same face
/// in a berth hands the row back whole, and the row acts on the layer it
/// stands for through [BerthRow]. The wrapper is built from the row's
/// ADDRESS — a drag carries the layer it moves — so it is built again
/// whenever its berth holds another row, around the same row.
///
/// ONE memo for the rail's rows and the x-sheet's headers — a grid says
/// how its rows drag once, when it makes its keep ([drags]: the wrapper
/// it puts on a row), and of each row only the wrapper's inputs. A lane's
/// row is kept here too ([keepLane]).
final class KeptLayerControlsRows {
  KeptLayerControlsRows(this.drags);

  final Widget Function(TimelineDisplayRow row, Widget built) drags;
  final KeptByBerth<LayerControlsRowFacts> _rows = KeptByBerth();
  final KeptByBerth<LaneControlsRowFacts> _lanes = KeptByBerth();
  final KeptByBerth<_LayerControlsRowWrap> _wrapped = KeptByBerth();

  /// [row]'s controls row in its berth of [berths] (F-244): the row
  /// [build] makes, kept while its facts hold, in the drag wrapper put on
  /// it, kept while the row and its address do — so a commit rebuilds no
  /// row it did not change, and a cut switch none whose face it left
  /// alone.
  Widget keep(
    RowBerthMap berths,
    TimelineDisplayRow row,
    LayerControlsRowInputs inputs,
    Widget Function() build,
  ) => BerthRow(
    layer: row.layer,
    child: _wrap(
      berths,
      row,
      _rows.keep(berths, row, inputs.facts, build),
      inputs.drag,
    ),
  );

  /// [row]'s LANE controls row in its berth of [berths]: the row [build]
  /// makes, kept while its facts hold, in its drag wrapper kept as a layer
  /// row's is. No [BerthRow]: its facts name its layer, so a kept lane row
  /// is never handed to another.
  Widget keepLane(
    RowBerthMap berths,
    TimelineDisplayRow row,
    LaneControlsRowInputs inputs,
    Widget Function() build,
  ) => _wrap(
    berths,
    row,
    _lanes.keep(berths, row, inputs.facts, build),
    inputs.drag,
  );

  /// [built] in the drag wrapper put on it, kept while [row]'s address, the
  /// row it is put on and what it is built from ([drag]) hold.
  Widget _wrap(
    RowBerthMap berths,
    TimelineDisplayRow row,
    Widget built,
    LayerRowDragInputs drag,
  ) => _wrapped.keep(
    berths,
    row,
    (drag: drag, address: row.address, row: ByIdentity(built)),
    () => drags(row, built),
  );
}

/// What a kept row's drag wrapper is built from: the wrapper's inputs, the
/// row it moves, and the row it is put on.
typedef _LayerControlsRowWrap = ({
  LayerRowDragInputs drag,
  TimelineRowAddress address,
  ByIdentity<Widget> row,
});
