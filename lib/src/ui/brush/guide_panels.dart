import 'dart:async';

import '../timeline/layer_label_controls.dart' show LayerVisibilityToggleButton;
import '../widgets/app_icon_button.dart';
import '../widgets/boolean_dot.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/drawing_guide.dart';
import '../../services/guide_geometry.dart' show alongAxis, toggledParallel;
import '../canvas/guide_overlay.dart'
    show GuideHandle, GuideHandleKind, dragGuideHandle, guideColorOf;
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/dialog_verb.dart';
import '../text/app_strings.dart';
import '../text/readout_text.dart' show columnValueOf, columnValueText;
import '../widgets/color_swatch_button.dart';
import '../widgets/content_scrollbar.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/ellipsis_text.dart';
import '../widgets/settings_rows.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import '../widgets/empty_state_text.dart';
import '../widgets/pill_strip.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../shortcuts/panel_keys.dart';
import 'brush_tool_state.dart' show CanvasTool;
import 'tool_setting_rows.dart';
import 'tool_settings_section.dart';

/// A fresh symmetry guide for [canvasSize].
///
/// Vertical axis through the middle, two copies, mirrored — the plain
/// left/right mirror everybody reaches for first. The axis reads 90°
/// because [GuideAxis] measures the LINE, and the eye level it shares a
/// type with is horizontal at 0°.
DrawingGuide newSymmetryGuide(GuideId id, CanvasSize canvasSize, String name) =>
    DrawingGuide(
      id: id,
      name: name,
      shape: SymmetryShape(
        axis: GuideAxis(
          origin: CanvasPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2,
          ),
          angleDegrees: 90,
        ),
      ),
    );

/// A fresh two-point perspective for [canvasSize].
///
/// The horizon runs through the middle and the two vanishing points sit
/// well outside the frame, which is where they normally live — a
/// two-pointer with both points on the paper is a fish-eye.
DrawingGuide newPerspectiveGuide(
  GuideId id,
  CanvasSize canvasSize,
  String name,
) {
  final eyeLevel = GuideAxis(
    origin: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
    angleDegrees: 0,
  );
  final reach = _vanishingPointReach(canvasSize);
  return DrawingGuide(
    id: id,
    name: name,
    shape: PerspectiveShape(
      vanishingPoints: [
        VanishingPointAt(alongAxis(eyeLevel, -reach)),
        VanishingPointAt(alongAxis(eyeLevel, reach)),
      ],
      eyeLevel: eyeLevel,
    ),
  );
}

/// How far from the eye level's handle a vanishing point the app stands
/// out of the frame is: a fresh perspective's two, and a family at
/// infinity whose 「평행」 is pressed off.
///
/// 🗣️vanishing-point-types-Q2 (유저 2026-10-16, 「점이 있던 쪽 그대로」): the
/// family comes back 「같은 방향의 그림 밖 먼 자리(새 퍼스 가이드의 두 점과
/// 같은 거리)」 — ONE distance, so the two cannot come apart.
double _vanishingPointReach(CanvasSize canvasSize) => canvasSize.width * 1.5;

/// How far along the eye level a vanishing point the ＋ adds stands from the
/// eye level's handle — beside it, where the hand can take it at once.
///
/// 🗣️vanishing-point-types-Q7 (유저 2026-10-16): 「아이레벨 위, 아이레벨
/// 손잡이 옆」 — the place the approved picture put 「소실점 4」.
const double _addedVanishingPointAlong = 420;

/// The guide TOOL's library content: the cut's guides, grouped by kind.
///
/// The two act-toggles look alike and behave differently on purpose — a
/// symmetry row's toggle is a RADIO (only one may replicate; two mirror
/// axes at an angle that does not divide π would multiply copies without
/// end), while a perspective row's is an independent checkbox (several may
/// snap at once, and switching the ones you are not drawing off is how the
/// candidate rays stay few enough to predict).
class GuideLibraryList extends StatelessWidget {
  const GuideLibraryList({
    super.key,
    required this.guides,
    required this.canvasSize,
    required this.onGuidesCommitted,
    required this.onGuidesPreview,
    required this.selectedGuideId,
    required this.onGuideSelected,
    this.currentColorOf,
  });

  final CutGuides guides;
  final CanvasSize canvasSize;
  final ValueChanged<CutGuides> onGuidesCommitted;

  /// A bar or a wheel in flight — see [GuideSettings.onGuidesPreview].
  final ValueChanged<CutGuides> onGuidesPreview;

  final GuideId? selectedGuideId;
  final ValueChanged<GuideId?> onGuideSelected;

  /// The colour 「현재 색 반영」 copies in
  /// ([ColorSwatchButton.currentColorOf]).
  final int Function()? currentColorOf;

  String _uniqueId(String prefix) {
    var index = 1;
    while (guides.guideFor(GuideId('$prefix-$index')) != null) {
      index += 1;
    }
    return '$prefix-$index';
  }

