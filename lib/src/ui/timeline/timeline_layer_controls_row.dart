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
import 'layer_label_controls.dart';
import 'layer_rail_columns.dart';
import 'timeline_grid_metrics.dart';

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

class TimelineLayerControlsRow extends StatelessWidget {
  const TimelineLayerControlsRow({
    super.key,
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
  /// Null [onToggleGroupFold] hides the twirl entirely.
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Shared with the property lanes' own "you are standing here" wash
    // ([railSelectedRowColor]) so the two cannot drift apart.
    final activeColor = railSelectedRowColor(colorScheme);
    // CONSTANT 1px side/bottom borders (UI-R10 #20). Selection speaks
    // through the BACKGROUND alone now (UI-R18 #5) — the accent border
    // doubled the signal for nothing.
    final borderColor = colorScheme.outlineVariant;

    // 🚨T10 — the rail row picks on the PRESS, exactly like a frame cell.
    //
    // 유저 확정 2026-08-14: 「행이든 뭐든 동일하게」. This row used to pick on
    // `InkWell.onTap` — the release — while the cells moved to the press,
    // and two surfaces answering the same gesture differently is the
    // complaint the user has made more than once (「제발 규칙다른거
    // 그만좀하자」). Both wear the same widget-level policy now, device gate
    // included.
    //
    // ⛔The InkWell keeps a NO-OP `onTap`, which is not decoration: it holds
    // a tap recognizer in the arena so scroll slop over a row behaves the
    // way it always has. The painted cells do the identical thing for the
    // identical reason.
    final row = InstantTapRegion(
      pressSeeksFor: AppInput.timelineCellPressSeeks,
      // The PICK. Whether it also CLEARS is the session's call — see
      // `standOnRow`, which holds the selection when the press landed inside
      // it, because that press is most likely the start of a move.
      onTap: (_) => onSelectLayer(layer.id),
      // And when the press turned out to be a tap, the selection goes —
      // 유저: 「클릭하고 떼면 뭐든 비우게」.
      onSettledTap: onSettledPress == null ? null : (_) => onSettledPress!(),
      child: InkWell(
        key: ValueKey<String>(
          layerKindGroupsLayers(layer.kind)
              ? 'timeline-folder-row-${layer.id}'
              : 'timeline-layer-row-${layer.id}',
        ),
        onTap: () {},
        // No hover glow on the ROW surface (UI-R24 #6): selection speaks
        // through the background alone; only the buttons may brighten.
        hoverColor: Colors.transparent,
        child: Container(
          // The section bracket occupies the leading gutter beside the rail.
          width: metrics.layerControlsWidth - metrics.sectionLabelGutterWidth,
          height: metrics.layerRowHeight,
          // The section band hugs the row's LEFT edge (UI-R6 #5); the 8px
          // breathing room moves between the band and the lane chevron.
          padding: const EdgeInsets.only(right: 8),
          // CHROMELESS drops the ground and keeps the contents — the row over
          // the artwork when the panel is folded (유저 확정: 바탕 없이 내용만).
          // A flag on the real row rather than a second row that lists the
          // same slots: the collapsed overlay then follows this widget by
          // construction, including whatever column it grows next.
          decoration: chromeless
              ? null
              : BoxDecoration(
                  // ㊴: the wash is the ACTIVE row's alone. `selected` used to
                  // share it, and on screen that made the two states one —
                  // the selection now speaks through the ring below, the way
                  // a selected frame run always has.
                  color: active ? activeColor : colorScheme.surface,
                  border: Border(
                    left: BorderSide(
                      color: borderColor,
                      width: timelineLayerRowLeadingBorder,
                    ),
                    right: BorderSide(color: borderColor),
                    bottom: BorderSide(color: borderColor),
                  ),
                ),
          child: Semantics(
            key: active
                ? const ValueKey<String>('timeline-selected-layer')
                : null,
            label: active ? 'selected layer' : 'layer',
            container: true,
            explicitChildNodes: true,
            child: Row(
              children: [
                // The rail's shared column skeleton (R9 #22): slot order and
                // widths come from ONE place, so the storyboard's rows and
                // the legend header cannot drift from these again.
                // ⛔`depth` no longer belongs here: nesting moved into the
                // NAME column so the buttons keep one x at every depth.
                ...layerRailLeadingCells(
                  laneToggle: hasLanes && onToggleLanes != null
                      // I-1: a leading toggle COLUMN owns drags that start on
                      // it, exactly as the trailing three do — the strong
                      // claim, kept in step with the grid's swipe column list
                      // (see [RailSwipeColumnPointer]).
                      ? RailSwipeColumnPointer(
                          child: AppIconButton(
                            keyValue: 'timeline-lane-toggle-${layer.id}',
                            tooltip: lanesExpanded
                                ? 'Collapse lanes'
                                : 'Expand lanes',
                            // The rail's law, read off the onion column ten
                            // slots along rather than invented here: a box tight
                            // to the slot, because `layerLaneToggleSlotWidth` is
                            // 16 and an IconButton left alone asks for 48. The
                            // slot is the PARENT's number, so it travels as an
                            // [AppIconButtonBox] rather than a token.
                            //
                            // R26 #28 (icon buttons hover ROUND) survives the
                            // swap for free — an IconButton's ink is already a
                            // circle, which is the whole reason the hand-rolled
                            // `customBorder: CircleBorder()` could go with it.
                            size: const AppIconButtonBox(
                              width: layerLaneToggleSlotWidth,
                              height: 24,
                              iconSize: 16,
                            ),
                            icon: Icon(
                              lanesExpanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                            ),
                            onPressed: () => onToggleLanes!(layer.id),
                          ),
                        )
                      : null,
                  // Timesheet + mark chips lead the label. Attach rows (W5)
                  // hide the sheet toggle — they are display accessories of
                  // their base, never sheet columns — and R10 R3 put their
                  // ARROW in the slot the toggle vacates, so the column
                  // reads "sheet, or what this row is attached to".
                  timesheet: attachArrowPlacement != null
                      ? LayerAttachArrowCell(
                          keyPrefix: 'timeline',
                          idValue: '${layer.id}',
                          placement: attachArrowPlacement!,
                        )
                      : layerKindEligibleForTimesheetToggle(layer.kind) &&
                            layer.attachedToLayerId == null
                      // I-1: the column the report named 「타임시트버튼이든 뭐
                      // 그런것들」. The claim goes on at the RAIL, not inside
                      // the button — the x-sheet's header shares that widget
                      // and has no swipe.
                      ? RailSwipeColumnPointer(
                          child: LayerTimesheetToggleButton(
                            keyPrefix: 'timeline',
                            layerId: layer.id,
                            onTimesheet: layer.onTimesheet,
                            onToggle: onToggleLayerTimesheet,
                          ),
                        )
                      : null,
                  mark: LayerMarkChip(
                    keyPrefix: 'timeline',
                    layerId: layer.id,
                    mark: layer.mark,
                    onMarkSelected: onLayerMarkSelected,
                    isVisible: layer.isVisible,
                  ),
                  // The TYPE BUTTON (UI-R24 #7): the kind icon in its OWN
                  // fixed slot, a control separate from the name (function
                  // TBD again — R26 #30-1 moved the blend flyout to the
                  // toolbar's PS-style dropdown, user rule 07-22; tap
                  // selects for now). One slot for every row kind, ALWAYS
                  // the kind (R10 R3): the arrow that used to take this
                  // slot on attach rows now rides the sheet column.
                  typeButton: LayerTypeButton(
                    keyPrefix: 'timeline',
                    idValue: '${layer.id}',
                    kind: layer.kind,
                    folderCollapsed: layer.collapsed,
                    onTap: () => onSelectLayer(layer.id),
                  ),
                ),
                // 🚨★★★NESTING LIVES HERE NOW, AND ONLY HERE.
                //
                // 유저 2026-08-29: the leading run used to spend a 16px cell
                // per level plus a ↳ cell, which pushed every button right and
                // 「계속밀려서 제대로 안보이게」 되었다. The buttons keep one x
                // at every depth now; the NAME is what gives ground, and a
                // clipped name still reads while a clipped button cannot be
                // pressed.
                //
                // The guides say the depth — one hairline per level, drawn
                // inside the name's own box.
                if (depth > 0)
                  SizedBox(
                    width: layerRailNameIndent(depth),
                    child: Row(
                      children: [
                        for (var level = 0; level < depth; level += 1)
                          SizedBox(
                            width: layerRailGuideWidth,
                            child: Center(
                              child: SizedBox(
                                width: 1,
                                height: double.infinity,
                                child: ColoredBox(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey<String>('timeline-layer-name-${layer.id}'),
                    // 🚨F-26 (유저 2026-08-24): 「레이어 클릭하고 이름영역
                    // 클릭시 **선택되는 애니메이션같은거 발동**하는데, 없애고
                    // 해당영역 클릭시 레이어라벨 빈공간 클릭이랑 마찬가지로
                    // 레이어 자체가 밝아지는 애니메이션 적용되도록.
                    // **규칙단순화**」.
                    //
                    // ⛔The name used to be an InkWell of its own, selecting
                    // the layer a SECOND time on top of the row's press-seek.
                    // Two consequences, both the report: it rippled where the
                    // rest of the row does not, and it picked on the RELEASE
                    // where the row picks on the DOWN (T10) — so the same
                    // click meant two different moments depending on which
                    // pixel it landed on.
                    //
                    // ★The row's own [InstantTapRegion] already covers every
                    // pixel of this area. Taking the InkWell away is not
                    // removing a behaviour; it is removing a SECOND one.
                    // 🚨F-29 (유저 2026-08-24): 「접기 펼치기 아이콘 위치 조정.
                    // 지금 레이어이름 옆에 붙어있는데, 그게아니라 위치는 항상
                    // 고정으로 두고싶기때문에 레이어 이름영역의 오른쪽정렬로
                    // 고정」.
                    //
                    // ⛔The twirl used to be the last child of a MIN-width Row
                    // inside a left Align, so it sat wherever the name ended —
                    // a different x on every row, and a moving x on a rename.
                    // The NAME takes the space now and the twirl trails it at
                    // the region's right edge, which is the one place it can
                    // be that does not depend on what the row is called.
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              // Selection reads by COLOR only (user rule): no
                              // bold flip, so the text never reflows on select.
                              Flexible(
                                child: Text(
                                  layer.name,
                                  style: layerRowNameStyle(context),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLinked)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Tooltip(
                                    message:
                                        'Linked layer — pictures are shared',
                                    child: Icon(
                                      Icons.link,
                                      key: ValueKey<String>(
                                        'timeline-layer-link-badge-${layer.id}',
                                      ),
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // The attach-group twirl (UI-R20 #9), shown only when
                        // the group exists — same chevron pair as the lane
                        // twirl. Its SLOT is always here (F-29): a row that
                        // folds nothing reserves the width rather than letting
                        // the name run into it, so the icons on the rows that
                        // do fold all sit on one line.
                        SizedBox(
                          width: layerLaneToggleSlotWidth,
                          child: hasGroupFold && onToggleGroupFold != null
                              ? ControlPressClaim(
                                  onPressed: () => onToggleGroupFold!(layer.id),
                                  child: InkWell(
                                    key: ValueKey<String>(
                                      layerKindGroupsLayers(layer.kind)
                                          ? 'timeline-folder-twirl-${layer.id}'
                                          : 'timeline-attach-twirl-${layer.id}',
                                    ),
                                    onTap: silentPress(
                                      () => onToggleGroupFold!(layer.id),
                                    ),
                                    // R26 #28
                                    customBorder: const CircleBorder(),
                                    child: SizedBox(
                                      width: layerLaneToggleSlotWidth,
                                      height: 24,
                                      // The rail's ONE twirl glyph — this
                                      // arm used to spell the pair out by
                                      // hand while the x-sheet read the
                                      // helper.
                                      child: Icon(
                                        layerRailTwirlIcon(
                                          expanded: groupFoldExpanded,
                                        ),
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                ...layerRailTrailingCells(
                  // Fill-reference toggle (R20-C2): drawing rows only —
                  // every OTHER kind reserves the slot so the legend
                  // header's column icons line up over one Excel-style grid
                  // (R-toolbar round).
                  fillReference:
                      onToggleLayerFillReference != null &&
                          layer.kind == LayerKind.animation
                      ? SizedBox(
                          height: 26,
                          child: AppIconButton(
                            keyValue:
                                'timeline-layer-fill-reference-${layer.id}',
                            tooltip: layer.isFillReference
                                ? 'Fill reference layer (on)'
                                : 'Fill reference layer',
                            size: const AppIconButtonBox(
                              width: layerFillReferenceSlotWidth,
                              height: 26,
                              iconSize: 16,
                            ),
                            icon: Icon(
                              Icons.format_color_fill,
                              color: layer.isFillReference
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.45),
                            ),
                            onPressed: () =>
                                onToggleLayerFillReference!(layer.id),
                          ),
                        )
                      : null,
                  // Attach rows and their 공정 organizer folder hide the fx
                  // switch — the BASE's switch governs what they show.
                  fx:
                      onToggleLayerFx != null &&
                          layerKindShowsFxToggle(layer.kind) &&
                          !wearsBaseComposite
                      // I-1: the three toggle COLUMNS own drags that start on
                      // them, so a press-and-drag paints the column down the
                      // rows instead of moving the row. Kept in step with the
                      // grid's swipe column list — see [RailSwipeColumnPointer].
                      ? RailSwipeColumnPointer(
                          child: FxToggleButton(
                            keyValue: 'timeline-layer-fx-${layer.id}',
                            state: fxState,
                            onToggle: () => onToggleLayerFx!(layer.id),
                          ),
                        )
                      : null,
                  // Per-layer onion toggle (UI-R17 #5) beside the eye — only
                  // brush-holding rows get the button; rows keep the slot so
                  // the control columns stay aligned; hosts without the
                  // callback (no header cell either) skip the column whole.
                  hasOnionColumn: onToggleLayerOnionSkin != null,
                  onion:
                      onToggleLayerOnionSkin != null &&
                          layerKindAcceptsBrushInput(layer.kind)
                      ? SizedBox(
                          height: 26,
                          child: RailSwipeColumnPointer(
                            child: AppIconButton(
                              keyValue: 'timeline-layer-onion-${layer.id}',
                              tooltip: onionSkinEnabled
                                  ? 'Onion skin (on)'
                                  : 'Onion skin',
                              size: const AppIconButtonBox(
                                width: layerOnionSlotWidth,
                                height: 26,
                                iconSize: 15,
                              ),
                              icon: Icon(
                                Icons.filter_none,
                                color: onionSkinEnabled
                                    ? colorScheme.primary
                                    : colorScheme.outline.withValues(
                                        alpha: 0.45,
                                      ),
                              ),
                              onPressed: () =>
                                  onToggleLayerOnionSkin!(layer.id),
                            ),
                          ),
                        )
                      : null,
                  visibility: RailSwipeColumnPointer(
                    child: LayerVisibilityToggleButton(
                      keyValue: 'timeline-layer-visibility-${layer.id}',
                      isVisible: layer.isVisible,
                      onToggle: () => onToggleLayerVisibility(layer.id),
                    ),
                  ),
                  // SE rows carry the mute speaker beside the eye (sounds
                  // silence, waveforms keep displaying). Tight SizedBox: the
                  // M3 IconButton otherwise inflates its layout box to the
                  // 48px minimum tap target, overflowing the rail row.
                  mute: layer.kind == LayerKind.se && onOpenLayerMixer != null
                      ? SizedBox(
                          height: 26,
                          child: LayerMuteToggleButton(
                            keyValue: 'timeline-layer-mute-${layer.id}',
                            muted: layer.muted,
                            soloed: isLayerSoloed,
                            onOpenMixer: (anchorContext) =>
                                onOpenLayerMixer!(anchorContext, layer.id),
                          ),
                        )
                      : null,
                  // The camera row's slider drives the camera-view DIM
                  // opacity (unified layer controls); every row shrinks
                  // alike so the control columns stay aligned.
                  opacity: layerKindShowsOpacityControl(layer.kind)
                      ? _opacityField()
                      : null,
                  // R27 #6: the blend mode, RIGHTMOST — the user's
                  // placement. Within a host that HAS the column,
                  // non-compositing kinds keep the slot so rows and the
                  // legend header stay aligned; hosts without it (the
                  // storyboard's track rail) skip the column outright,
                  // exactly like the onion cell.
                  hasBlendColumn: onLayerBlendModeSelected != null,
                  blend:
                      onLayerBlendModeSelected != null &&
                          layerKindShowsBlendControl(layer.kind)
                      ? LayerBlendModeChip(
                          keyValue: 'timeline-layer-blend-${layer.id}',
                          optionKeyPrefix: 'timeline-layer-blend-option-',
                          blendMode: layer.blendMode,
                          language: blendLanguage,
                          isGroup: layerKindGroupsLayers(layer.kind),
                          subject: layerKindGroupsLayers(layer.kind)
                              ? 'Folder'
                              : 'Layer',
                          onBlendModeSelected: (mode) =>
                              onLayerBlendModeSelected!(layer.id, mode),
                        )
                      : null,
                ),
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
    // semantics and keys its memo on it.
    // 🚨★★★THE WHOLE ROW IS 「레이어 쪽」 (유저 확정 2026-08-30): 「**레이어
    // 쪽 버튼은 탭다운, 헤더쪽은 손떼면**으로 충분할거같은데 맞지?」.
    //
    // ⛔Mounting this on the swipe columns alone was not enough, and the gap
    // was visible on one row: the group-fold twirl is not a swipe column, so
    // it acted on the RELEASE while the eye and the fx beside it acted on the
    // press. The rule the user stated is about the row, so it is stated on
    // the row — and the header, which is a different widget, keeps the
    // default.
    return PressFireScope(fireOn: PressFire.down, child: row);
  }

  /// The row's opacity slider, live-following the session's drag preview
  /// when it targets this layer (the master bar sweep, UI-R6 #2).
  Widget _opacityField() {
    Widget slider(double value) => FieldSlider.opacity(
      key: ValueKey<String>('timeline-layer-opacity-${layer.id}'),
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
