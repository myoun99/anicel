import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../input/arena_tap_hold.dart';
import '../input/control_press_claim.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/clip_button.dart';
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_id.dart';
import '../../models/app_input_settings.dart' show AppInput;
import '../widgets/field_slider.dart';
import '../widgets/instant_tap_region.dart';
import '../widgets/named.dart';
import 'lane_graph.dart' show LaneGraphVerbs;
import 'lane_graph_seats.dart' show laneGraphHeadedBy;
import 'lane_graph_toggle.dart';
import 'layer_label_controls.dart';
import 'layer_opacity_field.dart';
import 'axis_turn.dart';
import 'berth_row.dart';
import 'layer_rail_columns.dart';
import 'rail_eyes.dart';
import '../widgets/rail_glyph_button.dart';
import '../widgets/row_plate.dart';
import 'timeline_double_tap.dart'
    show TimelineLabelDoubleClick, timelineLabelDoubleTapDetector;
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

/// What the controls row SHOWS of a [Layer] — the rail row memo's token
/// field for the layer, comparing equal exactly when the row would look
/// the same.
///
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
/// 🚨I-57 ㉣ (10-13): and NOT the id. A cut switch puts the next cut's
/// layer in each berth ([RowBerths]), and a row of the same face is the same
/// row on screen — measured on the user's project, rebuilding the rail's
/// rows was 544 of a crossing's widget rebuilds. The row asks WHICH layer it
/// stands for at the moment it acts ([BerthRow]). Of the attach it renders
/// only that there is one (the arrow and the sheet toggle's gate), so the
/// layer it is attached to — another id — is not compared either.
///
/// Deliberately absent (the row renders none of them): `frames`, `timeline`,
/// `instructions`, `audioClips`, `baseFrameLinks`,
/// `transformTrack` (the LANE rows read it, and those are unmemoized),
/// `seSound` (its 「오디오」 lanes read it), `attachedMode` and `folderId`.
///
/// 🚨And `isVisible`, which the row DOES show — through [RailEyes], not
/// through this token. an-eye-rebuilds-its-whole-row (measured 2026-09-23):
/// a solo flips most rows' eyes in one frame, and with the eye in here every
/// one of those rows rebuilt all twelve slots — 3,051 elements, 55 ms of UI
/// thread on the user's machine (I-19, 「솔로 버벅임」). The eye and the plate
/// that dims with it read [RailEyes] themselves, so a flip rebuilds those
/// two and nothing else.
final class ControlsRowFace {
  const ControlsRowFace(this.layer);

  final Layer layer;

  @override
  bool operator ==(Object other) {
    if (other is! ControlsRowFace) {
      return false;
    }
    final a = layer;
    final b = other.layer;
    return identical(a, b) ||
        (a.name == b.name &&
            a.kind == b.kind &&
            a.opacity == b.opacity &&
            a.muted == b.muted &&
            a.mark == b.mark &&
            a.onTimesheet == b.onTimesheet &&
            a.blendMode == b.blendMode &&
            a.collapsed == b.collapsed &&
            a.clipsToBelow == b.clipsToBelow &&
            isAttachedLayer(a) == isAttachedLayer(b) &&
            a.attachedPlacement == b.attachedPlacement &&
            _isReference(a) == _isReference(b));
  }

  /// Whether the row stands on a file — what its reference button is
  /// there for. Only THAT is shown; which file and from where is the
  /// popover's to read. F-308 (유저 2026-10-06): 「래스터라이즈누르고 레이어
  /// 이동등 갱신되는행동해야 버튼사라짐」 — left out, a rasterize (and its undo)
  /// changed nothing this compared, and the button stayed as it was.
  static bool _isReference(Layer layer) => layer.mediaReference != null;

  @override
  int get hashCode => Object.hash(
    layer.name,
    layer.kind,
    layer.opacity,
    layer.muted,
    layer.mark,
    layer.onTimesheet,
    layer.blendMode,
    layer.collapsed,
    layer.clipsToBelow,
    isAttachedLayer(layer),
    layer.attachedPlacement,
    _isReference(layer),
  );
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
/// (R10 R3), the clip slot (R20-C2, I-92), onion and blend (R10 R6), the
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
    this.labelDoubleClick,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    this.onToggleLayerClip,
    this.onOpenLayerMixer,
    this.onOpenLayerReference,
    this.onOpenLayerLinks,
    this.onOpenCameraPath,
    this.isReferenceSourceShort = false,
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
    this.linkPartners = const [],
    this.onLayerBlendModeSelected,
    this.chromeless = false,
    this.laneGraphVerbs,
    this.headsGraph = false,
    this.graphOpen = false,
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