  void _add(GuideKind kind) {
    final strings = AppText.strings;
    final id = GuideId(_uniqueId(kind.jsonValue));
    final existing = kind == GuideKind.symmetry
        ? guides.symmetryGuides.length
        : guides.perspectiveGuides.length;
    final label = kind == GuideKind.symmetry
        ? strings.guideKindSymmetry
        : strings.guideKindPerspective;
    final name = '$label ${existing + 1}';
    final guide = kind == GuideKind.symmetry
        ? newSymmetryGuide(id, canvasSize, name)
        : newPerspectiveGuide(id, canvasSize, name);
    onGuidesCommitted(
      guides.copyWith(guides: [...guides.guides, guide]),
    );
    onGuideSelected(id);
  }

  void _delete(GuideId id) {
    onGuidesCommitted(guides.without(id));
    if (selectedGuideId == id) {
      onGuideSelected(null);
    }
  }

  void _replace(DrawingGuide guide) {
    onGuidesCommitted(guides.replacing(guide));
  }

  void _preview(DrawingGuide guide) {
    onGuidesPreview(guides.replacing(guide));
  }

  _GuideRow _row(
    DrawingGuide guide, {
    required bool acting,
    required bool inPickOneGroup,
    required ValueChanged<bool> onActingChanged,
  }) => _GuideRow(
    guide: guide,
    selected: guide.id == selectedGuideId,
    acting: acting,
    inPickOneGroup: inPickOneGroup,
    currentColorOf: currentColorOf,
    onSelected: () => onGuideSelected(guide.id),
    onActingChanged: onActingChanged,
    onVisibleChanged: (visible) => _replace(guide.copyWith(visible: visible)),
    onColorPicking: (argb) => _preview(guide.copyWith(color: argb)),
    onColorPicked: (argb) => _replace(guide.copyWith(color: argb)),
    onOpacityMoved: (opacity) => _preview(guide.copyWith(opacity: opacity)),
    onOpacityLet: (opacity) => _replace(guide.copyWith(opacity: opacity)),
    onRename: (context) => unawaited(_rename(context, guide)),
    onDelete: () => _delete(guide.id),
  );

