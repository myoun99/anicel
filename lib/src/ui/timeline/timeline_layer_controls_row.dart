import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/attached_placement.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../text/app_strings.dart';
import '../widgets/field_slider.dart';
import 'layer_label_controls.dart';
import 'timeline_grid_metrics.dart';

/// Whether two [Layer] snapshots would make [TimelineLayerControlsRow] look
/// EXACTLY the same — the rail memo's gate.
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
/// Deliberately absent (the row renders none of them): `frames`, `timeline`,
/// `instructions`, `audioClips`, `baseFrameLinks`, `runBehaviors`,
/// `transformTrack` (the LANE rows read it, and those are unmemoized),
/// `audioGain`/`audioPan` (the mix menu reads them at open time),
/// `attachedMode` and `folderId`.
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
  Future<void> _showMixMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    final strings = resolveStrings?.call() ?? AppStrings.of(AppLanguage.en);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [
        if (onToggleLayerSolo != null)
          PopupMenuItem<String>(
            key: ValueKey<String>('timeline-layer-solo-${layer.id}'),
            value: 'solo',
            child: Text(isLayerSoloed ? strings.audioUnsolo : strings.audioSolo),
          ),
        if (onEditLayerAudio != null)
          PopupMenuItem<String>(
            key: ValueKey<String>('timeline-layer-audio-${layer.id}'),
            value: 'audio',
            child: Text(strings.audioLayerAudioMenu),
          ),
      ],
    );
    switch (selected) {
      case 'solo':
        onToggleLayerSolo?.call(layer.id);
      case 'audio':
        onEditLayerAudio?.call(layer.id);
      case _:
        break;
    }
  }

  const TimelineLayerControlsRow({
    super.key,
    required this.layer,
    required this.active,
    required this.metrics,
    required this.onSelectLayer,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    required this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    this.onToggleLayerFillReference,
    this.onToggleLayerMuted,
    this.isLayerSoloed = false,
    this.onToggleLayerSolo,
    this.onEditLayerAudio,
    this.resolveStrings,
    this.hasLanes = false,
    this.lanesExpanded = false,
    this.onToggleLanes,
    this.depth = 0,
    this.hasGroupFold = false,
    this.groupFoldExpanded = true,
    this.onToggleGroupFold,
    this.onDissolveFolder,
    this.onRenameFolder,
    this.fxState = LayerFxState.on,
    this.onToggleLayerFx,
    this.onionSkinEnabled = false,
    this.onToggleLayerOnionSkin,
    this.opacityDragPreview,
    this.isLinked = false,
    this.onLayerBlendModeSelected,
    this.blendLanguage = AppLanguage.en,
    this.opacityOverride,
  });

  final Layer layer;
  final bool active;
  final TimelineGridMetrics metrics;
  final ValueChanged<LayerId> onSelectLayer;
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

  /// SE rows' speaker button (the audio counterpart of visibility); null
  /// hides it.
  final ValueChanged<LayerId>? onToggleLayerMuted;

  /// Whether this SE row is soloed (AUDIO-PRO R1) — the speaker tints
  /// accent while soloing narrows monitoring to the soloed rows.
  final bool isLayerSoloed;

  /// Toggles the SE row's solo — on the speaker's context menu (the rail
  /// has no room for another column; the menu also carries the layer's
  /// fader/pan entry).
  final ValueChanged<LayerId>? onToggleLayerSolo;

  /// Opens the layer's audio dialog (fader + pan).
  final ValueChanged<LayerId>? onEditLayerAudio;

  /// The PROGRAM-language table for the mix menu; null keeps English.
  final AppStrings Function()? resolveStrings;

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

  /// Folder rows' context menu; null hides the entry.
  final ValueChanged<LayerId>? onDissolveFolder;
  final ValueChanged<LayerId>? onRenameFolder;

  /// The AE-style fx switch as a MASTER over the row's per-group switches
  /// (R8: model state, so it survives a reload and reaches every composite
  /// route through the cut itself).
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

  /// R27 #9: a live opacity source that OUTRANKS `layer.opacity` for this
  /// row's slider. The camera row's opacity is a view notifier, not model
  /// state — reading it here lets the drag repaint just this slider
  /// instead of rebuilding the whole timeline host per move.
  final ValueListenable<double>? opacityOverride;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.secondaryContainer.withValues(alpha: 0.55);
    // CONSTANT 1px side/bottom borders (UI-R10 #20). Selection speaks
    // through the BACKGROUND alone now (UI-R18 #5) — the accent border
    // doubled the signal for nothing.
    final borderColor = colorScheme.outlineVariant;

    final row = InkWell(
      key: ValueKey<String>(
        layerKindGroupsLayers(layer.kind)
            ? 'timeline-folder-row-${layer.id}'
            : 'timeline-layer-row-${layer.id}',
      ),
      onTap: () => onSelectLayer(layer.id),
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
        decoration: BoxDecoration(
          color: active ? activeColor : colorScheme.surface,
          border: Border(
            left: BorderSide(color: borderColor),
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
              // The reserved section slot (UI-R7 #2): the section ZONE —
              // tint, upright label, flyout tap — overlays the whole run
              // from the grid (SectionBandZone), old-gutter style.
              const LayerSectionBandCell(),
              SizedBox(width: 8.0 + depth * 12.0),
              if (hasLanes && onToggleLanes != null)
                InkWell(
                  key: ValueKey<String>('timeline-lane-toggle-${layer.id}'),
                  onTap: () => onToggleLanes!(layer.id),
                  // R26 #28: icon buttons hover ROUND, like every other
                  // icon control — the square ink silhouette is retired.
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: layerLaneToggleSlotWidth,
                    height: 24,
                    child: Icon(
                      lanesExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 16,
                    ),
                  ),
                )
              else
                const SizedBox(width: layerLaneToggleSlotWidth),
              // Timesheet + mark chips lead the label; ineligible rows keep
              // empty slots so kind icons and names stay column-aligned.
              // Attach rows (W5) hide the sheet toggle — they are display
              // accessories of their base, never sheet columns.
              if (layerKindEligibleForTimesheetToggle(layer.kind) &&
                  layer.attachedToLayerId == null)
                LayerTimesheetToggleButton(
                  keyPrefix: 'timeline',
                  layerId: layer.id,
                  onTimesheet: layer.onTimesheet,
                  onToggle: onToggleLayerTimesheet,
                )
              else
                const SizedBox(width: layerTimesheetSlotWidth),
              const SizedBox(width: layerControlChipGap),
              LayerMarkChip(
                keyPrefix: 'timeline',
                layerId: layer.id,
                mark: layer.mark,
                onMarkSelected: onLayerMarkSelected,
              ),
              const SizedBox(width: layerControlChipGap),
              // The TYPE BUTTON (UI-R24 #7): the kind icon — or the attach
              // placement arrow — in its OWN fixed slot, a control
              // separate from the name (function TBD again — R26 #30-1
              // moved the blend flyout to the toolbar's PS-style
              // dropdown, user rule 07-22; tap selects for now). One slot
              // for every row kind, so attach rows align with the rest
              // (UI-R24 #8 — the old arrow indent is gone).
              InkWell(
                key: ValueKey<String>('timeline-layer-type-button-${layer.id}'),
                onTap: () => onSelectLayer(layer.id),
                customBorder: const CircleBorder(), // R26 #28
                child: SizedBox(
                  width: 22,
                  height: 24,
                  child: Center(
                    child: layer.attachedToLayerId != null
                        // Attach rows (UI-R20 #10): the placement arrow IS
                        // the type mark — bending up-right when the row
                        // attaches above, down-right below. No kind icon
                        // (the base carries the kind).
                        ? Semantics(
                            label:
                                layer.attachedPlacement ==
                                    AttachedPlacement.above
                                ? 'Attach layer (above)'
                                : 'Attach layer (below)',
                            container: true,
                            child: ExcludeSemantics(
                              child: Transform.flip(
                                flipY:
                                    layer.attachedPlacement ==
                                    AttachedPlacement.above,
                                child: Icon(
                                  Icons.subdirectory_arrow_right,
                                  key: ValueKey<String>(
                                    'timeline-layer-attach-arrow-${layer.id}',
                                  ),
                                  size: 16,
                                ),
                              ),
                            ),
                          )
                        : Semantics(
                            label: _semanticLabelForLayerKind(layer.kind),
                            container: true,
                            child: ExcludeSemantics(
                              child: layerKindGroupsLayers(layer.kind)
                                  // A folder's glyph reads its own fold.
                                  ? Icon(
                                      layer.collapsed
                                          ? Icons.folder
                                          : Icons.folder_open,
                                      key: ValueKey<String>(
                                        'timeline-folder-icon-${layer.id}',
                                      ),
                                      size: 16,
                                      color: colorScheme.onSurfaceVariant,
                                    )
                                  : Icon(
                                      layerKindIcon(layer.kind),
                                      key: ValueKey<String>(
                                        'timeline-layer-kind-icon-${layer.id}',
                                      ),
                                      size: 18,
                                    ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  key: ValueKey<String>('timeline-layer-name-${layer.id}'),
                  onTap: () => onSelectLayer(layer.id),
                  // No hover glow on the NAME either (UI-R24 #6).
                  hoverColor: Colors.transparent,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        // Selection reads by COLOR only (user rule): no
                        // bold flip, so the text never reflows on select.
                        Flexible(
                          child: Text(
                            layer.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLinked)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Tooltip(
                              message: 'Linked layer — pictures are shared',
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
                        // The attach-group twirl (UI-R20 #9), shown only
                        // when the group exists — same chevron pair as the
                        // lane twirl.
                        if (hasGroupFold && onToggleGroupFold != null)
                          InkWell(
                            key: ValueKey<String>(
                              layerKindGroupsLayers(layer.kind)
                                  ? 'timeline-folder-twirl-${layer.id}'
                                  : 'timeline-attach-twirl-${layer.id}',
                            ),
                            onTap: () => onToggleGroupFold!(layer.id),
                            customBorder: const CircleBorder(), // R26 #28
                            child: SizedBox(
                              width: layerLaneToggleSlotWidth,
                              height: 24,
                              child: Icon(
                                groupFoldExpanded
                                    ? Icons.arrow_drop_down
                                    : Icons.arrow_right,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Fill-reference toggle (R20-C2): drawing rows only — every
              // OTHER kind reserves the slot so the legend header's column
              // icons line up over one Excel-style grid (R-toolbar round).
              if (onToggleLayerFillReference != null &&
                  layer.kind == LayerKind.animation)
                SizedBox(
                  width: layerFillReferenceSlotWidth,
                  height: 26,
                  child: IconButton(
                    key: ValueKey<String>(
                      'timeline-layer-fill-reference-${layer.id}',
                    ),
                    tooltip: layer.isFillReference
                        ? 'Fill reference layer (on)'
                        : 'Fill reference layer',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: layerFillReferenceSlotWidth,
                      height: 26,
                    ),
                    icon: Icon(
                      Icons.format_color_fill,
                      size: 16,
                      color: layer.isFillReference
                          ? colorScheme.primary
                          : colorScheme.outline.withValues(alpha: 0.45),
                    ),
                    onPressed: () => onToggleLayerFillReference!(layer.id),
                  ),
                )
              else
                const SizedBox(width: layerFillReferenceSlotWidth),
              // Attach rows hide the fx switch — the BASE's switch governs
              // the shared transform/opacity lanes (W5 fx sharing).
              if (onToggleLayerFx != null &&
                  layerKindShowsFxToggle(layer.kind) &&
                  layer.attachedToLayerId == null)
                FxToggleButton(
                  keyValue: 'timeline-layer-fx-${layer.id}',
                  state: fxState,
                  onToggle: () => onToggleLayerFx!(layer.id),
                )
              else
                const SizedBox(width: layerFxSlotWidth),
              // Per-layer onion toggle (UI-R17 #5) beside the eye — only
              // brush-holding rows get the button; rows keep the slot so
              // the control columns stay aligned; hosts without the
              // callback (no header cell either) skip the column whole.
              if (onToggleLayerOnionSkin != null &&
                  layerKindAcceptsBrushInput(layer.kind))
                SizedBox(
                  width: layerOnionSlotWidth,
                  height: 26,
                  child: IconButton(
                    key: ValueKey<String>('timeline-layer-onion-${layer.id}'),
                    tooltip: onionSkinEnabled
                        ? 'Onion skin (on)'
                        : 'Onion skin',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: layerOnionSlotWidth,
                      height: 26,
                    ),
                    icon: Icon(
                      Icons.filter_none,
                      size: 15,
                      color: onionSkinEnabled
                          ? colorScheme.primary
                          : colorScheme.outline.withValues(alpha: 0.45),
                    ),
                    onPressed: () => onToggleLayerOnionSkin!(layer.id),
                  ),
                )
              else if (onToggleLayerOnionSkin != null)
                const SizedBox(width: layerOnionSlotWidth),
              LayerVisibilityToggleButton(
                keyValue: 'timeline-layer-visibility-${layer.id}',
                isVisible: layer.isVisible,
                onToggle: () => onToggleLayerVisibility(layer.id),
              ),
              // SE rows carry the mute speaker beside the eye (sounds
              // silence, waveforms keep displaying). Tight SizedBox: the M3
              // IconButton otherwise inflates its layout box to the 48px
              // minimum tap target, overflowing the rail row.
              if (layer.kind == LayerKind.se && onToggleLayerMuted != null)
                SizedBox(
                  width: layerMuteSlotWidth,
                  height: 26,
                  // Right-click/long-press: the mix menu (solo + fader/pan
                  // dialog) — the rail has no room for more columns, so
                  // the speaker doubles as the SE row's mixer entrance.
                  child: GestureDetector(
                    onSecondaryTapUp:
                        onToggleLayerSolo == null && onEditLayerAudio == null
                        ? null
                        : (details) =>
                              _showMixMenu(context, details.globalPosition),
                    onLongPressStart:
                        onToggleLayerSolo == null && onEditLayerAudio == null
                        ? null
                        : (details) =>
                              _showMixMenu(context, details.globalPosition),
                    child: LayerMuteToggleButton(
                      keyValue: 'timeline-layer-mute-${layer.id}',
                      muted: layer.muted,
                      soloed: isLayerSoloed,
                      onToggle: () => onToggleLayerMuted!(layer.id),
                    ),
                  ),
                )
              else
                const SizedBox(width: layerMuteSlotWidth),
              // The camera row's slider drives the camera-view DIM opacity
              // (unified layer controls); every row shrinks alike so the
              // control columns stay aligned.
              if (layerKindShowsOpacityControl(layer.kind))
                SizedBox(width: layerOpacitySlotWidth, child: _opacityField())
              else
                const SizedBox(width: layerOpacitySlotWidth),
              // R27 #6: the blend mode, RIGHTMOST — the user's placement.
              // Within a host that HAS the column, non-compositing kinds
              // keep the slot so rows and the legend header stay aligned;
              // hosts without it (the storyboard's track rail) skip the
              // column outright, exactly like the onion cell.
              if (onLayerBlendModeSelected != null)
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
                    : const SizedBox(width: layerBlendSlotWidth),
            ],
          ),
        ),
      ),
    );

    // Section boundaries draw ONE shared hairline like every row boundary
    // (R3 feedback #6) — the old extra 2px overlay double-lined them; the
    // gutter bracket carries the section identity.
    if (!layerKindGroupsLayers(layer.kind) ||
        (onRenameFolder == null && onDissolveFolder == null)) {
      return row;
    }
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showFolderMenu(context, details.globalPosition),
      onLongPressStart: (details) =>
          _showFolderMenu(context, details.globalPosition),
      child: row,
    );
  }

  /// The folder row's structural verbs. Everything else a folder does is
  /// on the row's own columns, because a folder is a layer.
  Future<void> _showFolderMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [
        if (onRenameFolder != null)
          PopupMenuItem<String>(
            key: ValueKey<String>('timeline-folder-rename-${layer.id}'),
            value: 'rename',
            child: Text(AppText.strings.tlRenameFolder),
          ),
        if (onDissolveFolder != null)
          PopupMenuItem<String>(
            key: ValueKey<String>('timeline-folder-dissolve-${layer.id}'),
            value: 'dissolve',
            child: Text(AppText.strings.tlDissolveFolder),
          ),
      ],
    );
    switch (selected) {
      case 'rename':
        onRenameFolder?.call(layer.id);
      case 'dissolve':
        onDissolveFolder?.call(layer.id);
      case _:
        break;
    }
  }

  /// The row's opacity slider, live-following the session's drag preview
  /// when it targets this layer (the master bar sweep, UI-R6 #2).
  Widget _opacityField() {
    Widget slider(double value) => FieldSlider(
      key: ValueKey<String>('timeline-layer-opacity-${layer.id}'),
      min: 0,
      max: 1,
      value: value,
      valueText: '${(value * 100).round()}%',
      valueTextBuilder: (next) => '${(next * 100).round()}%',
      displayFactor: 100,
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

String _semanticLabelForLayerKind(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation => 'Animation layer',
    LayerKind.storyboard => 'Storyboard layer',
    LayerKind.image => 'Image layer',
    LayerKind.text => 'Text layer',
    LayerKind.se => 'SE layer',
    LayerKind.instruction => 'Instruction layer',
    LayerKind.camera => 'Camera layer',
    LayerKind.folder => 'Folder',
    LayerKind.adjustment => 'Adjustment layer',
  };
}
