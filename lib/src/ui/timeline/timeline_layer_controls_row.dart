import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../widgets/app_icon_button.dart';
import '../../models/app_language.dart' show AppLanguage;
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../input/app_input_settings.dart' show AppInput;
import '../widgets/field_slider.dart';
import '../widgets/instant_tap_region.dart';
import '../text/vertical_writing_text.dart';
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import '../text/app_strings.dart' show AppText;
import 'timeline_grid_metrics.dart';
import '../../models/attached_layer_resolve.dart' show attachedLayersOf;
import 'property_lane_model.dart' show TimelineDisplayRow;

/// Whether two [Layer] snapshots would make [TimelineLayerControlsRow] look
/// EXACTLY the same — the rail memo's gate.
///
/// The row plate's own chrome before its first cell — the left border.
///
/// 🚨Every leading column therefore sits this much further in than the slot
/// skeleton alone says, which is a whole pixel of drift for anything that
/// LOCATES a column by measuring from the row's edge (I-1's swipe bands).
/// Named rather than left as `BorderSide`'s default so the two readings come
/// from one number. The chromeless row draws no border and no swipe reaches
/// it — the collapsed overlay is a different surface.
const double timelineLayerRowLeadingBorder = 1;

/// Layer identity is the wrong question here: a timesheet edit (a drawing
/// landed, an exposure cut, a block moved) hands back a new Layer instance
/// whose every RAIL-visible field is unchanged, and the rail row is ~200
/// Material widgets — measured at 24 layers, rebuilding it was a fifth of a
/// session notify's widget rebuilds for nothing on screen.
///
/// COMPLETENESS CONTRACT: every Layer field this row (or anything it builds)
/// RENDERS must be compared here — miss one and the rail shows stale state
/// until something else invalidates. The row's callbacks are all keyed by
/// [LayerId], never by the Layer value, so a cached row holding an older
/// instance can only be stale in what this function compares.
/// `timeline_rail_row_memo_test.dart` drives one mutation per field.
///
/// Deliberately absent (the row renders none of them): `frames`, `timeline`,
/// `instructions`, `audioClips`, `baseFrameLinks`, `runBehaviors`,
/// `transformTrack` (the LANE rows read it, and those are unmemoized),
/// `audioGain`/`audioPan` (the mixer reads them from the session while it
/// is open), `attachedMode` and `folderId`.
bool timelineLayerControlsRowShowsSameState(Layer a, Layer b) {
  return identical(a, b) ||
      (a.id == b.id &&
          a.name == b.name &&
          a.kind == b.kind &&
          a.opacity == b.opacity &&
          a.isVisible == b.isVisible &&
          a.muted == b.muted &&
          a.mark == b.mark &&
          a.onTimesheet == b.onTimesheet &&
          a.blendMode == b.blendMode &&
          a.collapsed == b.collapsed &&
          a.isFillReference == b.isFillReference &&
          a.attachedToLayerId == b.attachedToLayerId &&
          a.attachedPlacement == b.attachedPlacement);
}

/// A layer's controls — the twelve-slot strip the rail shows along a row and
/// the x-sheet shows down a column.
///
/// 🚨★★★ONE WIDGET, TURNED BY [axis]. 유저 2026-08-24 (F-26): 「x시트가
/// 가로모드랑 **전혀 통일화 안되어있음** … 몇번째인지 모를 통일화 미스가 또
/// 여기서 발견됐네?」, and 2026-08-27: 「x시트 **로직적으로 통일**하는거
/// 절대잊지말고」. The sheet used to carry a private `_LayerHeader` — this
/// widget transposed by hand, cell by cell, which is how it lagged behind on
/// press timing (T10), the name's second selection (F-26), the attach gate
/// (R10 R3), the fill-reference slot (R20-C2), onion and blend (R10 R6), the
/// nesting guides (2026-08-29)… each round found one more cell that had not
/// been turned with the rest. The differences that remain are the ones with a
/// decision behind them, and every one of them says which.
class TimelineLayerControlsRow extends StatelessWidget {
  const TimelineLayerControlsRow({
    super.key,
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
    this.mainExtent,
    required this.layer,
    required this.active,
    this.selected = false,
    required this.metrics,
    required this.onSelectLayer,
    this.onSettledPress,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    required this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    this.onToggleLayerFillReference,
    this.onOpenLayerMixer,
    this.isLayerSoloed = false,
    this.hasLanes = false,
    this.lanesExpanded = false,
    this.onToggleLanes,
    this.depth = 0,
    this.hasGroupFold = false,
    this.groupFoldExpanded = true,
    this.onToggleGroupFold,
    this.attachArrowPlacement,
    this.wearsBaseComposite = false,
    this.fxState = LayerFxState.on,
    this.onToggleLayerFx,
    this.onionSkinEnabled = false,
    this.onToggleLayerOnionSkin,
    this.opacityDragPreview,
    this.isLinked = false,
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.opacityOverride,
    this.chromeless = false,
  });