  /// 유저 (guide-sym): 「**이름변경 버튼을 비지블 버튼 왼쪽에**, 공통 이름변경
  /// 창」 — and 공통 is [AppPromptDialog], the app's one "type a short
  /// string" window, reached through the one dialog verb. ⛔Not a window of
  /// its own: the trim, the empty check and Enter-submits are decided
  /// there, and a second copy is where those three drift apart again.
  ///
  /// A guide's name is a LABEL, like a layer's — the canvas paints it over
  /// the axis — so an empty one is refused, the way `renameLayerEmpty`
  /// refuses. (A frame's name may be empty because it is a link key, which
  /// this is not.)
  Future<void> _rename(BuildContext context, DrawingGuide guide) {
    final strings = AppText.strings;
    return askThenCommit<String>(
      context,
      dialog: (_) => AppPromptDialog.keyed(
        keyPrefix: 'guide-rename',
        title: strings.renameGuideTitle,
        titleIcon: Icons.drive_file_rename_outline,
        fieldLabel: strings.renameGuideField,
        initialValue: guide.name,
        confirmLabel: strings.commonRename,
        emptyError: strings.renameGuideEmpty,
      ),
      commit: (name) => _replace(guide.copyWith(name: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    void addSymmetry() => _add(GuideKind.symmetry);
    void addPerspective() => _add(GuideKind.perspective);
    // A key presses the two ＋ — as the guide tool's library (I-40).
    return PanelKeysBinding(
      tool: CanvasTool.guide,
      buttons: {
        EditorActionIds.guideAddSymmetry: addSymmetry,
        EditorActionIds.guideAddPerspective: addPerspective,
      },
      child: _list(context, strings, addSymmetry, addPerspective),
    );
  }

  Widget _list(
    BuildContext context,
    AppStrings strings,
    VoidCallback addSymmetry,
    VoidCallback addPerspective,
  ) {
    return ContentScrollbar(
      builder: (context, controller) => ListView(
        key: const ValueKey<String>('tool-library-guide-list'),
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          _GuideGroupHeader(
            label: strings.guideKindSymmetry,
            onAdd: addSymmetry,
            addKey: 'guide-add-symmetry',
            action: EditorActionIds.guideAddSymmetry,
          ),
          for (final guide in guides.symmetryGuides)
            _row(
              guide,
              acting: guides.activeSymmetryId == guide.id,
              // ONE `activeSymmetryId`: turning a symmetry on turns the one
              // that was acting off.
              inPickOneGroup: true,
              onActingChanged: (acting) => onGuidesCommitted(
                guides.copyWith(
                  activeSymmetryId: acting ? guide.id : null,
                  clearActiveSymmetry: !acting,
                ),
              ),
            ),
          const Divider(height: 12),
          _GuideGroupHeader(
            label: strings.guideKindPerspective,
            onAdd: addPerspective,
            addKey: 'guide-add-perspective',
            action: EditorActionIds.guideAddPerspective,
          ),
          for (final guide in guides.perspectiveGuides)
            _row(
              guide,
              acting: (guide.shape as PerspectiveShape).snapEnabled,
              // Per guide on purpose ([PerspectiveShape.snapEnabled]):
              // several may snap at once.
              inPickOneGroup: false,
              onActingChanged: (snapping) => _replace(
                guide.copyWith(
                  shape: (guide.shape as PerspectiveShape).copyWith(
                    snapEnabled: snapping,
                  ),
                ),
              ),
            ),
          if (guides.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: EmptyStateText(
                strings.guideLibraryEmpty,
                place: EmptyStatePlace.list,
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideGroupHeader extends StatelessWidget {
  const _GuideGroupHeader({
    required this.label,
    required this.onAdd,
    required this.addKey,
    required this.action,
  });

  final String label;
  final VoidCallback onAdd;
  final String addKey;

  /// The shortcut list's action that presses this ＋ (I-40).
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AppIconButton(
            keyValue: addKey,
            tooltip: editorActionLabel(action),
            shortcuts: [action],
            // The ＋ carries the accent, not the button around it.
            icon: Icon(Icons.add, color: AppColors.addGlyph(enabled: true)),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.guide,
    required this.selected,
    required this.acting,
    required this.inPickOneGroup,
    required this.currentColorOf,
    required this.onSelected,
    required this.onActingChanged,
    required this.onVisibleChanged,
    required this.onColorPicking,
    required this.onColorPicked,
    required this.onOpacityMoved,
    required this.onOpacityLet,
    required this.onRename,
    required this.onDelete,
  });

  final DrawingGuide guide;
  final bool selected;
  final bool acting;

  /// See [BooleanDot.inPickOneGroup] — the two families answer it
  /// differently, which is why each call site says it.
  final bool inPickOneGroup;

  final int Function()? currentColorOf;
  final VoidCallback onSelected;
  final ValueChanged<bool> onActingChanged;
  final ValueChanged<bool> onVisibleChanged;
  final ValueChanged<int> onColorPicking;
  final ValueChanged<int> onColorPicked;
  final ValueChanged<double> onOpacityMoved;
  final ValueChanged<double> onOpacityLet;
  final ValueChanged<BuildContext> onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppText.strings;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey<String>('guide-row-${guide.id.value}'),
        dense: true,
        // The header's 12 at the left; a tile's own gutters left a name a
        // few pixels beside four controls and a bar.
        contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        horizontalTitleGap: 8,
        minLeadingWidth: 0,
        // Selection reads from colour alone — no trailing check glyph.
        selected: selected,
        selectedTileColor: colorScheme.surfaceContainerHigh,
        onTap: onSelected,
        // 🚨THE BUTTON 유저 made the app's boolean from (guide-sym ⑥⑧,
        // 2026-08-31: 「적용시 안에 동그라미 추가」) — [BooleanDot] carries
        // the ring, the dot and the user's two off colours.
        // ↩️It used to swap `circle_outlined` for `check_circle`: a check
        // mark, which 「선택 표시는 색상만」 names outright. Then a copy of
        // the ring drawn here by hand, until the ring had one home.
        leading: BooleanDotButton(
          keyValue: 'guide-acting-${guide.id.value}',
          tooltip: acting ? strings.guideActsOn : strings.guideActsOff,
          value: acting,
          inPickOneGroup: inPickOneGroup,
          onChanged: onActingChanged,
        ),
        // ONE Row in the title, ⛔not the tile's trailing: a trailing that
        // takes the tile's width is an assertion, and the name and the bar
        // are the two that can give at a narrow panel.
        title: Row(
          children: [
            Expanded(
              flex: 3,
              child: EllipsisText(guide.name, maxLines: 1),
            ),
            // 🗣️F-544 (유저 2026-11-02): 「공용 색 동그란 아이콘」.
            _GuideColorButton(
              keyValue: 'guide-color-${guide.id.value}',
              color: guide.color ?? guideColorOf(context).toARGB32(),
              currentColorOf: currentColorOf,
              onPicking: onColorPicking,
              onPicked: onColorPicked,
            ),
            // 유저 (guide-sym): 「**이름변경 버튼을 비지블 버튼 왼쪽에**」 — the
            // position is the instruction, so it is first in this Row and
            // stays first. The verb it opens is the shared one; see
            // `GuideLibraryList._rename`.
            AppIconButton(
              keyValue: 'guide-rename-${guide.id.value}',
              tooltip: strings.commonRename,
              // The rename family's glyph everywhere it has a button of its
              // own (`brush-tip-rename`), and the same icon the window
              // wears in its own title.
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: () => onRename(context),
            ),
            // 🗣️F-544 (유저 2026-11-02): 「비지블버튼 왼쪽에 불투명도 막대
            // 넣어서 보이는거 불투명도 조절가능하게」. The layer row's micro
            // bar: the number alone.
            Expanded(
              flex: 2,
              child: FieldSlider.opacity(
                name: 'guide-opacity-${guide.id.value}',
                value: guide.opacity,
                height: 18 + FieldSlider.growthIn(context),
                onChanged: onOpacityMoved,
                onChangeEnd: onOpacityLet,
              ),
            ),
            // ⛔NOT a hand-rolled eye. 유저 (F-58): 「비지블버튼은
            // 다른곳에서도 쓰니까 공용화/통일화」 — and this was the last
            // copy, the one that dimmed its OFF state in a colour of its
            // own while the five rails dimmed in none.
            LayerVisibilityToggleButton(
              name: 'guide-visible-${guide.id.value}',
              isVisible: guide.visible,
              tooltip: strings.guideShow,
              onToggle: () => onVisibleChanged(!guide.visible),
            ),
            // 🗣️I-58 (유저 2026-10-18): 「통일(레이어 추가 이런식으로 ㅁㅁ
            // 추가. ㅁㅁ 삭제)하고」 — 「가이드 삭제」, the pair of the list's
            // 「새 … 가이드」. ↩️It said 「삭제」, naming nothing.
            AppIconButton(
              keyValue: 'guide-delete-${guide.id.value}',
              tooltip: strings.guideDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's one colour button on a colour of a guide's: every colour the
/// wheel passes shown, the one it came to rest on written — one pick, one
/// undo, as a bar's drag is.
class _GuideColorButton extends StatefulWidget {
  const _GuideColorButton({
    required this.keyValue,
    required this.color,
    required this.currentColorOf,
    required this.onPicking,
    required this.onPicked,
  });

  final String keyValue;
  final int color;
  final int Function()? currentColorOf;
  final ValueChanged<int> onPicking;
  final ValueChanged<int> onPicked;

  @override
  State<_GuideColorButton> createState() => _GuideColorButtonState();
}

class _GuideColorButtonState extends State<_GuideColorButton> {
  /// The colour the window holds, until it closes; the panel underneath
  /// shows the written one, a preview being no write.
  int? _picking;

  @override
  Widget build(BuildContext context) => ColorSwatchButton(
    keyValue: widget.keyValue,
    tooltip: AppText.strings.guideColor,
    color: _picking ?? widget.color,
    currentColorOf: widget.currentColorOf,
    onChanged: (argb) {
      setState(() => _picking = argb);
      widget.onPicking(argb);
    },
    onSettled: () {
      final picked = _picking;
      if (picked != null) {
        widget.onPicked(picked);
        setState(() => _picking = null);
      }
    },
  );
}

/// A point of a guide in numbers: the transform tool's 위치 — X on the
/// name's line, Y under it, each a number box with its hands — and every
/// number of it goes where the canvas's handle would take the point
/// ([dragGuideHandle]), the eye-level law with it.
///
/// 🗣️F-544 (유저 2026-11-02): 「변형도구같은거 그대로 재사용해서 위치값」.
class _GuidePointValues extends StatelessWidget {
  const _GuidePointValues({
    required this.keyPrefix,
    required this.label,
    required this.guides,
    required this.guidesInFlight,
    required this.guideId,
    required this.handle,
    required this.pointIn,
    required this.onGuidesPreview,
    required this.onGuidesCommitted,
    this.vanishingPointIndex,
  });

  final String keyPrefix;
  final String label;
  final CutGuides guides;
  final ValueListenable<CutGuides?>? guidesInFlight;
  final GuideId guideId;
  final GuideHandleKind handle;
  final int? vanishingPointIndex;

  /// Where the point stands in the guides given it — null where they hold
  /// no such point any more.
  final CanvasPoint? Function(DrawingGuide guide) pointIn;

  final ValueChanged<CutGuides> onGuidesPreview;
  final ValueChanged<CutGuides> onGuidesCommitted;

  CutGuides get _now => guidesInFlight?.value ?? guides;

  CanvasPoint? _pointOf(CutGuides shown) => switch (shown.guideFor(guideId)) {
    final guide? => pointIn(guide),
    null => null,
  };

  CutGuides _movedTo(CanvasPoint to) => dragGuideHandle(
    _now,
    GuideHandle(
      guideId: guideId,
      kind: handle,
      position: to,
      vanishingPointIndex: vanishingPointIndex,
    ),
    to,
  );

  /// [at] with the value this box holds replaced by [value].
  static CanvasPoint _withX(CanvasPoint at, double value) =>
      CanvasPoint(x: value, y: at.y);

  static CanvasPoint _withY(CanvasPoint at, double value) =>
      CanvasPoint(x: at.x, y: value);

  Widget _box(
    CutGuides shown, {
    required String name,
    required double Function(CanvasPoint at) read,
    required CanvasPoint Function(CanvasPoint at, double value) write,
  }) {
    final at = _pointOf(shown);
    return DragValueLabel.box(
      keyValue: '$keyPrefix-${name.toLowerCase()}',
      name: name,
      text: at == null ? '' : columnValueText(read(at)),
      onDragDelta: (units) {
        final now = _pointOf(_now);
        if (now != null) {
          onGuidesPreview(_movedTo(write(now, read(now) + units)));
        }
      },
      // ONE SCRUB IS ONE STEP BACK, as the transform's box says.
      onOperationEnd: () => onGuidesCommitted(_now),
      onEditSubmit: (raw) {
        final typed = columnValueOf(raw);
        final now = _pointOf(_now);
        if (typed != null && now != null) {
          onGuidesCommitted(_movedTo(write(now, typed)));
        }
      },
    );
  }

  Widget _following(Widget Function(CutGuides shown) box) =>
      switch (guidesInFlight) {
        null => box(guides),
        final inFlight => ValueListenableBuilder<CutGuides?>(
          valueListenable: inFlight,
          builder: (context, flying, _) => box(flying ?? guides),
        ),
      };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ToolSettingRow.bar(
        label: label,
        bar: _following(
          (shown) => _box(
            shown,
            name: 'X',
            read: (at) => at.x,
            write: _withX,
          ),
        ),
      ),
      ToolSettingRow.bar(
        label: '',
        bar: _following(
          (shown) => _box(
            shown,
            name: 'Y',
            read: (at) => at.y,
            write: _withY,
          ),
        ),
      ),
    ],
  );
}

/// The guide TOOL's entry in the tool SETTINGS panel — the knobs for the
/// selected guide. Same panel every other tool uses; guides get no panel of
/// their own.
class GuideSettings extends StatelessWidget {
  const GuideSettings({
    super.key,
    required this.guides,
    required this.selectedGuideId,
    required this.canvasSize,
    required this.onGuidesCommitted,
    required this.onGuidesPreview,
    required this.onGuideRasterized,
    this.guidesInFlight,
    this.currentColorOf,
  });

  final CutGuides guides;
  final GuideId? selectedGuideId;

  /// The paper the guides stand over — how far out a family at infinity
  /// comes back as a point ([_vanishingPointReach]). Null in a host that
  /// holds no cut, which holds no guide to pick either.
  final CanvasSize? canvasSize;

  final ValueChanged<CutGuides> onGuidesCommitted;

  /// A drag in flight: shown, not written — the release goes to
  /// [onGuidesCommitted] (guide-slider-one-undo: one drag of the count bar
  /// was eleven undo entries).
  ///
  /// ⛔Required, not a fallback to committing: a host with nowhere to show a
  /// preview would be back to one entry per sample.
  final ValueChanged<CutGuides> onGuidesPreview;

  /// What a drag in flight has made of the guides, for the numbers that
  /// follow it — a canvas handle's as well as a box's own — without this
  /// panel rebuilding ([_GuidePointValues]). Null where nothing flies.
  final ValueListenable<CutGuides?>? guidesInFlight;

  /// The colour 「현재 색 반영」 copies in
  /// ([ColorSwatchButton.currentColorOf]).
  final int Function()? currentColorOf;

  /// 래스터라이즈: the guide's lines, as the canvas shows them, drawn
  /// into the cels (vanishing-point-types-Q5 · Q6, I-105-Q2). Null where
  /// nothing can take them — the button keeps its place and goes dead.
  final ValueChanged<DrawingGuide>? onGuideRasterized;

  CutGuides _withShape(DrawingGuide guide, GuideShape shape) =>
      guides.replacing(guide.copyWith(shape: shape));

  void _replaceShape(DrawingGuide guide, GuideShape shape) =>
      onGuidesCommitted(_withShape(guide, shape));

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final id = selectedGuideId;
    final guide = id == null ? null : guides.guideFor(id);
    if (guide == null) {
      return Padding(
        key: const ValueKey<String>('guide-settings-none'),
        padding: const EdgeInsets.all(12),
        child: EmptyStateText(
          strings.noGuideSelected,
          place: EmptyStatePlace.list,
        ),
      );
    }
    final shape = guide.shape;
    // The tool settings' one shell and grid, named by the guide it edits
    // (tool-settings-panel-tidy, 유저 2026-10-10: 「다 통일해서 정돈된 행/열
    // 느낌 나도록」). ↩️It was a list of its own: its rows flush to the
    // panel's edge, each vanishing point a two-line list tile, and the add
    // button gone once there were three.
    final section = ToolSettingsFolds.listen(
      'guide',
      (foldOf) => ToolSettingsSection(
        tool: 'guide-${guide.id.value}',
        title: guide.name,
        children: switch (shape) {
          SymmetryShape() => _symmetryFields(guide, shape),
          PerspectiveShape() => _perspectiveFields(guide, shape, foldOf),
        },
      ),
    );
    // A key presses the perspective's ＋ and 래스터라이즈 as the guide tool's
    // settings (I-40), while a perspective guide is the one picked.
    return PanelKeysBinding(
      tool: CanvasTool.guide,
      buttons: {
        EditorActionIds.guideAddVanishingPoint: switch (shape) {
          SymmetryShape() => null,
          PerspectiveShape() => _vanishingPointAdded(guide, shape),
        },
        EditorActionIds.guideRasterize: switch (shape) {
          SymmetryShape() => null,
          PerspectiveShape() => _rasterizing(guide),
        },
      },
      child: section,
    );
  }

  /// The numbers of [guide]'s point [handle] moves.
  _GuidePointValues _pointValues(
    DrawingGuide guide, {
    required String keyPrefix,
    required String label,
    required GuideHandleKind handle,
    required CanvasPoint? Function(DrawingGuide guide) pointIn,
    int? vanishingPointIndex,
  }) => _GuidePointValues(
    keyPrefix: keyPrefix,
    label: label,
    guides: guides,
    guidesInFlight: guidesInFlight,
    guideId: guide.id,
    handle: handle,
    vanishingPointIndex: vanishingPointIndex,
    pointIn: pointIn,
    onGuidesPreview: onGuidesPreview,
    onGuidesCommitted: onGuidesCommitted,
  );

  List<Widget> _symmetryFields(DrawingGuide guide, SymmetryShape shape) {
    final strings = AppText.strings;
    return [
      // 🗣️F-544 (유저 2026-11-02): 「이런 ui개편같은거 다른 도구설정쪽
      // 참고해서 그대로 재사용하면서 법 통일」 — a symmetry's middle is a
      // point the canvas's handle moves, as a vanishing point is.
      _pointValues(
        guide,
        keyPrefix: 'guide-origin',
        label: strings.trPosition,
        handle: GuideHandleKind.origin,
        pointIn: (guide) => switch (guide.shape) {
          SymmetryShape(:final axis) => axis.origin,
          _ => null,
        },
      ),
      SettingsSwitchRow(
        tileKey: const ValueKey<String>('guide-line-symmetry'),
        label: strings.guideMirrorMode,
        help: shape.lineSymmetry
            ? strings.guideMirrorModeOn
            : strings.guideMirrorModeOff,
        value: shape.lineSymmetry,
        onChanged: (value) =>
            _replaceShape(guide, shape.copyWith(lineSymmetry: value)),
      ),
      ToolSettingRow.bar(
        label: strings.guideLineCount,
        bar: FieldSlider.cell(
          key: const ValueKey<String>('guide-line-count'),
          label: strings.guideLineCount,
          value: shape.lineCount.toDouble(),
          min: 2,
          max: maxSymmetryLineCount.toDouble(),
          // Mirrored copies come in pairs, so the count steps by two there.
          divisions: shape.lineSymmetry
              ? (maxSymmetryLineCount - 2) ~/ 2
              : maxSymmetryLineCount - 2,
          // ⛔PREVIEW while the bar moves, COMMIT on release — one drag,
          // one undo. The canvas still follows every sample.
          onChanged: (value) => onGuidesPreview(
            _withShape(guide, shape.copyWith(lineCount: value.round())),
          ),
          onChangeEnd: (value) => _replaceShape(
            guide,
            shape.copyWith(lineCount: value.round()),
          ),
        ),
      ),
    ];
  }

  List<Widget> _perspectiveFields(
    DrawingGuide guide,
    PerspectiveShape shape,
    ToolSettingsFold Function(String group) foldOf,
  ) {
    final strings = AppText.strings;
    return [
      // ⛔THE SNAP SWITCH IS GONE FROM HERE (유저 2026-09-01, guide-sym):
      // 「퍼스자의 툴설정에 있는 스냅버튼, **이거 중복되니까 삭제. 퍼스자
      // 이름 왼쪽에 이미 존재**」.
      //
      // The row's own acting button IS this value — `_GuideRow(acting:
      // shape.snapEnabled, onActingChanged: …)` — so the panel was offering
      // one fact twice, and the two could disagree only in how far the user
      // had to look. ⚠️`snapEnabled` itself is untouched; what went is the
      // second control for it.
      ...toolSettingsGroup(
        strings.guideEyeLevel,
        first: true,
        fold: foldOf('eye-level'),
        rows: _eyeLevelRows(guide, shape),
      ),
      ...toolSettingsGroup(
        strings.guideVanishingPoint,
        fold: foldOf('vanishing-points'),
        rows: _vanishingPointRows(guide, shape),
      ),
      ToolSettingActions(
        lines: [
          [
            ToolSettingAction(
              keyValue: 'guide-add-vanishing-point',
              label: strings.guideAddVanishingPoint,
              shortcuts: const [EditorActionIds.guideAddVanishingPoint],
              onPressed: _vanishingPointAdded(guide, shape),
            ),
            ToolSettingAction(
              keyValue: 'guide-rasterize',
              label: strings.guideRasterize,
              shortcuts: const [EditorActionIds.guideRasterize],
              onPressed: _rasterizing(guide),
            ),
          ],
        ],
      ),
    ];
  }

  /// 🗣️F-544 (유저 2026-11-02): 「애초에 아이레벨이라고 항목화하자.
  /// 퍼스가이드안에서 항목화해서 표시 버튼, 색 버튼, 위치값 이렇게」.
  List<Widget> _eyeLevelRows(DrawingGuide guide, PerspectiveShape shape) {
    final strings = AppText.strings;
    return [
      ToolSettingRow.atEnd(
        label: strings.guideVisibleLabel,
        child: LayerVisibilityToggleButton(
          name: 'guide-eye-level-visible',
          isVisible: shape.eyeLevelVisible,
          tooltip: strings.guideEyeLevelShow,
          onToggle: () => _replaceShape(
            guide,
            shape.copyWith(eyeLevelVisible: !shape.eyeLevelVisible),
          ),
        ),
      ),
      ToolSettingRow.atEnd(
        label: strings.guideColor,
        child: Builder(
          builder: (context) => _GuideColorButton(
            keyValue: 'guide-eye-level-color',
            color:
                shape.eyeLevelColor ??
                guide.color ??
                guideColorOf(context).toARGB32(),
            currentColorOf: currentColorOf,
            onPicking: (argb) => onGuidesPreview(
              _withShape(guide, shape.copyWith(eyeLevelColor: argb)),
            ),
            onPicked: (argb) =>
                _replaceShape(guide, shape.copyWith(eyeLevelColor: argb)),
          ),
        ),
      ),
      _pointValues(
        guide,
        keyPrefix: 'guide-eye-level',
        label: strings.trPosition,
        handle: GuideHandleKind.origin,
        pointIn: (guide) => switch (guide.shape) {
          PerspectiveShape(:final eyeLevel) => eyeLevel.origin,
          _ => null,
        },
      ),
    ];
  }

  List<Widget> _vanishingPointRows(
    DrawingGuide guide,
    PerspectiveShape shape,
  ) {
    final strings = AppText.strings;
    final points = shape.vanishingPoints;
    return [
      SettingsSwitchRow(
        tileKey: const ValueKey<String>('guide-constrain-eye-level'),
        label: strings.guideConstrainToEyeLevel,
        help: strings.guideConstrainToEyeLevelNote,
        value: shape.constrainToEyeLevel,
        onChanged: (value) =>
            _replaceShape(guide, shape.copyWith(constrainToEyeLevel: value)),
      ),
      for (var index = 0; index < points.length; index += 1)
        _VanishingPointRow(
          index: index,
          point: points[index],
          whereItStands: _pointValues(
            guide,
            keyPrefix: 'guide-vanishing-point-$index',
            label: '${index + 1}',
            handle: GuideHandleKind.vanishingPoint,
            vanishingPointIndex: index,
            pointIn: (guide) => switch (guide.shape) {
              PerspectiveShape(:final vanishingPoints)
                  when index < vanishingPoints.length =>
                vanishingPoints[index].resolve().position,
              _ => null,
            },
          ),
          onParallelToggled: _parallelToggled(guide, shape, index),
          // The angle cell and the canvas's direction handle write the one
          // value (vanishing-point-types-Q3): shown while it moves,
          // committed once it is let go.
          onTurned: (degrees) => onGuidesPreview(
            _withShape(guide, _turned(shape, index, degrees)),
          ),
          onTurnEnded: (degrees) =>
              _replaceShape(guide, _turned(shape, index, degrees)),
          // ⛔PREVIEW while the bar moves, COMMIT on release — one drag,
          // one undo.
          onDensityMoved: (density) => onGuidesPreview(
            _withShape(guide, shape.withLineDensity(index, density)),
          ),
          onDensityLet: (density) => _replaceShape(
            guide,
            shape.withLineDensity(index, density),
          ),
          onRemoved: points.length > 1
              ? () => _replaceShape(
                  guide,
                  shape.copyWith(
                    vanishingPoints: [...points]..removeAt(index),
                  ),
                )
              : null,
        ),
    ];
  }

  /// What 래스터라이즈 presses: [guide] handed over to be baked — dead where
  /// nothing takes it.
  VoidCallback? _rasterizing(DrawingGuide guide) =>
      switch (onGuideRasterized) {
        null => null,
        final rasterize => () => rasterize(guide),
      };

  /// What the perspective's ＋ presses: one more vanishing point, on the eye
  /// level beside its handle.
  ///
  /// 🗣️유저 2026-09-17 (vanishing-point-types): 「소실점 몇개든
  /// 추가할수있게하고, 기본값은 일반타입」 · Q7 (10-16) for where it stands
  /// ([_addedVanishingPointAlong]). ↩️A guide held three at most, and the
  /// ＋ added the vertical family.
  VoidCallback _vanishingPointAdded(
    DrawingGuide guide,
    PerspectiveShape shape,
  ) => () => _replaceShape(
    guide,
    shape.copyWith(
      vanishingPoints: [
        ...shape.vanishingPoints,
        VanishingPointAt(
          alongAxis(shape.eyeLevel, _addedVanishingPointAlong),
        ),
      ],
    ),
  );

  /// What the point at [index]'s 「평행」 pill presses ([toggledParallel]),
  /// or null where it has nothing to turn the point into.
  VoidCallback? _parallelToggled(
    DrawingGuide guide,
    PerspectiveShape shape,
    int index,
  ) {
    final paper = canvasSize;
    final toggled = paper == null
        ? null
        : toggledParallel(
            shape,
            shape.vanishingPoints[index],
            reach: _vanishingPointReach(paper),
          );
    if (toggled == null) {
      return null;
    }
    return () =>
        _replaceShape(guide, shape.withVanishingPoint(index, toggled));
  }

  /// [shape] with its point at [index] the family running at [degrees].
  static PerspectiveShape _turned(
    PerspectiveShape shape,
    int index,
    double degrees,
  ) => shape.withVanishingPoint(
    index,
    VanishingPointTowards.atDegrees(degrees),
  );
}

/// One vanishing point's lines of the grid: its number in the name column
/// beside where it stands — or, a family at infinity, the way it runs as an
/// angle; its density bar; its 「평행」 pill and its delete.
class _VanishingPointRow extends StatelessWidget {
  const _VanishingPointRow({
    required this.index,
    required this.point,
    required this.whereItStands,
    required this.onParallelToggled,
    required this.onTurned,
    required this.onTurnEnded,
    required this.onDensityMoved,
    required this.onDensityLet,
    required this.onRemoved,
  });

  final int index;
  final VanishingPoint point;

  /// The point's 위치, for a point the hand placed.
  final Widget whereItStands;

  /// The 「평행」 pill's press — null where it is refused, and the pill keeps
  /// its place.
  final VoidCallback? onParallelToggled;

  /// A family at infinity's angle cell, while it moves and once let go.
  final ValueChanged<double> onTurned;
  final ValueChanged<double> onTurnEnded;

  /// The point's density bar, while it moves and once let go.
  final ValueChanged<int> onDensityMoved;
  final ValueChanged<int> onDensityLet;

  final VoidCallback? onRemoved;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final resolved = point.resolve();
    final position = resolved.position;
    // ⚠️EQUIVALENT MUTANT, and the arm stays on purpose (2026-09-08):
    // [HomogeneousPoint.position] is null for every `w == 0`, so dropping
    // `resolved.isInfinite` changes no answer. It NAMES the case a reader
    // came looking for, while the second arm also catches a cross product
    // that overflowed to NaN — which nobody would read out of it alone.
    final atInfinity = resolved.isInfinite || position == null;
    return Column(
      key: ValueKey<String>('guide-vanishing-point-$index'),
      children: [
        _whereIt(context, strings, position),
        // 🗣️F-544 (유저 2026-11-02): 「소실점의 해당 레인에 막대 두도록」.
        ToolSettingRow.bar(
          label: strings.guideLineDensity,
          bar: FieldSlider.cell(
            key: ValueKey<String>('guide-vanishing-point-$index-density'),
            label: strings.guideLineDensity,
            value: point.lineDensity.toDouble(),
            min: minGuideLineDensity.toDouble(),
            max: maxGuideLineDensity.toDouble(),
            divisions: maxGuideLineDensity - minGuideLineDensity,
            onChanged: (value) => onDensityMoved(value.round()),
            onChangeEnd: (value) => onDensityLet(value.round()),
          ),
        ),
        ToolSettingRow(
          label: '',
          child: _parallelAndRemove(strings, atInfinity: atInfinity),
        ),
      ],
    );
  }

  /// The point's first line, or two: where it stands — or, a family at
  /// infinity, the angle it runs at, typed here.
  Widget _whereIt(
    BuildContext context,
    AppStrings strings,
    CanvasPoint? position,
  ) => switch (point) {
    VanishingPointAt() => whereItStands,
    // 🗣️vanishing-point-types-Q3 (유저 2026-10-16): 「각도 칸으로
    // 정확히」 — 90 is the vertical family, stated exactly.
    final VanishingPointTowards towards => ToolSettingRow.bar(
      label: '${index + 1}',
      bar: FieldSlider.cell(
        key: ValueKey<String>('guide-vanishing-point-$index-angle'),
        label: strings.guideParallelAngle,
        value: towards.degrees,
        min: -180,
        max: 180,
        unit: '°',
        onChanged: onTurned,
        onChangeEnd: onTurnEnded,
      ),
    ),
    // Two drawn lines name it: they say where it is, not a number.
    VanishingPointFromLines() => ToolSettingRow(
      label: '${index + 1}',
      child: _reads(
        context,
        position == null
            ? strings.guideVanishingPointAtInfinity
            : '${position.x.round()}, ${position.y.round()}',
      ),
    ),
  };

  /// The point's last line: the 「평행」 pill and the delete, side by side.
  Widget _parallelAndRemove(AppStrings strings, {required bool atInfinity}) =>
      Row(
        children: [
          // 🗣️vanishing-point-types-Q1 (유저 2026-10-16): ONE pill, lit
          // while the point is at infinity, each press the other way.
          // ↩️「정확히 수직으로」 stood here, and only ever made a family.
          Expanded(
            child: PillStrip.even(
              items: [
                PillItem(
                  keyValue: 'guide-parallel',
                  label: strings.guideParallel,
                  selected: atInfinity,
                  onTap: onParallelToggled,
                ),
              ],
            ),
          ),
          const SizedBox(width: ToolSettingColumns.gap),
          // 🗣️I-58 (유저 2026-10-18): 「ㅁㅁ 삭제」 — 「소실점 삭제」, the
          // pair of 「새 소실점」. ↩️It borrowed the guide row's string, so
          // it said 「삭제」 and then would have said 「가이드 삭제」.
          Expanded(
            child: ToolSettingAction.glyph(
              keyValue: 'guide-remove',
              label: strings.guideDeleteVanishingPoint,
              glyph: const Icon(Icons.delete_outline),
              onPressed: onRemoved,
            ),
          ),
        ],
      );

  /// Where the point stands, read and not edited here.
  Widget _reads(BuildContext context, String text) {
    final theme = Theme.of(context);
    return EllipsisText(
      text,
      key: ValueKey<String>('guide-vanishing-point-$index-reads'),
      maxLines: 1,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