  /// A double click on this strip — the LABEL — asked at its first press
  /// (I-48; see [TimelineLabelDoubleClick]). Null mounts none.
  final TimelineLabelDoubleClick? labelDoubleClick;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4): per-move values ride
  /// [onLayerOpacityChanged] as a cheap preview; the release lands here as
  /// the real write. Null keeps the legacy per-move-write behavior.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  /// The sheet toggle's verb. Null mounts none and keeps its slot — the
  /// storyboard's conte rows, whose head is ONE for every cut while the
  /// sheet flag is each cut's own (I-73); an attach row's arrow stands in
  /// that slot either way.
  final ValueChanged<LayerId>? onToggleLayerTimesheet;
  final void Function(LayerId layerId, LayerMarkEdit edit) onLayerMarkSelected;

  /// The clip toggle (I-92) of every row that can clip; null hides it.
  final ValueChanged<LayerId>? onToggleLayerClip;

  /// SE rows' speaker button, which opens the row's mixer (mute, solo, the
  /// total volume) anchored under itself; null hides the speaker. It takes
  /// the BUTTON's context so the popup lands on the speaker.
  final void Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerMixer;

  /// A REFERENCE row's file button, which opens the row's reference popover
  /// anchored under itself; null hides it. It takes the BUTTON's context so
  /// the popover lands on the button, which stays lit until the future
  /// completes.
  ///
  /// 🚨THE SLOT EXISTS ONLY ON A REFERENCE ROW — the user's own exception to
  /// 「없다가 생기는 UI 금지」 (2026-09-11: 「참조인게 특수한 상황인거니까
  /// 없다가 생기는 ui 허용. 굽혀진 레이어, 참조가 아닌 레이어는 자리 없애고,
  /// 참조인 레이어만 자리 만들어서 버튼두도록」). ⛔Do not "fix" it into a
  /// reserved slot.
  final Future<void> Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerReference;

  /// The link badge's window (I-25): what the row is linked to, and the
  /// button that unlinks it. Null leaves the badge a picture.
  final Future<void> Function(BuildContext anchorContext, LayerId layerId)?
  onOpenLayerLinks;

  /// The camera row's path button ([_cameraPathButton], I-89 ④): how the
  /// canvas shows the camera's path, opened under the button. Null mounts
  /// none.
  final Future<void> Function(BuildContext anchorContext)? onOpenCameraPath;

  /// Whether this row asks its file for more film than the file has — the
  /// button turns red, and its popover says by how much.
  final bool isReferenceSourceShort;

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

  /// Link badge (L4): the rows this layer shares its pictures with — its
  /// link group's other members, each as a row reads ([linkPartnerLines]) —
  /// shown as a small chain icon after the name whose tooltip names them.
  /// Empty: not linked, no badge.
  ///
  /// 🗣️유저 2026-09-25: 「링크버튼통해서 어디랑 링크되고있는지만 제대로
  /// 표시하게」. ↩️It was a bool, and the tooltip a fixed sentence.
  final List<String> linkPartners;

  /// R27 #6: the blend-mode dropdown lives in the LABEL now (rightmost
  /// slot, past the opacity bar) instead of the timeline toolbar. Null
  /// keeps the slot reserved but inert (passive hosts).
  final void Function(LayerId layerId, LayerBlendMode mode)?
  onLayerBlendModeSelected;

  /// Paint the CONTENTS and no ground: no fill, no active wash, no seams.
  ///
  /// For the collapsed overlay, which lies over the artwork. Everything the
  /// row draws INSIDE stays exactly as it is — that is the whole point, and
  /// it is why this is a flag here rather than a second row somewhere else
  /// re-listing the same twelve slots.
  final bool chromeless;

  /// The header graphs' verbs (I-89 ③) — the HOST's, the same on every
  /// row: null mounts no graph button.
  final LaneGraphVerbs? laneGraphVerbs;

  /// Whether this row heads a header graph — the camera row, the row being
  /// its own Transform group (㉙) — and whether it stands open. A row that
  /// heads none leaves the button's room to the name.
  final bool headsGraph;
  final bool graphOpen;

  bool get _horizontal => axis == Axis.horizontal;

  double get _mainExtent =>
      mainExtent ??
      metrics.layerControlsWidth - metrics.sectionLabelGutterWidth;

  /// The row's cross extent is the layer row height on both surfaces — a
  /// column is as wide as a row is tall (`xsheet_transposed_metrics_test`).
  Size get _size =>
      sizeAlong(axis, along: _mainExtent, across: metrics.layerRowHeight);

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
    final doubleClick = labelDoubleClick;
    final surface = _surface(context, colorScheme);
    final strip = InstantTapRegion(
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      // The PICK. Whether it also CLEARS is the session's call — see
      // `standOnRow`, which holds the selection when the press landed inside
      // it, because that press is most likely the start of a move.
      onTap: (_) => onSelectLayer(layerIdNow(context, layer.id)),
      // And when the press turned out to be a tap, the selection goes —
      // 유저: 「클릭하고 떼면 뭐든 비우게」.
      onSettledTap: onSettledPress == null ? null : (_) => onSettledPress!(),
      // I-48: the label's double click, INSIDE the pick — the deeper
      // listener hears a press first, so its record reads the selection
      // before the pick can change it.
      child: doubleClick == null
          ? surface
          : timelineLabelDoubleTapDetector(
              layerId: () => layerIdNow(context, layer.id),
              doubleClick: doubleClick,
              child: surface,
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

  /// The strip itself — its plate and its twelve slots.
  ///
  /// ⛔Its tap is held in the arena and answers nothing, which is not
  /// decoration: scroll slop over a row behaves the way it always has
  /// ([ArenaTapHold]). The painted cells do the identical thing for the
  /// identical reason. No hover glow on the ROW surface (UI-R24 #6):
  /// selection speaks through the background alone; only the buttons may
  /// brighten.
  ///
  /// 🚨NAMES, NOT KEYS (I-57, 10-13): the row's handles are names
  /// ([NamesItself] — the tap hold and the plate wear theirs). A
  /// key spelled from the layer made a cut switch remount the row, and the
  /// selected row's key — there while the row was active, gone when it was
  /// not — remade the row's whole content whenever the selection moved.
  Widget _surface(BuildContext context, ColorScheme colorScheme) =>
      ArenaTapHold(
        name: _rowName,
        child: RowPlate(
          name: active ? '$keyPrefix-selected-layer' : null,
          width: _size.width,
          height: _size.height,
          padding: _padding,
          decoration: _plate(colorScheme),
          // The program language's word, as the conte's own rows say it.
          label: active
              ? AppText.strings.semSelectedLayer
              : AppText.strings.semLayer,
          // R10 R6 — THE RAIL ROW, STOOD UP. The sheet's column is the
          // shared skeleton in the shared order at the shared extents,
          // running downward: the same list the rail's rows and the legend
          // above read.
          child: Flex(
            direction: axis,
            crossAxisAlignment: _crossAxisAlignment,
            children: [
              ..._leadingCells(context),
              ?_depthGuides(colorScheme),
              _nameArea(context, colorScheme),
              ..._trailingCells(context, colorScheme),
            ],
          ),
        ),
      );

  /// `timeline-folder-row-…` / `xsheet-layer-row-…`: the kind's word and the
  /// surface's word, one grammar.
  String get _rowName =>
      '$keyPrefix-${layer.kind.groupsLayers ? 'folder' : 'layer'}'
      '-row-${layer.id}';

  /// The section band hugs the row's LEFT edge (UI-R6 #5); the 8px
  /// breathing room moves between the band and the lane chevron, and the
  /// row's end keeps the rail's ([layerRailEndPadding]). No padding on a
  /// column: a 28px column has none to give, and the shared slot skeleton
  /// already carries the row's gaps.
  EdgeInsets get _padding => _horizontal
      ? const EdgeInsets.only(right: layerRailEndPadding)
      : EdgeInsets.zero;

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

  // ── the leading run ───────────────────────────────────────────────────

  /// The rail's shared column skeleton (R9 #22): slot order and widths come
  /// from ONE place, so the storyboard's rows, the legend header and the
  /// sheet's columns cannot drift from these again. ⛔`depth` no longer
  /// belongs here: nesting moved into the NAME column so the buttons keep
  /// one x at every depth. The sheet keeps no section slot — its band is
  /// the strip above, not a cell in here.
  List<Widget> _leadingCells(BuildContext context) => layerRailLeadingCells(
    axis: axis,
    includeSectionSlot: _horizontal,
    laneToggle: _laneToggle(context),
    timesheet: layerRailTimesheetCell(
      keyPrefix: keyPrefix,
      layer: layer,
      onToggle: onToggleLayerTimesheet,
      attachArrowPlacement: attachArrowPlacement,
    ),
    mark: _markChip(),
    typeButton: _typeButton(context),
  );

  /// I-1: a leading toggle COLUMN owns drags that start on it, exactly as
  /// the trailing three do — the strong claim, kept in step with the grid's
  /// swipe column list (see [RailSwipeColumnPointer]).
  Widget? _laneToggle(BuildContext context) {
    final onToggle = onToggleLanes;
    if (!hasLanes || onToggle == null) return null;
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.laneToggle,
      child: LayerFoldTwirl(
        name: '$keyPrefix-lane-toggle-${layer.id}',
        axis: axis,
        expanded: lanesExpanded,
        tooltip: layerLaneTwirlTooltip(expanded: lanesExpanded),
        onToggle: () => onToggle(layerIdNow(context, layer.id)),
      ),
    );
  }

  /// The stood-up header's slot is 14px TALL, so the plate wears no upright
  /// text there (A6) — the chip reads the axis.
  ///
  /// Its plate dims with the eye (F-56), so it reads the eye the way the eye
  /// does — [_visibilityToggle] — a folder above that hides the row included
  /// (F-185: 「색라벨도 동일하게 비활성화색」).
  Widget _markChip() => RailEyeBuilder(
    layer: layer,
    builder: (context, eye) => LayerMarkChip.forLayer(
      layer,
      keyPrefix: keyPrefix,
      onMarkSelected: onLayerMarkSelected,
      axis: axis,
      isVisible: eye.shown,
    ),
  );

  /// The TYPE BUTTON (UI-R24 #7): the kind icon in its OWN fixed slot, a
  /// control separate from the name (function TBD again — R26 #30-1 moved
  /// the blend flyout to the toolbar's PS-style dropdown, user rule 07-22;
  /// tap selects for now). One slot for every row kind, ALWAYS the kind
  /// (R10 R3): the arrow that used to take this slot on attach rows now
  /// rides the sheet column.
  Widget _typeButton(BuildContext context) => LayerTypeButton(
    keyPrefix: keyPrefix,
    idValue: '${layer.id}',
    kind: layer.kind,
    folderCollapsed: layer.collapsed,
    onTap: () => onSelectLayer(layerIdNow(context, layer.id)),
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
  Widget? _depthGuides(ColorScheme colorScheme) =>
      layerRailDepthGuides(axis, depth, colorScheme: colorScheme);

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
  /// is called.
  ///
  /// I-89 Q1 (유저 2026-10-12): a row's own buttons take their room out of
  /// the name, right-aligned — 「추가로 공간 만드는게아니라 이름공간을 줄여서
  /// 오른쪽정렬로」 — the link among them, beside the reference when a row
  /// has both (「참조/링크가 동시에 될수있는거 말되니까 그런식으로 중복되는
  /// 상황은 중복되도록」). The order was left to me (「버튼별 순서는 알아서
  /// 맡김」): the graph last, so it ends the name as a header's does.
  /// ↩️The link trailed the name's letters, wherever a name happened to end.
  ///
  /// 🗣️F-454 (유저 2026-10-23): 「어태치 접기/펼치기버튼도 사실상 있는것만
  /// 있는 버튼이면서 레전드에도 존재하지않는 버튼이기때문에, 어태치
  /// 접기/펼치기 버튼도 포함해서 위치정하도록. 즉 어태치있으면 접기버튼이
  /// 지금처럼 가장 오른쪽에 오고, 참조버튼 그 왼쪽에 오고. 카메라 레이어는
  /// … 그 자리에 그래프버튼,그왼쪽에 경로버튼」 — the twirl is the last of
  /// the row's own buttons, there only on a row that folds. ↩️Its slot was
  /// reserved on every row (F-29), so a row's own buttons stood a twirl
  /// short of the name's end on the rows that fold nothing.
  Widget _nameArea(BuildContext context, ColorScheme colorScheme) => Expanded(
    child: Named(
      '$keyPrefix-layer-name-${layer.id}',
      child: Flex(
        direction: axis,
        children: [
          // The letters as long as they are: the ground past them is the
          // name's too, a double click there the label's. ↩️A Flex of one
          // Flexible stood here, which lays its one child exactly as this
          // does — an element more on every row, on every panel reopen
          // (card frame-panels-build-in-one-frame, 2026-10-25).
          Expanded(
            child: Align(
              alignment: centerStartAlong(axis),
              child: _nameText(context),
            ),
          ),
          ?_linkBadge(colorScheme),
          ?_referenceButton(),
          ?_soundButton(colorScheme),
          ?_cameraPathButton(),
          ?_graphToggle(context),
          ?_foldTwirl(context),
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
  ///
  /// It dims with the eye, as the colour label beside it does (I-62) — so it
  /// reads the eye the way that label does ([_markChip]), and a flip
  /// rebuilds the name and not the row.
  Widget _nameText(BuildContext context) => RailEyeBuilder(
    layer: layer,
    builder: (context, eye) => readableText(
      axis,
      layer.name,
      style: layerRowNameStyleFor(layerRowNameStyle(context), shown: eye.shown),
    ),
  );

  /// The box every button at the end of the name stands in — the link
  /// badge, a reference row's file, an SE row's speaker, the camera's path
  /// — the header graph's ([LaneGraphToggle]), so the five are one button.
  ///
  /// 🚨F-409 (유저 2026-10-19): 「카메라랑 참조레이어의 참조버튼. 얘네만 다른
  /// 버튼 사용하는거 눈에띄는게 얘네만 누르면 버튼 실루엣이 강조색됨.
  /// 같은버튼 공용화된거 쓰도록」. ↩️The reference and the path wore the box's
  /// edge in an 18px box and lit while their window was open (the 09-11
  /// mockup: beside the name a button had to read as a button, not as a
  /// badge), and the badge stood in an 18px box of its own.
  AppIconButtonBox get _nameButtonBox => railSlotBox(
    axis,
    slot: layerGraphSlotWidth,
    across: 26,
    iconSize: 15,
  );

  /// One of the buttons at the end of the name, `layer-[slug]` in
  /// [_nameButtonBox] in its [look] — pressed under its own context, so a
  /// popover it opens lands on it.
  Widget _nameButton({
    required String slug,
    required String tooltip,
    required _NameButtonLook look,
    required void Function(BuildContext context)? onPressed,
  }) => Builder(
    builder: (context) => RailGlyphButton(
      name: '$keyPrefix-layer-$slug-${layer.id}',
      tooltip: tooltip,
      size: _nameButtonBox,
      glyph: look.glyph,
      danger: look.danger,
      onPressed: onPressed == null ? null : () => onPressed(context),
    ),
  );

  /// 🗣️I-25 (유저 2026-09-14): 「레이어도 똑같이 버튼누르면 링크 대상 리스트
  /// 표시」 — the badge is the entrance to the link window, a rail button
  /// like the reference button beside it.
  Widget? _linkBadge(ColorScheme colorScheme) {
    if (linkPartners.isEmpty) return null;
    final onOpen = onOpenLayerLinks;
    return _nameButton(
      slug: 'link-badge',
      tooltip: [AppText.strings.tlLinkedWith, ...linkPartners].join('\n'),
      // The link reads in the accent whatever the button's own rest
      // colour: it says the row is linked before anything is pressed.
      look: _NameButtonLook(
        RailIconGlyph(Icons.link, color: colorScheme.primary),
      ),
      onPressed: onOpen == null
          ? null
          : (context) => onOpen(context, layerIdNow(context, layer.id)),
    );
  }

  /// The reference button (유저 2026-09-11) at the name area's far end,
  /// right before the fold where the row folds (「레이어 이름 영역의
  /// 오른쪽정렬. 최종적으로 폴더 접기 펼치기가 오른쪽정렬로 마지막에 있을텐데,
  /// 그거 왼쪽」; F-454) — so it stands at one x on every reference row,
  /// whatever the row is called.
  ///
  /// The FILE glyph, icon only (미디어 배치 라운드 3~5 — 「아이콘만(이름은
  /// 툴팁)」), and the press opens the row's reference popover instead of
  /// baking at once. Not the chain: the chain already means "linked layer"
  /// on this same label.
  ///
  /// A row that asks its file for more film than the file has wears
  /// [AppColors.danger] (유저 2026-09-12: 「참조버튼을 빨갛게 만들고, 그걸
  /// 누르면 팝오버 항목중 하나로 내용 띄우도록 하자」). ⛔The BUTTON says it,
  /// not a new badge beside it: the slot is already there on every reference
  /// row, and red on a control the user can press is what makes the popover
  /// the place the detail lives.
  Widget? _referenceButton() {
    final onOpen = onOpenLayerReference;
    if (layer.mediaReference == null || onOpen == null) {
      return null;
    }
    return _nameButton(
      slug: 'reference',
      tooltip: AppText.strings.tlLayerReference,
      look: _NameButtonLook(
        const RailIconGlyph(Icons.insert_drive_file_outlined),
        danger: isReferenceSourceShort,
      ),
      onPressed: (context) => onOpen(context, layerIdNow(context, layer.id)),
    );
  }

  /// An SE row's SPEAKER among the name's buttons (F-443, 유저 2026-10-23:
  /// 「se레이어의 사운드버튼도 se레이어만 쓰는데 자리 고정으로 차지하는거
  /// 비효율적이니 동일하게 위에서 말한 규칙적용해서 위치옮김」) — the room a
  /// row's own button takes comes out of its name. ↩️It stood in a column
  /// of its own after the eye, reserved and empty on every other row.
  ///
  /// A DOOR, not a toggle (R10 R3): it opens the SE mixer (mute, solo, the
  /// total volume) under itself, and SHOWS mute and solo, because a door has
  /// to say what is behind it — solo in the accent, as a selection reads.
  Widget? _soundButton(ColorScheme colorScheme) {
    final onOpenMixer = onOpenLayerMixer;
    if (layer.kind != LayerKind.se || onOpenMixer == null) return null;
    return _nameButton(
      slug: 'mute',
      tooltip: AppText.strings.layerAudioTitle,
      look: _NameButtonLook(
        RailIconGlyph(
          layer.muted ? Icons.volume_off : Icons.volume_up,
          color: isLayerSoloed ? colorScheme.primary : null,
        ),
      ),
      onPressed: (context) =>
          onOpenMixer(context, layerIdNow(context, layer.id)),
    );
  }

  /// The camera row's path button (I-89 ④, 유저 2026-10-12: 「카메라
  /// 경로표시 설정은 카메라 레이어에 두고싶어. 거기에 버튼으로서. 카메라는
  /// 지금 비지블이랑 불투명도가 어차피 글로벌이라서 이 경로도 글로벌 취급」):
  /// it opens how the canvas shows the camera's path under itself — one value
  /// for every open project, as the row's eye and its dim are. Among the
  /// name's buttons — the camera's row is never a reference row, so the two
  /// never stand together.
  Widget? _cameraPathButton() {
    final onOpen = onOpenCameraPath;
    if (!layer.kind.carriesCameraPath || onOpen == null) {
      return null;
    }
    return _nameButton(
      slug: 'camera-path',
      tooltip: AppText.strings.cameraPath,
      look: const _NameButtonLook(RailIconGlyph(Icons.route)),
      onPressed: onOpen,
    );
  }

  /// The camera row's graph button (I-89 ③) — the row being its own
  /// Transform group (㉙), the button its header's. It turns the graph of
  /// the layer the row stands for at the press ([BerthRow]).
  Widget? _graphToggle(BuildContext context) {
    final verbs = laneGraphVerbs;
    if (verbs == null || !headsGraph) return null;
    return LaneGraphToggle(
      kind: LaneGraphToggleKind.graph,
      name: '$keyPrefix-layer-graph-${layer.id}',
      axis: axis,
      on: graphOpen,
      onToggle: () {
        if (laneGraphHeadedBy(BerthRow.at(context) ?? layer, null)
            case final key?) {
          verbs.toggle(key);
        }
      },
    );
  }

  /// The attach-group twirl (UI-R20 #9), shown only when the group exists —
  /// same chevron pair as the lane twirl, the rail's ONE twirl glyph (this
  /// arm used to spell the pair out by hand while the x-sheet read the
  /// helper). Same key grammar on both surfaces so a folder and an attach
  /// base read alike anywhere.
  ///
  /// A drag from it sweeps the folds down the rail as the eye's does its
  /// column (F-475).
  Widget? _foldTwirl(BuildContext context) {
    final onToggle = onToggleGroupFold;
    if (!hasGroupFold || onToggle == null) return null;
    final kind = layer.kind.groupsLayers ? 'folder' : 'attach';
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.groupFold,
      child: LayerFoldTwirl(
        name: '$keyPrefix-$kind-twirl-${layer.id}',
        axis: axis,
        expanded: groupFoldExpanded,
        onToggle: () => onToggle(layerIdNow(context, layer.id)),
      ),
    );
  }

  // ── the trailing run ──────────────────────────────────────────────────

  List<Widget> _trailingCells(
    BuildContext context,
    ColorScheme colorScheme,
  ) => layerRailTrailingCells(
    axis: axis,
    columns: metrics.railColumns,
    optionalColumns: (
      onion: onToggleLayerOnionSkin != null,
      blend: onLayerBlendModeSelected != null,
    ),
    clip: _clipToggle(context),
    fx: _fxSwitch(context),
    onion: _onionToggle(context, colorScheme),
    visibility: _visibilityToggle(),
    opacity: _opacitySlot(),
    blend: _blendChip(context),
  );

  /// Clip to layer below (I-92): every row that can clip
  /// ([LayerKind.takesClipping]) — every OTHER kind reserves the slot so the
  /// legend header's column icons line up over one Excel-style grid
  /// (R-toolbar round).
  ///
  /// A toggle COLUMN, as the eye's is (F-475, 유저 2026-10-26: 「클리핑버튼도
  /// 위아래 드래그로 여러 버튼 동시조작 가능하게」) — kept in step with the
  /// grid's swipe column list, see [RailSwipeColumnPointer].
  Widget? _clipToggle(BuildContext context) {
    final onToggle = onToggleLayerClip;
    if (onToggle == null || !layer.kind.takesClipping) return null;
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.clip,
      child: ClipButton(
        name: '$keyPrefix-layer-clip-${layer.id}',
        isOn: layer.clipsToBelow,
        size: railSlotBox(
          axis,
          slot: layerClipSlotWidth,
          across: 26,
          iconSize: 16,
        ),
        onPressed: () => onToggle(layerIdNow(context, layer.id)),
      ),
    );
  }

  /// Attach rows and their 공정 organizer folder hide the fx switch — the
  /// BASE's switch governs what they show, in BOTH orientations: a flip here
  /// would burn an undo step writing a flag nothing reads
  /// ([layerRowWearsFxSwitch], which the sweep and the spread read too).
  ///
  /// I-1: the three toggle COLUMNS own drags that start on them, so a
  /// press-and-drag paints the column down the rows instead of moving the
  /// row. Kept in step with the grid's swipe column list — see
  /// [RailSwipeColumnPointer].
  Widget? _fxSwitch(BuildContext context) {
    final onToggle = onToggleLayerFx;
    if (onToggle == null ||
        !layerRowWearsFxSwitch(
          layer.kind,
          wearsBaseComposite: wearsBaseComposite,
        )) {
      return null;
    }
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.fx,
      child: FxToggleButton(
        name: '$keyPrefix-layer-fx-${layer.id}',
        state: fxState,
        onToggle: () => onToggle(layerIdNow(context, layer.id)),
      ),
    );
  }

  /// Per-layer onion toggle (UI-R17 #5) beside the eye — only brush-holding
  /// rows get the button; rows keep the slot so the control columns stay
  /// aligned; hosts without the callback (no header cell either) skip the
  /// column whole. The sheet went without it until R10 R6's "싹다 넣어".
  Widget? _onionToggle(BuildContext context, ColorScheme colorScheme) {
    final onToggle = onToggleLayerOnionSkin;
    if (onToggle == null || !layer.kind.takesOnionSkin) {
      return null;
    }
    return RailSwipeColumnPointer(
      column: RailSwipeColumn.onion,
      child: RailGlyphButton(
        name: '$keyPrefix-layer-onion-${layer.id}',
        tooltip: onionSkinEnabled
            ? AppText.strings.railOnionSkinOn
            : AppText.strings.railOnionSkin,
        size: railSlotBox(
          axis,
          slot: layerOnionSlotWidth,
          across: 26,
          iconSize: 15,
        ),
        glyph: RailIconGlyph(
          Icons.filter_none,
          color: onionSkinEnabled
              ? colorScheme.primary
              : colorScheme.outline.withValues(alpha: 0.45),
        ),
        onPressed: () => onToggle(layerIdNow(context, layer.id)),
      ),
    );
  }

  /// Built from [RailEyes], not from [layer]: a memoized row keeps the
  /// [Layer] it was built with, and the eye is the one thing a flip changes
  /// — so it is the one thing a flip rebuilds (an-eye-rebuilds-its-whole-row).
  Widget _visibilityToggle() => RailSwipeColumnPointer(
    column: RailSwipeColumn.visibility,
    child: RailEyeBuilder(
      layer: layer,
      builder: (context, eye) => LayerVisibilityToggleButton(
        name: '$keyPrefix-layer-visibility-${layer.id}',
        isVisible: eye.on,
        hiddenAbove: eye.hiddenAbove,
        onToggle: () => onToggleLayerVisibility(layerIdNow(context, layer.id)),
      ),
    ),
  );

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
  Widget? _blendChip(BuildContext context) {
    final onSelected = onLayerBlendModeSelected;
    if (onSelected == null || !layerKindShowsBlendControl(layer.kind)) {
      return null;
    }
    final isGroup = layer.kind.groupsLayers;
    return LayerBlendModeChip(
      axis: axis,
      name: '$keyPrefix-layer-blend-${layer.id}',
      optionKeyPrefix: '$keyPrefix-layer-blend-option-',
      blendMode: layer.blendMode,
      isGroup: isGroup,
      onBlendModeSelected: (mode) =>
          onSelected(layerIdNow(context, layer.id), mode),
    );
  }

  /// The row's opacity slider, live-following the session's drag preview
  /// when it targets this layer (the master bar sweep, UI-R6 #2). Stood up
  /// like every other control in a column: the fader fills upward and its
  /// readout reads down the column, lying on its side (유저 2026-09-10:
  /// 「x시트의 불투명도바는 세로쓰기 세로표기로」). ⚠️The BAR is still not a
  /// `RotatedBox` — only its writing is; see [FieldSlider.axis].
  Widget _opacityField() => layerOpacityField(
    layer: layer,
    keyPrefix: keyPrefix,
    axis: axis,
    dragPreview: opacityDragPreview,
    onChanged: onLayerOpacityChanged,
    onChangeEnd: onLayerOpacityChangeEnd,
  );
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
  final has = _rowFolds(row, layers);
  if (row.isFolder) {
    return (
      has: has,
      expanded: !row.layer.collapsed,
      onToggle: onToggleLayerCollapsed,
    );
  }
  return (
    has: has,
    expanded: !collapsedAttachBaseIds.contains(row.layer.id),
    onToggle: onToggleAttachGroup,
  );
}

/// Whether [row] of [layers] folds rows of its own — a folder its members,
/// an attach base the attach rows riding it: a twirl ends its name
/// ([timelineGroupFoldFor]).
bool _rowFolds(TimelineDisplayRow row, List<Layer> layers) =>
    row.isFolder || attachedLayersOf(row.layer.id, layers).isNotEmpty;

/// What a button at the end of a name looks like
/// ([TimelineLayerControlsRow]): its glyph, and whether it warns — the
/// reference button, red while its file is short of film.
final class _NameButtonLook {
  const _NameButtonLook(this.glyph, {this.danger = false});

  final RailGlyph glyph;
  final bool danger;
}
