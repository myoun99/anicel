import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../../models/brush_tip_entry.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/drawing_guide.dart';
import '../../models/shape_tool_options.dart';
import '../../models/transform_values.dart';
import '../../services/canvas_read_source.dart';
import '../../services/canvas_flood_fill.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/resample/resample_kernel.dart';
import '../../services/transform_box_law.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/panel_keys.dart' show PanelKeysBinding;
import '../widgets/drag_value_label.dart';
import '../widgets/field_slider.dart';
import '../widgets/settings_rows.dart';
import 'brush_settings_panel.dart';
import 'brush_tool_state.dart';
import 'tool_setting_rows.dart';
import 'tool_settings_section.dart';
import 'guide_panels.dart';
import 'canvas_selection_commands.dart';
import 'canvas_traces.dart';
import 'cel_text_commands.dart';
import 'text_tool_options.dart';
import 'text_tool_settings.dart';
import 'transform_tool_options.dart';
import '../../models/cut_piece.dart';
import '../../services/cut_piece_slot.dart';
import 'brush_stroke_live_preview.dart';
import 'cut_piece_preview.dart';
import '../text/app_strings.dart';
import '../text/imported_fonts.dart';
import '../text/model_vocabulary.dart';
import '../text/pixel_size_label.dart';
import '../text/readout_text.dart';
import '../widgets/empty_state_text.dart';
import '../listenable_rebind.dart';
import '../widgets/pill_strip.dart';
import '../widgets/scale_chain_button.dart';

/// The TOOL SETTINGS panel (R11-④, CSP's tool property palette): detailed
/// knobs for the ACTIVE tool. Painting tools show the brush settings, the
/// fill shows its flood options, the selection tool picks its variant
/// (rectangle/lasso — R17-U: one toolbar tool), and Move shows the live
/// transform's numeric inputs.
class ToolSettingsPanel extends StatelessWidget {
  const ToolSettingsPanel({
    super.key,
    required this.state,
    required this.onChanged,
    required this.fillOptions,
    required this.onFillOptionsChanged,
    this.selectionMaskOptions = SelectionMaskOptions.none,
    this.onSelectionMaskOptionsChanged,
    this.transformOptions = TransformToolOptions.defaults,
    this.onTransformOptionsChanged,
    this.selectionCommands,
    this.canvasTraces,
    this.textOptions,
    this.textCommands,
    this.textFonts,
    this.pasteboard,
    this.language = AppLanguage.en,
    this.eyedropperSource = CanvasReadSource.display,
    this.onEyedropperSourceChanged,
    this.readLayerNames,
    this.tips = const <BrushTipEntry>[],
    this.onTipImportRequested,
    this.onRenameTip,
    this.onDeleteTip,
    this.guides,
    this.selectedGuideId,
    this.onGuidesCommitted,
    this.onGuidesPreview,
    this.onGuideRasterized,
    this.cutPieceSlot,
    this.onCutPasteAtOrigin,
    this.onRegisterCutPieceAsTip,
  });

  /// The active cut's guides, and which one the tool is editing. Null
  /// handler = the panel shows but cannot change them (hosts with no cut).
  final CutGuides? guides;
  final GuideId? selectedGuideId;
  final ValueChanged<CutGuides>? onGuidesCommitted;

  /// The guide drag in flight — see [GuideSettings.onGuidesPreview].
  final ValueChanged<CutGuides>? onGuidesPreview;

  /// 래스터라이즈 — see [GuideSettings.onGuideRasterized].
  final ValueChanged<DrawingGuide>? onGuideRasterized;

  /// The shared tip library, forwarded to the brush settings' tip pickers.
  final List<BrushTipEntry> tips;

  /// Opens the add-a-tip-from-an-image flow.
  final VoidCallback? onTipImportRequested;

  /// Manage a tip from inside the library popup. The pair of them is why
  /// picking no longer dismisses that popup.
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  /// The program language (BB-2): the brush blend labels localize
  /// (ja = CSP terms); everything else keeps incremental coverage.
  final AppLanguage language;

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;
  final FloodFillOptions fillOptions;
  final ValueChanged<FloodFillOptions> onFillOptionsChanged;

  /// R26 (C2): the Select tool's lift-time mask knobs (grow/shrink,
  /// inward feather, edge AA).
  final SelectionMaskOptions selectionMaskOptions;
  final ValueChanged<SelectionMaskOptions>? onSelectionMaskOptionsChanged;

  /// The transform tool's knobs: mode, scale anchor, AA, mesh grid. A null
  /// handler shows them disabled — the convention the eyedropper's source
  /// picker uses for hosts that do not own the setting.
  final TransformToolOptions transformOptions;
  final ValueChanged<TransformToolOptions>? onTransformOptionsChanged;

  /// The mounted selection layer's imperative channel — the Move tool's
  /// numeric inputs read and write the live transform through it.
  final CanvasSelectionCommands? selectionCommands;

  /// Every canvas's polygon trace: 닫기 closes the one the user is in the
  /// middle of, as 확정 does (F-380).
  final CanvasTraces? canvasTraces;

  /// The text tool's own (R9-rest): the next text's values, and the channel
  /// to the text the canvas holds. Null in a host that owns neither.
  final ValueNotifier<TextToolOptions>? textOptions;
  final CelTextCommands? textCommands;

  /// The fonts this device was brought, for the text tool's faces. Null in
  /// a host that keeps none.
  final ImportedFonts? textFonts;

  /// The wall of the cut on screen — its canvas, out as far as the
  /// project's pasteboard reaches (I-109) — that the selection tool's 선택
  /// 반전 inverts out to (I-23); its canvas is the paper guides are laid on.
  /// Null = no cut to take a wall from, and the button keeps its place,
  /// greyed.
  final PasteboardWall? pasteboard;

  /// The piece the cut tool is holding — the stamp tile's knobs pose it.
  final CutPieceSlot? cutPieceSlot;

  /// Drop the held piece back at the coordinates it was cut from. Whether it
  /// lands over what is there or under it is the BLEND's answer now (TS8),
  /// so this is ONE verb. Null = the host cannot paste (no cel).
  final VoidCallback? onCutPasteAtOrigin;

  /// Promote the held piece into the brush tip library. Explicit on
  /// purpose: cutting must never grow the library by itself.
  final VoidCallback? onRegisterCutPieceAsTip;

  /// R28 #6: where the eyedropper reads from (PS/CSP's 참조원). Null
  /// handler = the picker shows but cannot be changed (hosts that do not
  /// own the setting).
  final CanvasReadSource eyedropperSource;
  final ValueChanged<CanvasReadSource>? onEyedropperSourceChanged;

  /// The names of the layers a reading tool reads with a given source right
  /// now — null for every visible layer (I-36: 「범위를 보여주고」). The host
  /// answers with [layerNamesReadBy], the answer the fill and the
  /// eyedropper read by, so the line cannot name one thing while the tool
  /// reads another. A host with no answer shows the line empty.
  final List<String>? Function(CanvasReadSource source)? readLayerNames;

  List<String>? _namesReadBy(CanvasReadSource source) {
    final answer = readLayerNames;
    return answer == null ? const [] : answer(source);
  }