  /// The strip's MAIN axis: along a rail row (horizontal) or down an x-sheet
  /// column (vertical). Every slot, box and hairline is stated once and
  /// turned by this — `layerRailLeadingCells`/`layerRailTrailingCells` take
  /// it too, so the slot order and extents come from one list on both
  /// surfaces.
  final Axis axis;

  /// The first word of every key this strip mounts (`timeline-layer-row-…`,
  /// `xsheet-layer-fx-…`): the tests locate one surface's controls by it.
  final String keyPrefix;

  /// The strip's extent along [axis]. Null is the rail row's own width from
  /// [metrics]; the x-sheet passes its column's natural height (the stood-up
  /// slot list — always the whole list, the rail window above decides how
  /// much of it shows).
  final double? mainExtent;

  final Layer layer;
  final bool active;

  /// ⑨: this row is in the rail's ROW SELECTION — what the row verbs act on.
  ///
  /// ㊴ (유저 08-12): it wears the accent RING, not the wash. Sharing the wash
  /// with [active] was defensible on paper — both mean "the verbs act here" —
  /// and wrong on screen, where it left nothing to tell the two apart. The
  /// wash answers "where am I standing", the ring answers "what is selected",
  /// and a row can honestly be both.
  final bool selected;

  final TimelineGridMetrics metrics;
  final ValueChanged<LayerId> onSelectLayer;