  /// What the tool in hand shows in the slot at the top, or null for a tool
  /// with nothing to preview.
  ///
  /// 🚨I-33: 「일단 **스탬프도구, 브러시/지우개**의 도구설정에서 비추게」 —
  /// 「일단」 is why this is a switch with a default rather than a field every
  /// section would have to remember to fill: adding the next tool is one arm.
  Widget? _preview() => switch (state.tool) {
    // 「브러시/지우개의 프리뷰는 스트로크를 보여줌. 설정하는거에 맞춰서 실시간
    // 갱신되는」 — the brush in the HAND, not a preset (see
    // [BrushStrokeLivePreview] for why it is not the list's widget).
    CanvasTool.brush || CanvasTool.eraser => ToolSettingsPreview(
      child: BrushStrokeLivePreview(settings: state.toBrushSettings()),
    ),
    // ↩️The stamp drew this INSIDE its own section until I-33, in a box it
    // spelled itself. Same picture, same 88, one place now — and it no
    // longer scrolls away with the knobs under it.
    CanvasTool.cutStamp => switch (cutPieceSlot) {
      final holder? => ListenableBuilder(
        listenable: holder,
        builder: (context, _) => ToolSettingsPreview(
          child: switch (holder.piece) {
            final piece? => CutPiecePreview(piece: piece),
            // ⛔The BOX stays while the hand is empty: a slot that came and
            // went would move every knob under it (없다가 생기는 UI 금지).
            // What is held — or that nothing is — the section says.
            _ => const SizedBox.shrink(),
          },
        ),
      ),
      _ => null,
    },
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    // Own Material (the tool LIBRARY panel's rule, same reason): the dock
    // body paints a background color, and the Switch/ListTile ink and
    // selection tints render on the nearest Material ancestor — without
    // one Flutter asserts that those effects would be invisible. R26 #31
    // surfaced it by docking this panel open by default, so every tool's
    // settings now build for real instead of only when its tab is picked.
    final preview = _preview();
    final settings = Material(
      type: MaterialType.transparency,
      child: ToolSettingSurface(child: _settingsOfTheTool()),
    );
    if (preview == null) {
      return settings;
    }
    // ⛔The preview is PINNED and the settings scroll under it — 「위치는
    // 도구 설정의 맨 위」. Putting it inside the section would have let it
    // scroll away, which is what the stamp's own copy did.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [preview, Expanded(child: settings)],
    );
  }

  /// The section of the tool in hand.
  Widget _settingsOfTheTool() => switch (state.tool) {
    CanvasTool.brush || CanvasTool.eraser => BrushSettingsPanel(
      state: state,
      onChanged: onChanged,
      tips: tips,
      onTipImportRequested: onTipImportRequested,
      onRenameTip: onRenameTip,
      onDeleteTip: onDeleteTip,
    ),
    CanvasTool.fill => _FillSettings(
      options: fillOptions,
      onChanged: onFillOptionsChanged,
      readLayerNames: _namesReadBy(fillOptions.source),
    ),
    // 유저 확정 ⑥: a panel PER TILE, showing what actually applies.
    // The bucket's knobs above are about reading the picture — where
    // the flood may go — and a drawn outline never asks that question,
    // so tolerance, gap close and pasteboard-fill are simply not here.
    // Only the edge is shared, because only the edge is shared.
    CanvasTool.fillShape => _ShapeFillSettings(
      options: fillOptions,
      onChanged: onFillOptionsChanged,
      shapeKind: state.activeShapeKind,
      traces: canvasTraces,
    ),
    // I-69: what the shape tool lays and what lays its line. A line of
    // the brush type is drawn by the brush in hand — its size and
    // opacity are the strip's, the rest the brush's own panel's; the
    // tool's own values are the strip's too, wherever it draws by them.
    CanvasTool.shape => _ShapeToolSettings(
      state: state,
      onChanged: onChanged,
    ),
    // R28 #6: the eyedropper has a REFERENCE SOURCE setting now.
    CanvasTool.eyedropper => _EyedropperSettings(
      source: eyedropperSource,
      onChanged: onEyedropperSourceChanged,
      readLayerNames: _namesReadBy(eyedropperSource),
    ),
    CanvasTool.select => _SelectionSettings(
      state: state,
      onChanged: onChanged,
      maskOptions: selectionMaskOptions,
      onMaskOptionsChanged: onSelectionMaskOptionsChanged,
      selectionCommands: selectionCommands,
      traces: canvasTraces,
      pasteboard: pasteboard,
      language: language,
    ),
    // The CUT grab: 「원본 삭제」 and the polygon's confirm, whatever shape
    // it is wearing — and nothing of a selection's (see the class).
    CanvasTool.cut => _CutGrabSettings(
      state: state,
      onChanged: onChanged,
      traces: canvasTraces,
    ),
    CanvasTool.cutStamp => _CutStampSettings(
      slot: cutPieceSlot,
      onPasteAtOrigin: onCutPasteAtOrigin,
      onRegisterAsTip: onRegisterCutPieceAsTip,
    ),
    CanvasTool.move => _MoveSettings(
      selectionCommands: selectionCommands,
      options: transformOptions,
      onOptionsChanged: onTransformOptionsChanged,
    ),
    CanvasTool.text => TextToolSettings(
      options: textOptions,
      commands: textCommands,
      // The brush's colour, for the colour window's 「현재 색 반영」.
      currentColorOf: () => state.color,
      fonts: textFonts,
    ),
    // Guides get their knobs HERE, like every other tool. There is no
    // guide panel of its own.
    CanvasTool.guide => GuideSettings(
      guides: guides ?? CutGuides.empty,
      selectedGuideId: selectedGuideId,
      canvasSize: pasteboard?.canvas,
      onGuidesCommitted: onGuidesCommitted ?? (_) {},
      onGuidesPreview: onGuidesPreview ?? (_) {},
      onGuideRasterized: onGuideRasterized,
    ),
  };
}

/// The SHAPE FILL tile's knobs.
///
/// Short on purpose. A drawn outline is filled whatever is inside it (유저
/// 확정: 올가미 채우기는 A), so nothing here reads the picture — the
/// bucket's tolerance, gap close and pasteboard boundary have no question
/// to answer. What remains is the edge, which both tiles share because
/// both end in a coverage mask.
class _ShapeFillSettings extends StatelessWidget {
  const _ShapeFillSettings({
    required this.options,
    required this.onChanged,
    required this.shapeKind,
    required this.traces,
  });

  final FloodFillOptions options;
  final ValueChanged<FloodFillOptions> onChanged;
  final CanvasShapeKind? shapeKind;
  final CanvasTraces? traces;

  @override
  Widget build(BuildContext context) {
    return ToolSettingsSection(
      tool: 'fill-shape',
      title: AppText.strings.toolShapeFill,
      children: [
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('fill-shape-anti-alias-switch'),
          label: AppText.strings.brAntiAlias,
          value: options.antiAlias,
          onChanged: (value) => onChanged(options.copyWith(antiAlias: value)),
        ),
        ToolSettingActions(lines: _closePolygonLine(shapeKind, traces)),
      ],
    );
  }
}

/// The SHAPE tool's settings (I-69, 유저 답 Q1 · Q5 · Q7 · Q8 · Q9 —
/// 2026-10-08).
///
/// 🗣️F-478-Q1 (유저 2026-10-27): 「없앤다 — 그 모양 · 모드에 필요할 때만
/// 있다」 — 「그리기」 stands only under a tile with an inside to fill. Under
/// the line tile there is nothing to choose: the line is what is laid,
/// whatever was chosen for the other shapes. ↩️It kept its place there with
/// 「채움」 refused (「없다가 생기는 UI 금지」).
///
/// The rest keep their place and lose their tap where what is chosen IN
/// this panel leaves them nothing to say — whether they go too is
/// F-478-Q2's question, not this law's:
///
/// - 「채움」 has no line, so the type and the corners are off (Q9: 「채움은
///   타입과 무관하다」);
/// - the corners are the PLAIN line's (Q8), and so is the edge switch —
///   with the fill's. A line of the brush type has the brush's own edge.
///
/// ⛔No size and no opacity here: those are the strip's for every tool
/// (`BrushToolState.activeSize`, `activeOpacity`).
class _ShapeToolSettings extends StatelessWidget {
  const _ShapeToolSettings({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  void _set(ShapeToolOptions options) =>
      onChanged(state.copyWith(shapeOptions: options));

  ShapeToolOptions get _options => state.shapeOptions;

  /// Whether what is chosen lays a LINE — and whether that line is the
  /// tool's own plain one.
  bool get _laysLine => state.shapePart == ShapePart.line;
  bool get _laysPlainLine => _laysLine && _options.type == ShapeLineType.plain;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return ToolSettingsSection(
      tool: 'shape',
      title: strings.toolShape,
      children: [
        if (canvasShapeEncloses(state.drawShape)) _partRow(strings),
        _typeRow(strings),
        _cornersRow(strings),
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('shape-tool-anti-alias-switch'),
          label: strings.brAntiAlias,
          value: _options.antiAlias,
          onChanged: state.shapeDrawsWithTheBrush
              ? null
              : (value) => _set(_options.copyWith(antiAlias: value)),
        ),
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('shape-tool-ratio-lock-switch'),
          label: strings.shapeToolRatioLock,
          value: _options.ratioLock,
          onChanged: (value) => _set(_options.copyWith(ratioLock: value)),
        ),
      ],
    );
  }

  /// 「그리기」: the line, or the inside — asked only under a tile with an
  /// inside (see the class).
  Widget _partRow(AppStrings strings) => ToolSettingChoiceRow<ShapePart>(
    tool: 'shape-tool',
    name: 'part',
    label: strings.shapeToolDraws,
    current: state.shapePart,
    answers: [
      (value: ShapePart.line, key: 'line', label: strings.shapeToolStroke),
      (value: ShapePart.fill, key: 'fill', label: strings.shapeToolFill),
    ],
    onPick: (part) => () => _set(_options.copyWith(part: part)),
  );

  /// 「타입」: what lays the line — it takes a press only where a line is
  /// laid.
  Widget _typeRow(AppStrings strings) => ToolSettingChoiceRow<ShapeLineType>(
    tool: 'shape-tool',
    name: 'type',
    label: strings.shapeToolType,
    current: _options.type,
    answers: [
      (value: ShapeLineType.brush, key: 'brush', label: strings.toolBrush),
      (
        value: ShapeLineType.plain,
        key: 'plain',
        label: strings.shapeToolTypePlain,
      ),
    ],
    onPick: (type) =>
        _laysLine ? () => _set(_options.copyWith(type: type)) : null,
  );

  /// 「모서리」: the plain line's alone.
  Widget _cornersRow(AppStrings strings) => ToolSettingChoiceRow<ShapeCorners>(
    tool: 'shape-tool',
    name: 'corners',
    label: strings.shapeToolCorners,
    current: _options.corners,
    answers: [
      (
        value: ShapeCorners.sharp,
        key: 'sharp',
        label: strings.shapeToolCornersSharp,
      ),
      (
        value: ShapeCorners.round,
        key: 'round',
        label: strings.shapeToolCornersRound,
      ),
    ],
    onPick: (corners) => _laysPlainLine
        ? () => _set(_options.copyWith(corners: corners))
        : null,
  );
}

/// The CUT grab's knobs: 「원본 삭제」, and the polygon's confirm, which
/// every drag-out verb needs while a trace is open.
///
/// 🗣️I-90 (유저 2026-10-10): 「올가미잘라내기등 잘라내는 서브도구의
/// 도구설정으로서 원본 삭제 불리언버튼 추가」 — one switch for every outline
/// the grab drags, and for 전체 잘라내기 ([BrushToolState.cutDeletesSource]).
///
/// ↩️「The two GRAB tiles have nothing to set」 stood here until then, and
/// its reasons still hold for everything else: the grab makes no selection,
/// so there is no combine mode to offer, and its mask is hard-edged by law
/// (2치 보존) rather than by a default someone could nudge. The soft-edge
/// knobs that would otherwise belong here already live on the Select tool.
class _CutGrabSettings extends StatelessWidget {
  const _CutGrabSettings({
    required this.state,
    required this.onChanged,
    required this.traces,
  });

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;
  final CanvasTraces? traces;

  @override
  Widget build(BuildContext context) {
    return ToolSettingsSection(
      tool: 'cut-grab',
      scrolls: false,
      children: [
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('cut-deletes-source-switch'),
          label: AppText.strings.toolCutDeletesSource,
          value: state.cutDeletesSource,
          onChanged: (value) =>
              onChanged(state.copyWith(cutDeletesSource: value)),
        ),
        ToolSettingActions(
          lines: _closePolygonLine(state.activeShapeKind, traces),
        ),
      ],
    );
  }
}

/// The line of [ToolSettingActions] the polygon's confirm stands on — none
/// while another shape is in hand ([_ClosePolygonButton]).
List<List<Widget>> _closePolygonLine(
  CanvasShapeKind? shapeKind,
  CanvasTraces? traces,
) => [
  if (shapeKind == CanvasShapeKind.polygon)
    [_ClosePolygonButton(traces: traces)],
];

/// The polygon's confirm, for hands with no Enter key — an ACTION of the
/// tools that trace one ([ToolSettingActions]).
///
/// It bites only once three vertices are down — a button offering to close
/// nothing would be lying about what a tap does.
///
/// 🗣️F-478-Q1 (유저 2026-10-27): 「없앤다 — 그 모양 · 모드에 필요할 때만
/// 있다」 — it stands only while the polygon is the shape in hand
/// ([_closePolygonLine]): 「도형닫기가 필요없는 사각형 타원 올가미 전체등은
/// 해당 버튼 삭제」 · 「선택 도구의 도형 닫기도 다각형 선택만 쓸것임」 ·
/// 「채우기 도구도 도형 닫기 버튼 마찬가지」. ↩️It kept its place and dimmed
/// under the other shapes (tool-settings-panel-tidy, 유저 2026-10-10 「자리를
/// 늘 두고 아닐 때는 흐리게」), and before that rendered nothing for them.
///
/// It is 확정's polygon half (`ConfirmVerb` closes an open outline before
/// anything else it might confirm — 유저 확정 「폴리곤 확정은 확정 버튼으로」),
/// so it names 확정 rather than an action of its own (I-40): Enter is its
/// key.
class _ClosePolygonButton extends StatelessWidget {
  const _ClosePolygonButton({required this.traces});

  final CanvasTraces? traces;

  Widget _button(VoidCallback? close) => ToolSettingAction(
    keyValue: 'selection-close-polygon-button',
    label: AppText.strings.selectionClosePolygon,
    shortcuts: const [EditorActionIds.confirm],
    onPressed: close,
  );

  @override
  Widget build(BuildContext context) {
    final traces = this.traces;
    if (traces == null) {
      return _button(null);
    }
    return ListenableBuilder(
      listenable: traces.changes,
      builder: (context, _) {
        final trace = traces.open;
        return _button(
          trace != null && trace.canClosePolygon ? trace.closePolygon : null,
        );
      },
    );
  }
}