  /// 🚨T10's second half: the press turned out to be a TAP, so whatever was
  /// selected goes (유저: 「클릭하고 떼면 뭐든 비우게」). The SAME callback
  /// the frame cells take, because 「행이든 뭐든 동일하게」.
  final VoidCallback? onSettledPress;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4): per-move values ride
  /// [onLayerOpacityChanged] as a cheap preview; the release lands here as
  /// the real write. Null keeps the legacy per-move-write behavior.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  final ValueChanged<LayerId> onToggleLayerTimesheet;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// Drawing rows' FILL-reference toggle (R20-C2, the CSP lighthouse);
  /// null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;

  /// SE rows' speaker button, which opens the row's mixer (mute, solo,
  /// fader, pan) anchored under itself; null hides the speaker. It takes
  /// the BUTTON's context so the popup lands on the speaker.
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// Whether this SE row is soloed (AUDIO-PRO R1) — the speaker tints
  /// accent while soloing narrows monitoring to the soloed rows.
  final bool isLayerSoloed;

  /// AE-style property-lane twirl-down: layers with lanes get a chevron
  /// leading the row; rows without lanes keep an empty slot so labels stay
  /// column-aligned.
  final bool hasLanes;
  final bool lanesExpanded;
  final ValueChanged<LayerId>? onToggleLanes;

  /// Folder nesting indent (0 = top level).
  final int depth;

  /// GROUP-FOLD twirl after the name: an attach base folding its attach
  /// rows (UI-R20 #9) or a FOLDER folding its members (R28 #13 put the
  /// folder's fold in exactly this slot — "일단은 통일해서 이름 오른쪽에").
  /// They are one control: a row that holds other rows, folding them.
  /// Null [onToggleGroupFold] hides the twirl entirely. Transposed (R5 #2),
  /// the rail's "right of the name" is the column's "below the name".
  final bool hasGroupFold;
  final bool groupFoldExpanded;
  final ValueChanged<LayerId>? onToggleGroupFold;

  /// Which way this row's attach ARROW points in the sheet column, null on
  /// rows that are not part of an attach group (R10 R3). Precomputed by
  /// the host through [attachArrowPlacement] — a folder's direction is
  /// STACK ORDER against its base, and a row widget holds no stack.
  final AttachedPlacement? attachArrowPlacement;

  /// The AE-style fx switch as a MASTER over the row's per-group switches
  /// (R8: model state, so it survives a reload and reaches every composite
  /// route through the cut itself).
  /// R9: this row wears its BASE's composite (an attach row, or the 공정
  /// organizer folder holding attach rows), so it authors no fx of its own
  /// — see [attachRowWearsBaseComposite]. A LAYER-level fact: the kind
  /// cannot answer it, because a folder is a folder either way.
  final bool wearsBaseComposite;

  final LayerFxState fxState;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// Per-layer onion skin (UI-R17 #5, TVPaint style): whether THIS
  /// layer's ghosts composite, and the row toggle. Null hides the slot's
  /// button (non-drawing rows keep the empty slot for column alignment).
  final bool onionSkinEnabled;
  final ValueChanged<LayerId>? onToggleLayerOnionSkin;

  /// The session's live opacity-drag preview (UI-R6 #2): while the master
  /// bar (or another surface) drags THIS layer's opacity, the row's slider
  /// follows live instead of waiting for the release commit.
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  /// Link badge (L4): this layer's pictures are shared with a link group
  /// ("이름이 같으면 같은 그림") — a small chain icon after the name.
  final bool isLinked;

  /// R27 #6: the blend-mode dropdown lives in the LABEL now (rightmost
  /// slot, past the opacity bar) instead of the timeline toolbar. Null
  /// keeps the slot reserved but inert (passive hosts).
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;

  /// PROGRAM language for the blend-mode name.
  final AppLanguage blendLanguage;

  /// Paint the CONTENTS and no ground: no fill, no active wash, no seams.
  ///
  /// For the collapsed overlay, which lies over the artwork. Everything the
  /// row draws INSIDE stays exactly as it is — that is the whole point, and
  /// it is why this is a flag here rather than a second row somewhere else
  /// re-listing the same twelve slots.
  final bool chromeless;

  /// R27 #9: a live opacity source that OUTRANKS `layer.opacity` for this
  /// row's slider. The camera row's opacity is a view notifier, not model
  /// state — reading it here lets the drag repaint just this slider
  /// instead of rebuilding the whole timeline host per move.
  final ValueListenable<double>? opacityOverride;

  bool get _horizontal => axis == Axis.horizontal;

  double get _mainExtent =>
      mainExtent ??
      metrics.layerControlsWidth - metrics.sectionLabelGutterWidth;

  /// The row's cross extent is the layer row height on both surfaces — a
  /// column is as wide as a row is tall (`xsheet_transposed_metrics_test`).
  double get _width => _horizontal ? _mainExtent : metrics.layerRowHeight;
  double get _height => _horizontal ? metrics.layerRowHeight : _mainExtent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 🚨T10 — the row picks on the PRESS, exactly like a frame cell.
    //
    // 유저 확정 2026-08-14: 「행이든 뭐든 동일하게」. This row used to pick on
    // `InkWell.onTap` — the release — while the cells moved to the press,
    // and two surfaces answering the same gesture differently is the
    // complaint the user has made more than once (「제발 규칙다른거
    // 그만좀하자」). Both wear the same widget-level policy now, device gate
    // included. The sheet's columns read it through the same widget: an
    // `InkWell.onTap` fires on the RELEASE, which was F-26's report.
    //
    // ⛔The InkWell keeps a NO-OP `onTap`, which is not decoration: it holds
    // a tap recognizer in the arena so scroll slop over a row behaves the
    // way it always has. The painted cells do the identical thing for the
    // identical reason.
    final strip = InstantTapRegion(
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      // The PICK. Whether it also CLEARS is the session's call — see
      // `standOnRow`, which holds the selection when the press landed inside
      // it, because that press is most likely the start of a move.
      onTap: (_) => onSelectLayer(layer.id),
      // And when the press turned out to be a tap, the selection goes —
      // 유저: 「클릭하고 떼면 뭐든 비우게」.
      onSettledTap: onSettledPress == null ? null : (_) => onSettledPress!(),
      child: InkWell(
        key: ValueKey<String>(_rowKey),
        onTap: () {},
        // No hover glow on the ROW surface (UI-R24 #6): selection speaks
        // through the background alone; only the buttons may brighten.
        hoverColor: Colors.transparent,
        child: Container(
          width: _width,
          height: _height,
          padding: _padding,
          decoration: _plate(colorScheme),
          child: Semantics(
            key: active ? ValueKey<String>('$keyPrefix-selected-layer') : null,
            label: active ? 'selected layer' : 'layer',
            container: true,
            explicitChildNodes: true,
            // R10 R6 — THE RAIL ROW, STOOD UP. The sheet's column is the
            // shared skeleton in the shared order at the shared extents,
            // running downward: the same list the rail's rows and the
            // legend above read.
            child: Flex(
              direction: axis,
              crossAxisAlignment: _crossAxisAlignment,
              children: [
                ..._leadingCells(),
                ?_depthGuides(colorScheme),
                _nameArea(context, colorScheme),
                ..._trailingCells(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );

    // R10 R3: a folder row used to carry rename + dissolve on a context
    // menu. Rename is the Layer ▾ menu's first entry and a folder is a
    // layer, so it was always a second door to the same dialog; dissolve
    // is waiting on the layer-label drag system, and Delete on a folder
    // row already dissolves it.
    // 🚨T1 — the selection is NOT drawn here any more.
    //
    // ㊴ put a ring around each selected row, and 유저 2026-08-13 read the
    // result back: 「외곽선이 레이어 하나마다 들어오는데, 그게아니라 프레임셀
    // 처럼 연결된 레이어들 선택하면 **한 외곽선, 바탕**이 되도록. 그리고 지금
    // **외곽선이 왼쪽 섹션부분의 선이 없음**」 — two symptoms, one cause. A
    // per-row box seams every boundary inside one selection, and the only box
    // a row can draw is its INNER container, which stops short of the section
    // gutter where the band lives.
    //
    // ★So it moved to where the cells' band already was: an overlay across
    // the rail ([TimelineRowSelectionBands]) — one shape per contiguous run
    // over the LAYER area (A2 2026-08-17 pulled the band back out of the
    // section zone). `selected` stays because the row still reports it to
    // semantics and keys its memo on it. ⛔F-26: the sheet retired its ring
    // per column (「하나하나 실루엣 선택」) for exactly this reason (T1) — the
    // grid lays one band per contiguous run over the header strip instead,
    // through the same widget.
    // 🚨★★★THE WHOLE ROW IS 「레이어 쪽」 (유저 확정 2026-08-30): 「**레이어
    // 쪽 버튼은 탭다운, 헤더쪽은 손떼면**으로 충분할거같은데 맞지?」.
    //
    // ⛔Mounting this on the swipe columns alone was not enough, and the gap
    // was visible on one row: the group-fold twirl is not a swipe column, so
    // it acted on the RELEASE while the eye and the fx beside it acted on the
    // press. The rule the user stated is about the row, so it is stated on
    // the row — and the column-title header (`timeline_layer_controls_
    // header.dart`), which is a different widget, keeps the default. In the
    // x-sheet a layer's own strip is THIS widget stood up: the sheet is the
    // rail transposed, so a layer's toggles sit at the head of its column
    // instead of along its row — and 「헤더쪽은 손떼면」 does NOT mean it.
    return PressFireScope(fireOn: PressFire.down, child: strip);
  }

  /// `timeline-folder-row-…` / `xsheet-layer-row-…`: the kind's word and the
  /// surface's word, one grammar.
  String get _rowKey =>
      '$keyPrefix-${layerKindGroupsLayers(layer.kind) ? 'folder' : 'layer'}'
      '-row-${layer.id}';

  /// The section band hugs the row's LEFT edge (UI-R6 #5); the 8px
  /// breathing room moves between the band and the lane chevron. No padding
  /// on a column: a 28px column has none to give, and the shared slot
  /// skeleton already carries the row's gaps.
  EdgeInsets get _padding =>
      _horizontal ? const EdgeInsets.only(right: 8) : EdgeInsets.zero;

  /// `stretch` down a column: a reserved (childless) slot keeps its extent
  /// either way, but a POPULATED one would take its intrinsic width under
  /// `center` and could out-grow a 28px column. Stretch makes every slot
  /// exactly one column wide, which is what the rail's row gets from its row
  /// height.
  CrossAxisAlignment get _crossAxisAlignment =>
      _horizontal ? CrossAxisAlignment.center : CrossAxisAlignment.stretch;

  /// CHROMELESS drops the ground and keeps the contents — the row over
  /// the artwork when the panel is folded (유저 확정: 바탕 없이 내용만).
  /// A flag on the real row rather than a second row that lists the
  /// same slots: the collapsed overlay then follows this widget by
  /// construction, including whatever column it grows next.
  BoxDecoration? _plate(ColorScheme colorScheme) {
    if (chromeless) return null;
    return _horizontal ? _rowPlate(colorScheme) : _columnPlate(colorScheme);
  }

  /// CONSTANT 1px side/bottom borders (UI-R10 #20). Selection speaks
  /// through the BACKGROUND alone now (UI-R18 #5) — the accent border
  /// doubled the signal for nothing.
  /// ㊴: the wash is the ACTIVE row's alone. `selected` used to share it,
  /// and on screen that made the two states one — the selection now speaks
  /// through the band, the way a selected frame run always has. Shared with
  /// the property lanes' own "you are standing here" wash
  /// ([railSelectedRowColor]) so the two cannot drift apart.
  BoxDecoration _rowPlate(ColorScheme colorScheme) {
    final borderColor = colorScheme.outlineVariant;
    return BoxDecoration(
      color: active ? railSelectedRowColor(colorScheme) : colorScheme.surface,
      border: Border(
        left: BorderSide(
          color: borderColor,
          width: timelineLayerRowLeadingBorder,
        ),
        right: BorderSide(color: borderColor),
        bottom: BorderSide(color: borderColor),
      ),
    );
  }

  /// R5 #17: the SAME wash the rail rows wear, resolved against this
  /// surface's own resting colour so the column stays opaque (the rail lays
  /// its translucent wash over `surface`; the sheet's headers sit on
  /// `surfaceContainerHighest`). One value, one saturation — the sheet used
  /// to paint `secondaryContainer` at full strength and read a shade louder
  /// than the rail for the same state.
  ///
  /// CONSTANT 1px borders, right/top/bottom only (UI-R10 #20): side-by-side
  /// headers kept doubling their shared seam. The left line is the
  /// neighbor's right (the frame rail closes the first column). And constant
  /// in COLOUR too: the accent outline the active column drew was retired
  /// from the timeline rows long ago (UI-R18 #5) and survived here alone.
  BoxDecoration _columnPlate(ColorScheme colorScheme) {
    final ground = colorScheme.surfaceContainerHighest;
    final borderColor = colorScheme.outlineVariant;
    return BoxDecoration(
      color: active
          ? Color.alphaBlend(railSelectedRowColor(colorScheme), ground)
          : ground,
      border: Border(
        right: BorderSide(color: borderColor),
        top: BorderSide(color: borderColor),
        bottom: BorderSide(color: borderColor),
      ),
    );
  }

  // ── boxes turned by the axis ──────────────────────────────────────────

  /// A box tight to its slot: [slot] along the strip, [across] the other
  /// way. The rail's law, read off the onion column rather than invented per
  /// cell — `layerLaneToggleSlotWidth` is 16 and an IconButton left alone
  /// asks for 48. The slot is the PARENT's number, so it travels as an
  /// [AppIconButtonBox] rather than a token.
  AppIconButtonBox _box({
    required double slot,
    required double across,
    required double iconSize,
  }) => AppIconButtonBox(
    width: _horizontal ? slot : across,
    height: _horizontal ? across : slot,
    iconSize: iconSize,
  );

  /// A cell that is [across] the strip and whatever its child is along it —
  /// the tight SizedBox that stops an M3 IconButton inflating to its 48px
  /// minimum tap target and overflowing the row.
  Widget _acrossBox(double across, {required Widget child}) => _horizontal
      ? SizedBox(height: across, child: child)
      : SizedBox(width: across, child: child);

  /// A cell that is [along] the strip.
  Widget _alongBox(double along, {Widget? child}) => _horizontal
      ? SizedBox(width: along, child: child)
      : SizedBox(height: along, child: child);

  // ── the leading run ───────────────────────────────────────────────────

  /// The rail's shared column skeleton (R9 #22): slot order and widths come
  /// from ONE place, so the storyboard's rows, the legend header and the
  /// sheet's columns cannot drift from these again. ⛔`depth` no longer
  /// belongs here: nesting moved into the NAME column so the buttons keep
  /// one x at every depth. The sheet keeps no section slot — its band is
  /// the strip above, not a cell in here.
  List<Widget> _leadingCells() => layerRailLeadingCells(
    axis: axis,
    includeSectionSlot: _horizontal,
    laneToggle: _laneToggle(),
    timesheet: _timesheetCell(),
    mark: _markChip(),
    typeButton: _typeButton(),
  );

  /// I-1: a leading toggle COLUMN owns drags that start on it, exactly as
  /// the trailing three do — the strong claim, kept in step with the grid's
  /// swipe column list (see [RailSwipeColumnPointer]).
  ///
  /// R26 #28 (icon buttons hover ROUND) survives the swap for free — an
  /// IconButton's ink is already a circle, which is the whole reason the
  /// hand-rolled `customBorder: CircleBorder()` could go with it.
  Widget? _laneToggle() {
    if (!hasLanes || onToggleLanes == null) return null;
    return RailSwipeColumnPointer(
      child: AppIconButton(
        keyValue: '$keyPrefix-lane-toggle-${layer.id}',
        tooltip: lanesExpanded ? 'Collapse lanes' : 'Expand lanes',
        size: _box(slot: layerLaneToggleSlotWidth, across: 24, iconSize: 16),
        icon: Icon(layerRailTwirlIcon(expanded: lanesExpanded)),
        onPressed: () => onToggleLanes!(layer.id),
      ),
    );
  }

  /// Timesheet + mark chips lead the label. Attach rows (W5) hide the sheet
  /// toggle — they are display accessories of their base, never sheet
  /// columns — and R10 R3 put their ARROW in the slot the toggle vacates, so
  /// the column reads "sheet, or what this row is attached to". The gate is
  /// the same on both surfaces: the sheet once had no `attachedToLayerId`
  /// check, so an attach column showed a live sheet toggle the rail hides.
  ///
  /// I-1: the column the report named 「타임시트버튼이든 뭐 그런것들」. The
  /// claim goes on at the RAIL, not inside the button.
  Widget? _timesheetCell() {
    final placement = attachArrowPlacement;
    if (placement != null) {
      return LayerAttachArrowCell(
        keyPrefix: keyPrefix,
        idValue: '${layer.id}',
        placement: placement,
      );
    }
    if (!layerKindEligibleForTimesheetToggle(layer.kind) ||
        layer.attachedToLayerId != null) {
      return null;
    }
    return RailSwipeColumnPointer(
      child: LayerTimesheetToggleButton(
        keyPrefix: keyPrefix,
        layerId: layer.id,
        onTimesheet: layer.onTimesheet,
        onToggle: onToggleLayerTimesheet,
      ),
    );
  }

  /// The stood-up header's slot is 14px TALL, so the plate wears no upright
  /// text there (A6) — the chip reads the axis.
  Widget _markChip() => LayerMarkChip(
    keyPrefix: keyPrefix,
    layerId: layer.id,
    mark: layer.mark,
    onMarkSelected: onLayerMarkSelected,
    isVisible: layer.isVisible,
    axis: axis,
  );

  /// The TYPE BUTTON (UI-R24 #7): the kind icon in its OWN fixed slot, a
  /// control separate from the name (function TBD again — R26 #30-1 moved
  /// the blend flyout to the toolbar's PS-style dropdown, user rule 07-22;
  /// tap selects for now). One slot for every row kind, ALWAYS the kind
  /// (R10 R3): the arrow that used to take this slot on attach rows now
  /// rides the sheet column.
  Widget _typeButton() => LayerTypeButton(
    keyPrefix: keyPrefix,
    idValue: '${layer.id}',
    kind: layer.kind,
    folderCollapsed: layer.collapsed,
    onTap: () => onSelectLayer(layer.id),
  );

  // ── nesting and the name ──────────────────────────────────────────────

  /// 🚨★★★NESTING LIVES HERE NOW, AND ONLY HERE — THE SAME ON BOTH SURFACES.
  ///
  /// 유저 2026-08-29: the leading run used to spend a 16px cell per level
  /// plus a ↳ cell, which pushed every button right and 「계속밀려서 제대로
  /// 안보이게」 되었다. The buttons keep one x at every depth now; the NAME is
  /// what gives ground, and a clipped name still reads while a clipped button
  /// cannot be pressed. Transposed (유저 2026-08-27: 「x시트 로직적으로 통일하는거
  /// 절대잊지말고」): depth used to be cells in the sheet's LEADING run, which
  /// ran down the very length the name is written in — a two-level cap or
  /// the name clipped to nothing. The guides say the depth — one hairline per
  /// level, drawn inside the name's own box.
  Widget? _depthGuides(ColorScheme colorScheme) {
    if (depth == 0) return null;
    return _alongBox(
      layerRailNameIndent(depth),
      child: Flex(
        direction: axis,
        children: [
          for (var level = 0; level < depth; level += 1)
            _alongBox(
              layerRailGuideWidth,
              child: Center(child: _guideHairline(colorScheme)),
            ),
        ],
      ),
    );
  }

  Widget _guideHairline(ColorScheme colorScheme) => SizedBox(
    width: _horizontal ? 1 : double.infinity,
    height: _horizontal ? double.infinity : 1,
    child: ColoredBox(color: colorScheme.outlineVariant),
  );

  /// 🚨F-26 (유저 2026-08-24): 「레이어 클릭하고 이름영역 클릭시 **선택되는
  /// 애니메이션같은거 발동**하는데, 없애고 해당영역 클릭시 레이어라벨 빈공간
  /// 클릭이랑 마찬가지로 레이어 자체가 밝아지는 애니메이션 적용되도록.
  /// **규칙단순화**」.
  ///
  /// ⛔The name used to be an InkWell of its own, selecting the layer a
  /// SECOND time on top of the row's press-seek. Two consequences, both the
  /// report: it rippled where the rest of the row does not, and it picked on
  /// the RELEASE where the row picks on the DOWN (T10) — so the same click
  /// meant two different moments depending on which pixel it landed on.
  /// ★The row's own [InstantTapRegion] already covers every pixel of this
  /// area. Taking the InkWell away is not removing a behaviour; it is
  /// removing a SECOND one.
  ///
  /// 🚨F-29 (유저 2026-08-24): 「접기 펼치기 아이콘 위치 조정. 지금 레이어이름
  /// 옆에 붙어있는데, 그게아니라 위치는 항상 고정으로 두고싶기때문에 레이어
  /// 이름영역의 오른쪽정렬로 고정」. ⛔The twirl used to be the last child of
  /// a MIN-width Row inside a left Align, so it sat wherever the name ended
  /// — a different x on every row, and a moving x on a rename. The NAME
  /// takes the space now and the twirl trails it at the region's far edge,
  /// which is the one place it can be that does not depend on what the row
  /// is called. The SLOT is always there: a row that folds nothing reserves
  /// the extent rather than letting the name run into it, so the icons on
  /// the rows that do fold all sit on one line (one axis over: a column that
  /// folds nothing used to drop it, which pulled every cell below up by
  /// 20px).
  Widget _nameArea(BuildContext context, ColorScheme colorScheme) => Expanded(
    child: KeyedSubtree(
      key: ValueKey<String>('$keyPrefix-layer-name-${layer.id}'),
      child: Flex(
        direction: axis,
        children: [
          Expanded(
            child: Flex(
              direction: axis,
              children: [
                Flexible(child: _nameText(context)),
                ?_linkBadge(colorScheme),
              ],
            ),
          ),
          _alongBox(layerLaneToggleSlotWidth, child: _foldTwirl()),
        ],
      ),
    ),
  );

  /// Selection reads by COLOR only (user rule): no bold flip, so the text
  /// never reflows on select — one style on both surfaces
  /// ([layerRowNameStyle], F-26 #1226). Down a column the name is a name you
  /// READ, so the letters stand up and the column begins at the top — the
  /// rail's left-aligned name, transposed (user, 2026-08-08). It used to lie
  /// down AND float in the middle of its own column.
  Widget _nameText(BuildContext context) => _horizontal
      ? Text(
          layer.name,
          style: layerRowNameStyle(context),
          overflow: TextOverflow.ellipsis,
        )
      : ClipRect(
          child: VerticalWritingText(
            text: layer.name,
            latinForm: VerticalLatinForm.upright,
            mainAlignment: 0,
            style: layerRowNameStyle(context),
          ),
        );

  Widget? _linkBadge(ColorScheme colorScheme) {
    if (!isLinked) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: AppText.strings.tlLinkedLayerTooltip,
        child: Icon(
          Icons.link,
          key: ValueKey<String>('$keyPrefix-layer-link-badge-${layer.id}'),
          size: 14,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  /// The attach-group twirl (UI-R20 #9), shown only when the group exists —
  /// same chevron pair as the lane twirl, the rail's ONE twirl glyph (this
  /// arm used to spell the pair out by hand while the x-sheet read the
  /// helper). Same key grammar on both surfaces so a folder and an attach
  /// base read alike anywhere.
  Widget? _foldTwirl() {
    if (!hasGroupFold || onToggleGroupFold == null) return null;
    final kind = layerKindGroupsLayers(layer.kind) ? 'folder' : 'attach';
    return ControlPressClaim(
      onPressed: () => onToggleGroupFold!(layer.id),
      child: InkWell(
        key: ValueKey<String>('$keyPrefix-$kind-twirl-${layer.id}'),
        onTap: silentPress(() => onToggleGroupFold!(layer.id)),
        // R26 #28
        customBorder: const CircleBorder(),
        child: _alongBox(
          layerLaneToggleSlotWidth,
          child: _acrossBox(
            24,
            child: Icon(
              layerRailTwirlIcon(expanded: groupFoldExpanded),
              size: 16,
            ),
          ),
        ),
      ),
    );
  }

  // ── the trailing run ──────────────────────────────────────────────────

  List<Widget> _trailingCells(ColorScheme colorScheme) =>
      layerRailTrailingCells(
        axis: axis,
        fillReference: _fillReferenceToggle(colorScheme),
        fx: _fxSwitch(),
        hasOnionColumn: onToggleLayerOnionSkin != null,
        onion: _onionToggle(colorScheme),
        visibility: _visibilityToggle(),
        mute: _muteButton(),
        opacity: _opacitySlot(),
        hasBlendColumn: onLayerBlendModeSelected != null,
        blend: _blendChip(),
      );

  /// Fill-reference toggle (R20-C2): drawing rows only — every OTHER kind
  /// reserves the slot so the legend header's column icons line up over one
  /// Excel-style grid (R-toolbar round).
  Widget? _fillReferenceToggle(ColorScheme colorScheme) {
    final onToggle = onToggleLayerFillReference;
    if (onToggle == null || layer.kind != LayerKind.animation) return null;
    return _acrossBox(
      26,
      child: AppIconButton(
        keyValue: '$keyPrefix-layer-fill-reference-${layer.id}',
        tooltip: layer.isFillReference
            ? 'Fill reference layer (on)'
            : 'Fill reference layer',
        size: _box(slot: layerFillReferenceSlotWidth, across: 26, iconSize: 16),
        icon: Icon(
          Icons.format_color_fill,
          color: layer.isFillReference
              ? colorScheme.primary
              : colorScheme.outline.withValues(alpha: 0.45),
        ),
        onPressed: () => onToggle(layer.id),
      ),
    );
  }

  /// Attach rows and their 공정 organizer folder hide the fx switch — the
  /// BASE's switch governs what they show, in BOTH orientations: a flip here
  /// would burn an undo step writing a flag nothing reads.
  ///
  /// I-1: the three toggle COLUMNS own drags that start on them, so a
  /// press-and-drag paints the column down the rows instead of moving the
  /// row. Kept in step with the grid's swipe column list — see
  /// [RailSwipeColumnPointer].
  Widget? _fxSwitch() {
    final onToggle = onToggleLayerFx;
    if (onToggle == null ||
        !layerKindShowsFxToggle(layer.kind) ||
        wearsBaseComposite) {
      return null;
    }
    return RailSwipeColumnPointer(
      child: FxToggleButton(
        keyValue: '$keyPrefix-layer-fx-${layer.id}',
        state: fxState,
        onToggle: () => onToggle(layer.id),
      ),
    );
  }

  /// Per-layer onion toggle (UI-R17 #5) beside the eye — only brush-holding
  /// rows get the button; rows keep the slot so the control columns stay
  /// aligned; hosts without the callback (no header cell either) skip the
  /// column whole. The sheet went without it until R10 R6's "싹다 넣어".
  Widget? _onionToggle(ColorScheme colorScheme) {
    final onToggle = onToggleLayerOnionSkin;
    if (onToggle == null || !layerKindAcceptsBrushInput(layer.kind)) {
      return null;
    }
    return _acrossBox(
      26,
      child: RailSwipeColumnPointer(
        child: AppIconButton(
          keyValue: '$keyPrefix-layer-onion-${layer.id}',
          tooltip: onionSkinEnabled ? 'Onion skin (on)' : 'Onion skin',
          size: _box(slot: layerOnionSlotWidth, across: 26, iconSize: 15),
          icon: Icon(
            Icons.filter_none,
            color: onionSkinEnabled
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.45),
          ),
          onPressed: () => onToggle(layer.id),
        ),
      ),
    );
  }

  Widget _visibilityToggle() => RailSwipeColumnPointer(
    child: LayerVisibilityToggleButton(
      keyValue: '$keyPrefix-layer-visibility-${layer.id}',
      isVisible: layer.isVisible,
      onToggle: () => onToggleLayerVisibility(layer.id),
    ),
  );

  /// SE rows carry the mute speaker beside the eye (sounds silence,
  /// waveforms keep displaying) — the mixer's door. Tight box: the M3
  /// IconButton otherwise inflates its layout box to the 48px minimum tap
  /// target, overflowing the rail row.
  Widget? _muteButton() {
    final onOpenMixer = onOpenLayerMixer;
    if (layer.kind != LayerKind.se || onOpenMixer == null) return null;
    return _acrossBox(
      26,
      child: LayerMuteToggleButton(
        keyValue: '$keyPrefix-layer-mute-${layer.id}',
        muted: layer.muted,
        soloed: isLayerSoloed,
        width: _horizontal ? layerMuteSlotWidth : 26,
        height: _horizontal ? 26 : layerMuteSlotWidth,
        onOpenMixer: (anchorContext) => onOpenMixer(anchorContext, layer.id),
      ),
    );
  }

  /// The camera row's slider drives the camera-view DIM opacity (unified
  /// layer controls); every row shrinks alike so the control columns stay
  /// aligned. Down a column the fader is centred in its slot, because the
  /// column's `stretch` would otherwise widen it to the column.
  Widget? _opacitySlot() {
    if (!layerKindShowsOpacityControl(layer.kind)) return null;
    final field = _opacityField();
    return _horizontal ? field : Center(child: field);
  }

  /// R27 #6: the blend mode, RIGHTMOST — the user's placement. Within a
  /// host that HAS the column, non-compositing kinds keep the slot so rows
  /// and the legend header stay aligned; hosts without it (the storyboard's
  /// track rail) skip the column outright, exactly like the onion cell.
  Widget? _blendChip() {
    final onSelected = onLayerBlendModeSelected;
    if (onSelected == null || !layerKindShowsBlendControl(layer.kind)) {
      return null;
    }
    final isGroup = layerKindGroupsLayers(layer.kind);
    return LayerBlendModeChip(
      axis: axis,
      keyValue: '$keyPrefix-layer-blend-${layer.id}',
      optionKeyPrefix: '$keyPrefix-layer-blend-option-',
      blendMode: layer.blendMode,
      language: blendLanguage,
      isGroup: isGroup,
      subject: isGroup ? 'Folder' : 'Layer',
      onBlendModeSelected: (mode) => onSelected(layer.id, mode),
    );
  }

  /// The row's opacity slider, live-following the session's drag preview
  /// when it targets this layer (the master bar sweep, UI-R6 #2). Stood up
  /// like every other control in a column: the fader fills upward and its
  /// readout writes downward (`RotatedBox` was not an option — see
  /// [FieldSlider.axis]).
  Widget _opacityField() {
    Widget slider(double value) => FieldSlider.opacity(
      key: ValueKey<String>('$keyPrefix-layer-opacity-${layer.id}'),
      axis: axis,
      value: value,
      valueText: sliderValueText(value * 100, unit: '%'),
      height: 18,
      onChanged: (opacity) => onLayerOpacityChanged(layer.id, opacity),
      onChangeEnd: onLayerOpacityChangeEnd == null
          ? null
          : (opacity) => onLayerOpacityChangeEnd!(layer.id, opacity),
    );

    // R27 #9: a row whose opacity IS a view notifier (the camera row)
    // reads it here — the slider follows the drag by itself, no host
    // rebuild in the loop.
    final override = opacityOverride;
    if (override != null) {
      return ValueListenableBuilder<double>(
        valueListenable: override,
        builder: (context, value, _) => slider(value.clamp(0.0, 1.0)),
      );
    }

    final preview = opacityDragPreview;
    final resting = layer.opacity.clamp(0.0, 1.0).toDouble();
    if (preview == null) {
      return slider(resting);
    }
    return ValueListenableBuilder<({Set<LayerId> layerIds, double opacity})?>(
      valueListenable: preview,
      builder: (context, dragging, _) => slider(
        dragging != null && dragging.layerIds.contains(layer.id)
            ? dragging.opacity
            : resting,
      ),
    );
  }
}

/// One fold twirl, answered ONCE (UI-R20 #9): a folder folds its members, an
/// attach base folds its attach rows — the base-row twirl shows only when the
/// layer carries attach rows.
///
/// Three answers — is there a twirl, is it open, what does it toggle — and
/// both grids' headers derived all three inline, each with its own
/// `row.isFolder ? … : …`, until the x-sheet's copy was found with the
/// comment "the rail's rule verbatim" on it. Verbatim is a copy; this is the
/// rule. `one_fold_twirl_test` keeps it the only one.
typedef TimelineGroupFold = ({
  bool has,
  bool expanded,
  ValueChanged<LayerId>? onToggle,
});

TimelineGroupFold timelineGroupFoldFor({
  required TimelineDisplayRow row,
  required List<Layer> layers,
  required Set<LayerId> collapsedAttachBaseIds,
  required ValueChanged<LayerId>? onToggleLayerCollapsed,
  required ValueChanged<LayerId>? onToggleAttachGroup,
}) {
  if (row.isFolder) {
    return (
      has: true,
      expanded: !row.layer.collapsed,
      onToggle: onToggleLayerCollapsed,
    );
  }
  return (
    has: attachedLayersOf(row.layer.id, layers).isNotEmpty,
    expanded: !collapsedAttachBaseIds.contains(row.layer.id),
    onToggle: onToggleAttachGroup,
  );
}