/// The STAMP tile's knobs.
///
/// Deliberately short: spacing, jitter and the rest of the brush
/// parameters are NOT here (유저 확정 — "스페이싱 같은 거 없애고 … 그건 그냥
/// 팁으로 등록해서 뭐 할 때만 띄우는 게 낫겠다"). The law that falls out is
/// **a held piece stays simple, brush parameters belong to a registered
/// tip** — the same split Photoshop draws between a clipboard piece and a
/// Define Brush Preset.
class _CutStampSettings extends StatelessWidget {
  const _CutStampSettings({
    required this.slot,
    required this.onPasteAtOrigin,
    required this.onRegisterAsTip,
  });

  final CutPieceSlot? slot;

  /// Drop the held piece back where it was cut from. ONE button (TS8): the
  /// pair that used to say Above/Below was spelling a COMPOSITE ORDER, and
  /// that is what the blend control says now — 유저 확정, *"합성순서는
  /// 블렌드가 정함. 제자리붙여넣기는 개별로 존재."*
  final VoidCallback? onPasteAtOrigin;
  final VoidCallback? onRegisterAsTip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final holder = slot;
    if (holder == null) {
      // ⚠️Still wearing the section's key: the panel has nothing to show for
      // a host that owns no cut slot, and a section that renders nothing has
      // to be findable saying so.
      return SizedBox.shrink(key: ToolSettingsSection.keyFor('cut-stamp'));
    }
    return ListenableBuilder(
      listenable: holder,
      builder: (context, _) {
        final piece = holder.piece;
        if (piece == null) {
          return ToolSettingsSection(
            tool: 'cut-stamp',
            scrolls: false,
            children: [
              EmptyStateText(
                AppText.strings.toolCutNothingHeld,
                place: EmptyStatePlace.list,
              ),
            ],
          );
        }
        final reset = piece.isPosed ? holder.resetPose : null;
        final section = ToolSettingsSection(
          tool: 'cut-stamp',
          children: [
            Padding(
              padding: const EdgeInsets.only(
                bottom: ToolSettingsSection.rowGap,
              ),
              child: Text(
                AppText.strings.toolCutHoldingTemplate.replaceAll(
                  '{size}',
                  pixelSizeLabel(piece.image.width, piece.image.height),
                ),
                key: const ValueKey<String>('cut-stamp-holding'),
                style: theme.textTheme.labelMedium,
              ),
            ),
            // 🪦A copy of this preview stood here in its own 88-tall box —
            // I-33 moved it to the panel's one slot, where it is pinned
            // instead of scrolling away with the knobs.
            //
            // Flip is a flag applied at stamp time, never baked into the
            // held bytes: baking would destroy the original, and flipping
            // is a byte re-order that keeps the 1:1 contract intact.
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('cut-flip-horizontal-switch'),
              label: AppText.strings.toolCutFlipHorizontal,
              value: piece.flipHorizontal,
              onChanged: (value) => holder.updatePose(flipHorizontal: value),
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('cut-flip-vertical-switch'),
              label: AppText.strings.toolCutFlipVertical,
              value: piece.flipVertical,
              onChanged: (value) => holder.updatePose(flipVertical: value),
            ),
            // Percent, not pixels: with pixels "original" is 300 for one
            // piece and 40 for the next, so the number would have to be
            // remembered. And NOT the top strip's brush size — sharing it
            // would multiply the piece by whatever pen width was last
            // used, the same failure the locked 100% opacity avoids.
            ToolSettingRow.bar(
              label: AppText.strings.brSize,
              bar: FieldSlider.cell(
                key: const ValueKey<String>('cut-scale-slider'),
                label: AppText.strings.brSize,
                min: CutPiece.minScalePercent.toDouble(),
                max: 400,
                divisions: 400 - CutPiece.minScalePercent,
                value: piece.scalePercent.clamp(1, 400).toDouble(),
                unit: '%',
                onChanged: (value) =>
                    holder.updatePose(scalePercent: value.round()),
              ),
            ),
            // ↩️The paste stood under the name of the piece, and the reset
            // and the registration in a row of their own under the size —
            // three outlined buttons in two places. They are the tool's
            // actions (tool-settings-panel-tidy, 유저 2026-10-10 「다
            // 추천대로」), the paste's name too long to share its line.
            ToolSettingActions(
              lines: [
                [
                  // ONE button, and the strip's blend decides whether the
                  // pixels land over what is there or under it (TS8). The
                  // two buttons this replaced were `color` and `behind`
                  // under other names — the same two entries the blend list
                  // has always carried.
                  ToolSettingAction(
                    keyValue: 'cut-paste-at-origin-button',
                    label: AppText.strings.toolCutPasteAtOrigin,
                    shortcuts: const [EditorActionIds.cutStampPasteAtOrigin],
                    onPressed: onPasteAtOrigin,
                  ),
                ],
                [
                  // Reset clears size AND both flips, which is why there is
                  // no separate "original size" button: those two knobs are
                  // everything this panel poses.
                  ToolSettingAction(
                    keyValue: 'cut-reset-button',
                    label: AppText.strings.commonReset,
                    shortcuts: const [EditorActionIds.cutStampReset],
                    onPressed: reset,
                  ),
                  ToolSettingAction(
                    keyValue: 'cut-register-tip-button',
                    label: AppText.strings.toolCutRegisterTip,
                    shortcuts: const [EditorActionIds.cutStampRegisterTip],
                    onPressed: onRegisterAsTip,
                  ),
                ],
              ],
            ),
          ],
        );
        // A key presses the three as the stamp's settings (I-40) while a
        // piece is held: with none they are not here, and a key has
        // nothing to press.
        return PanelKeysBinding(
          tool: CanvasTool.cutStamp,
          buttons: {
            EditorActionIds.cutStampPasteAtOrigin: onPasteAtOrigin,
            EditorActionIds.cutStampReset: reset,
            EditorActionIds.cutStampRegisterTip: onRegisterAsTip,
          },
          child: section,
        );
      },
    );
  }
}

/// R17-U: the selection VARIANT is a setting of the single Select tool.
/// R26 (C2): plus the lift-time mask knobs — grow/shrink, inward
/// feather, edge AA. Defaults keep the lift byte-preserving.
class _SelectionSettings extends StatelessWidget {
  const _SelectionSettings({
    required this.state,
    required this.onChanged,
    required this.maskOptions,
    required this.onMaskOptionsChanged,
    required this.selectionCommands,
    required this.traces,
    required this.pasteboard,
    required this.language,
  });

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;
  final SelectionMaskOptions maskOptions;
  final ValueChanged<SelectionMaskOptions>? onMaskOptionsChanged;
  final CanvasSelectionCommands? selectionCommands;
  final CanvasTraces? traces;
  final PasteboardWall? pasteboard;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final onMask = onMaskOptionsChanged;
    final commands = selectionCommands;
    final wall = pasteboard;
    VoidCallback? invert(InvertReach reach) =>
        commands == null || wall == null
        ? null
        : () => commands.invertSelection(pasteboard: wall, reach: reach);
    // R26 #12: the rectangle/lasso CHOICE lives in the tool library
    // (two tools there), so the settings panel no longer duplicates
    // it — only the mask knobs remain.
    return ToolSettingsSection(
      tool: 'selection',
      title: AppText.strings.toolSelect,
      children: [
        // R26 #16: 갱신 / 추가 / 삭제 / 선택중 — how the next drag folds
        // into the region already selected. Default 추가 (유저 원문).
        if (commands != null)
          ListenableBuilder(
            listenable: commands,
            builder: (context, _) => _SelectionModeRow(
              mode: commands.combineMode,
              language: language,
              onChanged: (mode) => commands.combineMode = mode,
            ),
          ),
        if (onMask != null) ...[
          ToolSettingRow.bar(
            label: AppText.strings.brGrowShrink,
            bar: FieldSlider.cell(
              key: const ValueKey<String>('selection-grow-slider'),
              min: -20,
              max: 20,
              divisions: 40,
              value: maskOptions.growPx.toDouble().clamp(-20, 20),
              label: AppText.strings.brGrowShrink,
              unit: ' px',
              valueTextBuilder: (grow, derived) => grow == 0
                  ? 'off'
                  : '${grow > 0 ? '+' : ''}$derived',
              onChanged: (value) =>
                  onMask(maskOptions.copyWith(growPx: value.round())),
            ),
          ),
          ToolSettingRow.bar(
            label: AppText.strings.brFeather,
            bar: FieldSlider.cell(
              key: const ValueKey<String>('selection-feather-slider'),
              min: 0,
              max: 50,
              divisions: 50,
              value: maskOptions.featherPx.clamp(0, 50),
              label: AppText.strings.brFeather,
              unit: ' px',
              valueTextBuilder: (feather, derived) =>
                  feather <= 0 ? 'off' : derived,
              onChanged: (value) => onMask(
                maskOptions.copyWith(featherPx: value.roundToDouble()),
              ),
            ),
          ),
          SettingsSwitchRow(
            tileKey: const ValueKey<String>('selection-anti-alias-switch'),
            label: AppText.strings.brAntiAlias,
            value: maskOptions.antiAlias,
            onChanged: (value) =>
                onMask(maskOptions.copyWith(antiAlias: value)),
          ),
        ],
        ToolSettingActions(
          lines: [
            ..._closePolygonLine(state.activeShapeKind, traces),
            // 선택 반전 — 유저 2026-09-12 (I-23): 「선택반전기능 … 위치는
            // 선택툴일때의 툴설정. 버튼.」 In its place whatever is selected
            // (with nothing selected it selects the whole wall), and greyed
            // — never gone — when there is no canvas to take the wall from.
            // Each key answers under every tool, in the shell (I-40-Q8), and
            // runs this same verb. Two walls, two buttons (I-108), each on a
            // line of its own — ⚠️my call: their names are long, and a
            // shared line would cut them.
            if (commands != null) ...[
              [
                ToolSettingAction(
                  keyValue: 'selection-invert-in-canvas-button',
                  label: AppText.strings.selectionInvertInCanvas,
                  shortcuts: const [EditorActionIds.selectionInvertInCanvas],
                  onPressed: invert(InvertReach.canvas),
                ),
              ],
              [
                ToolSettingAction(
                  keyValue: 'selection-invert-button',
                  label: AppText.strings.selectionInvert,
                  shortcuts: const [EditorActionIds.selectionInvert],
                  onPressed: invert(InvertReach.pasteboard),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}

/// R26 #16: the four selection modes as one segmented row — the same
/// "selection shows in COLOR only" rule the rest of the app follows
/// ([[ui-selection-style]]: no check marks).
class _SelectionModeRow extends StatelessWidget {
  const _SelectionModeRow({
    required this.mode,
    required this.language,
    required this.onChanged,
  });

  final SelectionCombineMode mode;
  final AppLanguage language;
  final ValueChanged<SelectionCombineMode> onChanged;

  static const Map<SelectionCombineMode, IconData> _icons = {
    SelectionCombineMode.replace: Icons.crop_square,
    SelectionCombineMode.add: Icons.add_box_outlined,
    SelectionCombineMode.subtract: Icons.indeterminate_check_box_outlined,
    SelectionCombineMode.intersect: Icons.join_inner,
  };

  /// A CHOICE like every other setting's: the four share the control
  /// column as the app's one grouped choice ([PillStrip.even]), each drawn
  /// as its glyph and named by its tooltip. ↩️It was the four alone at the
  /// tool RAIL's 42px square, then four icon buttons at the row's end (유저
  /// 2026-10-10: 「사각형 박스 크기가 다 달라서 정돈된느낌 하나도안들어」).
  @override
  Widget build(BuildContext context) {
    return ToolSettingRow(
      label: AppText.strings.toolSelectionMode,
      child: PillStrip.even(
        key: const ValueKey<String>('selection-mode-row'),
        items: [
          for (final candidate in SelectionCombineMode.values)
            PillItem(
              keyValue: 'selection-mode-${candidate.name}',
              label: candidate.labelFor(language),
              icon: _icons[candidate],
              selected: candidate == mode,
              onTap: () => onChanged(candidate),
            ),
        ],
      ),
    );
  }
}

/// One of the transform box's values as the tool settings show it: how it
/// is read off the values, how another is put in its place, and what the
/// readout calls it.
class _BoxValue {
  const _BoxValue({
    required this.read,
    required this.write,
    this.unit = '',
    this.perUnit = 1,
  });

  final double Function(TransformValues values) read;

  /// [now] with this value replaced — and nothing else restated.
  final TransformValues Function(TransformValues now, double value) write;

  final String unit;

  /// What one unit of the readout is worth in the value: a scale is held
  /// as a ratio and read as a percentage.
  final double perUnit;

  String shown(TransformValues values) =>
      '${columnValueText(read(values) / perUnit)}'
      '$unit';
}

/// The Move/Transform tool's numeric inputs (R17-U 유저 채택 설계:
/// 좌표/각도 수치 입력): the LIVE transform box's move, angle, scales and
/// anchor, each written through the selection channel as it is scrubbed or
/// typed. The channel notifies on session changes so the fields track
/// handle drags.
class _MoveSettings extends StatefulWidget {
  const _MoveSettings({
    required this.selectionCommands,
    required this.options,
    required this.onOptionsChanged,
  });

  final CanvasSelectionCommands? selectionCommands;

  /// The transform tool's knobs. A null handler shows them disabled — the
  /// convention the eyedropper's source picker uses for hosts that do not
  /// own the setting.
  final TransformToolOptions options;
  final ValueChanged<TransformToolOptions>? onOptionsChanged;

  @override
  State<_MoveSettings> createState() => _MoveSettingsState();
}

class _MoveSettingsState extends State<_MoveSettings> {
  /// What the box holds, as the session last said — the digits at rest.
  ///
  /// ↩️It was six doubles of this panel's own, one per channel, that a
  /// scrub added to and then wrote back ALL of (R26 #14, so that the
  /// deferred session ping could not eat drag steps). Its copy of the scale
  /// was one number, so a scrub on X restated a scale the box did not have
  /// (F-265 · F-256). A channel adds to what the box holds NOW instead
  /// ([_write]), which has no step for a late ping to eat.
  TransformValues _values = TransformValues.identity;

  /// The most a typed or scrubbed scale reaches, as a ratio (3200%).
  static const double _scaleCeiling = 32;

  @override
  void initState() {
    super.initState();
    widget.selectionCommands?.addListener(_syncFromSession);
    _syncFromSession();
  }

  @override
  void didUpdateWidget(covariant _MoveSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (rebindListener(
      oldWidget.selectionCommands,
      widget.selectionCommands,
      _syncFromSession,
    )) {
      _syncFromSession();
    }
  }

  @override
  void dispose() {
    widget.selectionCommands?.removeListener(_syncFromSession);
    super.dispose();
  }

  void _syncFromSession() {
    if (!mounted) {
      return;
    }
    setState(() {
      _values =
          widget.selectionCommands?.transformValues ??
          TransformValues.identity;
    });
  }

  /// One channel's write through the selection channel: [change] is handed
  /// what the box holds NOW and names the one value it means
  /// ([CanvasSelectionCommands.editTransformValues]). With no session open
  /// this OPENS one (Ctrl+T semantics; R26 #13: with no selection the box
  /// opens on the whole picture).
  void _write(TransformValues Function(TransformValues now) change) =>
      widget.selectionCommands?.editTransformValues(change);

  /// A typed or scrubbed scale as the box keeps one: off zero WITH ITS
  /// SIGN — the law a dragged handle keeps ([TransformBoxLaw.clampScale]),
  /// so a number taken through zero mirrors as a handle taken through the
  /// centre does — and under this panel's ceiling.
  static double _scaleWithin(double ratio) {
    final kept = TransformBoxLaw.clampScale(ratio);
    return kept.abs() > _scaleCeiling ? _scaleCeiling * kept.sign : kept;
  }

  /// What a scale row's write leaves in the box: linked, the write carried
  /// the other axis along, and what it was carried to is held to
  /// [_scaleWithin] like any scale the box keeps.
  ///
  /// ⛔Unlinked, the other axis is NOT restated — not even to clamp it. A
  /// row names its own value and no other ([_write]); a handle can leave a
  /// scale past this panel's ceiling, and a number typed beside it must not
  /// pull it back.
  TransformValues _linkedWithin(TransformValues written) =>
      widget.options.scaleLinked
      ? written.copyWith(
          sx: _scaleWithin(written.sx),
          sy: _scaleWithin(written.sy),
        )
      : written;

  /// One of the box's values as a NUMBER BOX ([DragValueLabel.box]): a
  /// scrub adds to what the box holds now, a typed number replaces it, and
  /// neither names another value.
  ///
  /// 🚨★★★**THE DIGITS, LIVE — and ONLY the digits.**
  ///
  /// 🗣️유저 2026-09-18 (F-164): 「변형중에 툴도구의 X,Y값같은거 **실시간
  /// 으로 바뀌게**해주고. **무겁지 않을 구조로 패널리빌드하지말고 글자만
  /// 바꾸게**」.
  ///
  /// The number comes from [CanvasSelectionCommands.liveTransformValues]
  /// through a `ValueListenableBuilder`, so a transform drag repaints one box
  /// and nothing above it. ⛔The alternative — this panel's own `setState` on
  /// the channel's ping — rebuilds every row of every section on every
  /// pointer sample, which is the one thing the user ruled out in the same
  /// sentence they asked for the numbers.
  Widget _valueBox({
    required String keyValue,
    String? name,
    required _BoxValue value,
  }) {
    Widget box(TransformValues values) => DragValueLabel.box(
      keyValue: keyValue,
      name: name,
      text: value.shown(values),
      onDragDelta: (units) => _write(
        (now) => value.write(now, value.read(now) + units * value.perUnit),
      ),
      // 🚨★★★**ONE SCRUB IS ONE STEP BACK** (유저 2026-09-20: 「변형에 대한
      // **조작마다** 언두로 기록」). A scrub is forty writes and one
      // operation; the canvas takes its own step when a press lands, and
      // this is the same announcement from the other entrance.
      onOperationStart: widget.selectionCommands?.beginTransformStep,
      onEditSubmit: (raw) {
        final typed = columnValueOf(raw);
        if (typed != null) {
          _write((now) => value.write(now, typed * value.perUnit));
        }
      },
    );
    final notifier = widget.selectionCommands?.liveTransformValues;
    return notifier == null
        ? box(_values)
        : ValueListenableBuilder<TransformValues?>(
            valueListenable: notifier,
            builder: (context, values, _) => box(values ?? _values),
          );
  }

  /// The mesh grid's cell count on one axis, as a number box.
  Widget _meshBox({
    required String keyValue,
    required String name,
    required int value,
    required bool live,
    required ValueChanged<int> onChanged,
  }) => DragValueLabel.box(
    keyValue: keyValue,
    name: name,
    text: '$value',
    enabled: live,
    onDragDelta: (units) => onChanged(
      TransformToolOptions.clampMeshCells(value + units.round()),
    ),
    onEditSubmit: (raw) {
      final typed = columnValueOf(raw);
      if (typed != null) {
        onChanged(TransformToolOptions.clampMeshCells(typed.round()));
      }
    },
  );

  /// 🗣️tool-settings-panel-tidy (유저 2026-10-10, 「다 추천대로」): the
  /// values in ROWS AND COLUMNS — 위치 · 배율 · 회전 · 기준점 · 메시 — the
  /// scale's link as the chain beside 「배율」, and 초기화 · 적용 as the last
  /// line ([ToolSettingActions]). ONE VALUE A LINE, its hands where a bar's
  /// stand ([ToolSettingRow.bar]): X on the name's line, Y under it, and the
  /// flips a line of their own under 회전, half the control column each.
  /// 🗣️유저 2026-10-10: 「상자에 한걸음 올리기 내리기버튼들도 동일하게
  /// 넣고싶어 … 공간 꽤 많이필요하니까 그냥 열당 하나. x만두고 다음열에 y두고」.
  /// ↩️It was a list of nine name-and-number lines with the link's switch
  /// row between them and its four buttons folding onto two lines under
  /// them; then X beside Y, a pair a row, the flips in the rotation row's
  /// second cell — until each value took its ± and its pencil.
  @override
  Widget build(BuildContext context) {
    // The one gate for the whole panel. Choosing the tool is always
    // allowed now; it is the EDIT that is refused, and it is refused
    // quietly — flat controls rather than a notice per press (유저 08-13).
    final canEdit = widget.selectionCommands?.canEditTransform ?? false;
    final options = widget.options;
    final onOptions = canEdit ? widget.onOptionsChanged : null;
    final commands = widget.selectionCommands;
    final strings = AppText.strings;
    // The mesh's density, shown as numbers because that is what it is
    // (유저 08-13: "수치도 조절가능하게 값으로 드러내고"). 🗣️F-478-Q1 (유저
    // 2026-10-27): 「변형도구의 툴설정의 메시도 마찬가지」 — its rows stand
    // in 메쉬 alone; a grid size means nothing to the other two modes.
    // ↩️They kept their place and dimmed there (tool-settings-panel-tidy,
    // 10-10 — 「없다가 생기는 UI」), and before that were only there in 메쉬.
    //
    // ⚠️「메시워프에서도 일반변형등에서만 쓰는거 있으면 삭제하고」: nothing
    // else here is 일반's alone. 위치 · 배율 · 회전 · 반전 · 기준점 move the
    // box, and the box carries the mesh and the quad with it — each of
    // their points is laid through its affine (`FloatWarp._placedPoints`).
    final meshHandler = widget.onOptionsChanged;
    final inMesh = options.mode == TransformMode.mesh;
    final flipHorizontal = canEdit
        ? () => commands?.flipTransform(horizontal: true)
        : null;
    final flipVertical = canEdit
        ? () => commands?.flipTransform(horizontal: false)
        : null;
    final reset = canEdit ? () => commands?.resetTransform() : null;
    final section = ToolSettingsFolds.listen(
      'move',
      (foldOf) => ToolSettingsSection(
        tool: 'move',
        title: strings.toolTransform,
        children: [
          ToolSettingRow.bar(
            label: strings.trPosition,
            bar: _valueBox(
              keyValue: 'move-x-field',
              name: 'X',
              value: _BoxValue(
                read: (values) => values.tx,
                write: (now, tx) => now.copyWith(tx: tx),
              ),
            ),
          ),
          ToolSettingRow.bar(
            label: '',
            bar: _valueBox(
              keyValue: 'move-y-field',
              name: 'Y',
              value: _BoxValue(
                read: (values) => values.ty,
                write: (now, ty) => now.copyWith(ty: ty),
              ),
            ),
          ),
          // 🚨★★★**A SCALE PER AXIS, EACH WITH ITS SIGN** (F-256 · F-265).
          // 🗣️유저 2026-10-01: 「가로에 대한 단독배율변경같은게 저장안됨.
          // 가로세로 통합으로서 … 기록됨」 — and 10-03: 「반전을 숫자로서
          // 표현못하는게 원인인거같으니 구조적으로 해결」. The box has always
          // held two; this row showed the horizontal one as 「배율」 and
          // wrote it to both. An edge middle's stretch reads on its own
          // box now, and a mirror reads as the minus it is.
          //
          // 🗣️F-256-Q2 (유저 2026-10-06): 「연동 스위치(AE 의 사슬) — 켜면 한
          // 칸을 바꿀 때 다른 칸도 같은 비율로」. Each box still names its own
          // axis; linked, the write carries the other along by the same
          // ratio and leaves its sign alone (`TransformValues.withScaleX`).
          ToolSettingRow.bar(
            label: strings.trScale,
            labelEnd: ScaleChainButton(
              keyValue: 'move-scale-link-switch',
              isOn: options.scaleLinked,
              onPressed: onOptions == null
                  ? null
                  : () => onOptions(
                      options.copyWith(scaleLinked: !options.scaleLinked),
                    ),
            ),
            bar: _valueBox(
              keyValue: 'move-scale-x-field',
              name: 'X',
              value: _BoxValue(
                read: (values) => values.sx,
                write: (now, sx) => _linkedWithin(
                  now.withScaleX(
                    _scaleWithin(sx),
                    linked: options.scaleLinked,
                  ),
                ),
                unit: '%',
                perUnit: 0.01,
              ),
            ),
          ),
          ToolSettingRow.bar(
            label: '',
            bar: _valueBox(
              keyValue: 'move-scale-y-field',
              name: 'Y',
              value: _BoxValue(
                read: (values) => values.sy,
                write: (now, sy) => _linkedWithin(
                  now.withScaleY(
                    _scaleWithin(sy),
                    linked: options.scaleLinked,
                  ),
                ),
                unit: '%',
                perUnit: 0.01,
              ),
            ),
          ),
          ToolSettingRow.bar(
            label: strings.trRotation,
            bar: _valueBox(
              keyValue: 'move-angle-field',
              value: _BoxValue(
                read: (values) => values.rotationDegrees,
                write: (now, degrees) =>
                    now.copyWith(rotationDegrees: degrees),
                unit: '°',
              ),
            ),
          ),
          // ↩️유저 08-13 put them in a row of their own, in this order:
          // 좌우반전 · 상하반전 · 리셋 · 적용. The two flips turn the box the
          // way the angle does, so they stand under it — in the view pill's
          // own glyphs, half the control column each (유저 2026-10-10).
          ToolSettingRow.pair(
            label: '',
            first: ToolSettingAction.glyph(
              keyValue: 'move-flip-horizontal-button',
              label: strings.trFlipHorizontal,
              glyph: const Icon(Icons.flip),
              shortcuts: const [EditorActionIds.transformFlipHorizontal],
              onPressed: flipHorizontal,
            ),
            second: ToolSettingAction.glyph(
              keyValue: 'move-flip-vertical-button',
              label: strings.trFlipVertical,
              glyph: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
              shortcuts: const [EditorActionIds.transformFlipVertical],
              onPressed: flipVertical,
            ),
          ),
          // 🗣️유저 2026-09-20: 「앵커포인트 … **툴설정에도 존재하겟고**」 —
          // beside the other digits, and written the way they are: each
          // box names its own value and restates none ([_write]).
          //
          // ⚠️Always here, never mode-gated: the rotation the anchor
          // serves works in every mode (outside the box is the rotation),
          // so a row that appeared and vanished would be inventing a rule
          // the rotation does not have — and 「없다가 생기는 UI 금지」
          // besides.
          ToolSettingRow.bar(
            label: strings.trAnchorPoint,
            bar: _valueBox(
              keyValue: 'move-anchor-x-field',
              name: 'X',
              value: _BoxValue(
                read: (values) => values.anchorX,
                write: (now, anchorX) => now.copyWith(anchorX: anchorX),
              ),
            ),
          ),
          ToolSettingRow.bar(
            label: '',
            bar: _valueBox(
              keyValue: 'move-anchor-y-field',
              name: 'Y',
              value: _BoxValue(
                read: (values) => values.anchorY,
                write: (now, anchorY) => now.copyWith(anchorY: anchorY),
              ),
            ),
          ),
          if (inMesh) ...[
            ToolSettingRow.bar(
              label: strings.trMesh,
              bar: _meshBox(
                keyValue: 'move-mesh-columns-field',
                name: strings.trMeshColumns,
                value: options.meshColumns,
                live: meshHandler != null,
                onChanged: (cells) =>
                    meshHandler?.call(options.copyWith(meshColumns: cells)),
              ),
            ),
            ToolSettingRow.bar(
              label: '',
              bar: _meshBox(
                keyValue: 'move-mesh-rows-field',
                name: strings.trMeshRows,
                value: options.meshRows,
                live: meshHandler != null,
                onChanged: (cells) =>
                    meshHandler?.call(options.copyWith(meshRows: cells)),
              ),
            ),
          ],
          ...toolSettingsGroup(
            strings.trFinish,
            fold: foldOf('finish'),
            rows: [
              // AA, and nothing else.
              //
              // It was "Preserve original colours" over a paragraph about
              // in-between shades, which is the same switch described from the
              // far side: the argmax preserves the source words BECAUSE it
              // refuses to blend, and the blend anti-aliases BECAUSE it does.
              // 유저 08-13 asked for the polarity that goes with it — on is the
              // smoothing default, off is the two-value copy.
              //
              // ↩️And for the two letters, 「AA」 — the one tool whose switch did
              // not say what every other tool's did. 🗣️유저 2026-10-10: 「안티앨리어스는
              // 왜 변형도구만 이름 다른건지도 모르겠고. 안티앨리어스로 이름 다 통일」.
              SettingsSwitchRow(
                tileKey: const ValueKey<String>('move-antialias-switch'),
                label: strings.brAntiAlias,
                value: options.resampleMode == ResampleMode.blend,
                onChanged: onOptions == null
                    ? null
                    : (value) => onOptions(
                        options.copyWith(
                          resampleMode: value
                              ? ResampleMode.blend
                              : ResampleMode.pick,
                        ),
                      ),
              ),
            ],
          ),
          ToolSettingActions(
            lines: [
              [
                ToolSettingAction(
                  keyValue: 'move-reset-button',
                  label: strings.commonReset,
                  shortcuts: const [EditorActionIds.transformReset],
                  onPressed: reset,
                ),
                // 적용 is 확정's transform half (confirm-button) — grey when it
                // has nothing to do, like the rail's ↵ and the box's ✓,
                // because all three ask the one verb — so it names 확정, as
                // they do (I-40).
                ToolSettingAction(
                  keyValue: 'move-apply-button',
                  label: strings.commonApply,
                  decides: true,
                  shortcuts: const [EditorActionIds.confirm],
                  onPressed: commands?.canApplyTransform ?? false
                      ? () => commands?.applyTransform()
                      : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
    // A key presses the flips and 초기화 as the Transform tool's settings
    // (I-40); 적용 is 확정's, whose key reaches it anywhere.
    return PanelKeysBinding(
      tool: CanvasTool.move,
      buttons: {
        EditorActionIds.transformFlipHorizontal: flipHorizontal,
        EditorActionIds.transformFlipVertical: flipVertical,
        EditorActionIds.transformReset: reset,
      },
      child: section,
    );
  }
}

/// R28 #6: the eyedropper's REFERENCE SOURCE — Photoshop's "current
/// layer / all layers", Clip Studio's 참조원. The tool itself works in
/// every section and on every layer kind; this only decides which pixels
/// it reads. A row with nothing drawable (an SE row) simply reads the
/// canvas color, which is what the user described.
class _EyedropperSettings extends StatelessWidget {
  const _EyedropperSettings({
    required this.source,
    required this.onChanged,
    required this.readLayerNames,
  });

  final CanvasReadSource source;
  final ValueChanged<CanvasReadSource>? onChanged;
  final List<String>? readLayerNames;

  @override
  Widget build(BuildContext context) {
    return ToolSettingsSection(
      tool: 'eyedropper',
      title: AppText.strings.toolEyedropper,
      children: [
        _ReadSourceControl(
          tool: 'eyedropper',
          source: source,
          onChanged: onChanged,
          readLayerNames: readLayerNames,
        ),
      ],
    );
  }
}

/// WHAT THE TOOL READS — the eyedropper's 참조 (R28 #6) and the fill's
/// (I-36) as one control: the answers, and a line naming the layers the
/// chosen answer reads right now.
///
/// 🗣️유저 2026-09-24 (I-36-Q1): 「범위를 보여주고」. The line is a READOUT of
/// state, not a caption — it took the place of the eyedropper's sentences
/// about what each segment does. It is always there; only its words change.
/// ↩️The same answer put 「활성 레이어의 참조 버튼」 beside it, and the fill
/// offered a third answer; both went with I-92 (see [_FillSettings]), so
/// the two tools offer the same two.
class _ReadSourceControl extends StatelessWidget {
  const _ReadSourceControl({
    required this.tool,
    required this.source,
    required this.onChanged,
    required this.readLayerNames,
  });

  /// The section's name: `eyedropper` keys `eyedropper-source-segments`.
  final String tool;
  final CanvasReadSource source;
  final ValueChanged<CanvasReadSource>? onChanged;

  /// The layers [source] reads now; null = every visible layer.
  final List<String>? readLayerNames;

  static String _label(CanvasReadSource source) => switch (source) {
    CanvasReadSource.display => AppText.strings.brDisplay,
    CanvasReadSource.layer => AppText.strings.tlLayer,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handler = onChanged;
    final names = readLayerNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selection shows through COLOR only — no check glyphs (the
        // program's selection style).
        //
        // ↩️It stood one answer per line under its name, because three
        // answers side by side folded 「References」 onto four lines
        // (measured, 2026-09-24). It is a choice row like every other now —
        // its name in the name column, the answers sharing the control
        // column, a long word ellipsising (tool-settings-panel-tidy, 유저
        // 2026-10-10: 「채우기 참조는 왜 세로로 버튼이 있는건지도
        // 모르겠고」).
        ToolSettingRow(
          label: AppText.strings.toolReadSource,
          child: PillStrip.even(
            key: ValueKey<String>('$tool-source-segments'),
            items: [
              for (final offer in CanvasReadSource.values)
                PillItem(
                  keyValue: '$tool-source-${offer.name}',
                  label: _label(offer),
                  selected: offer == source,
                  onTap: handler == null ? null : () => handler(offer),
                ),
            ],
          ),
        ),
        // What the answer reads right now, under the answers.
        ToolSettingRow(
          label: '',
          child: Text(
            names == null
                ? AppText.strings.toolReadsEveryVisibleLayer
                : names.isEmpty
                ? '—'
                : names.join(' · '),
            key: ValueKey<String>('$tool-reads'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _FillSettings extends StatelessWidget {
  const _FillSettings({
    required this.options,
    required this.onChanged,
    required this.readLayerNames,
  });

  final FloodFillOptions options;
  final ValueChanged<FloodFillOptions> onChanged;
  final List<String>? readLayerNames;

  @override
  Widget build(BuildContext context) {
    return ToolSettingsSection(
      tool: 'fill',
      title: AppText.strings.toolFill,
      children: [
        // ↩️A third answer, 「References」, read the layers the rail's
        // bucket flagged, and a bucket here flipped the active layer's flag
        // (I-36, 유저 2026-09-24). 유저 2026-10-12 (I-92): 「채우기도구에서
        // 채색참조 기반으로 채우기 이런식으로 구현되있는데, 그런버튼 삭제하고」
        // — the flag is the rail's CLIPPING now, and the fill reads what you
        // see or the layer you are on.
        _ReadSourceControl(
          tool: 'fill',
          source: options.source,
          onChanged: (source) => onChanged(options.copyWith(source: source)),
          readLayerNames: readLayerNames,
        ),
        ToolSettingRow.bar(
          label: AppText.strings.brTolerance,
          bar: FieldSlider.cell(
            key: const ValueKey<String>('fill-tolerance-slider'),
            min: 0,
            max: 128,
            divisions: 128,
            value: options.tolerance.toDouble().clamp(0, 128),
            label: AppText.strings.brTolerance,
            onChanged: (value) =>
                onChanged(options.copyWith(tolerance: value.round())),
          ),
        ),
        ToolSettingRow.bar(
          label: AppText.strings.brExpand,
          bar: FieldSlider.cell(
            key: const ValueKey<String>('fill-expand-slider'),
            min: 0,
            max: 4,
            divisions: 4,
            value: options.expandPx.toDouble().clamp(0, 4),
            label: AppText.strings.brExpand,
            unit: ' px',
            onChanged: (value) =>
                onChanged(options.copyWith(expandPx: value.round())),
          ),
        ),
        ToolSettingRow.bar(
          label: AppText.strings.brGapClose,
          bar: FieldSlider.cell(
            key: const ValueKey<String>('fill-gap-close-slider'),
            min: 0,
            max: 8,
            divisions: 8,
            value: options.gapClosePx.toDouble().clamp(0, 8),
            label: AppText.strings.brGapClose,
            unit: ' px',
            valueTextBuilder: (gap, derived) => gap == 0 ? 'off' : derived,
            onChanged: (value) =>
                onChanged(options.copyWith(gapClosePx: value.round())),
          ),
        ),
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('fill-anti-alias-switch'),
          label: AppText.strings.brAntiAlias,
          value: options.antiAlias,
          onChanged: (value) => onChanged(options.copyWith(antiAlias: value)),
        ),
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('fill-extend-beyond-canvas-switch'),
          label: AppText.strings.brFillBeyondCanvas,
          help: AppText.strings.brOpenRegionsRefuse,
          value: options.extendBeyondCanvas,
          onChanged: (value) =>
              onChanged(options.copyWith(extendBeyondCanvas: value)),
        ),
      ],
    );
  }
}
