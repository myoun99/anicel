import 'dart:async';

import '../timeline/layer_label_controls.dart' show LayerVisibilityToggleButton;
import '../widgets/app_icon_button.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/drawing_guide.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/dialog_verb.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';
import '../widgets/settings_prompt_text.dart';

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
  final midY = canvasSize.height / 2.0;
  final width = canvasSize.width.toDouble();
  return DrawingGuide(
    id: id,
    name: name,
    shape: PerspectiveShape(
      vanishingPoints: [
        VanishingPointAt(CanvasPoint(x: -width, y: midY)),
        VanishingPointAt(CanvasPoint(x: width * 2, y: midY)),
      ],
      eyeLevel: GuideAxis(
        origin: CanvasPoint(x: width / 2, y: midY),
        angleDegrees: 0,
      ),
    ),
  );
}

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
    required this.selectedGuideId,
    required this.onGuideSelected,
  });

  final CutGuides guides;
  final CanvasSize canvasSize;
  final ValueChanged<CutGuides> onGuidesCommitted;
  final GuideId? selectedGuideId;
  final ValueChanged<GuideId?> onGuideSelected;

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
    return ListView(
      key: const ValueKey<String>('tool-library-guide-list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _GuideGroupHeader(
          label: strings.guideKindSymmetry,
          onAdd: () => _add(GuideKind.symmetry),
          addKey: 'guide-add-symmetry',
        ),
        for (final guide in guides.symmetryGuides)
          _GuideRow(
            guide: guide,
            selected: guide.id == selectedGuideId,
            acting: guides.activeSymmetryId == guide.id,
            onSelected: () => onGuideSelected(guide.id),
            onActingChanged: (acting) => onGuidesCommitted(
              guides.copyWith(
                activeSymmetryId: acting ? guide.id : null,
                clearActiveSymmetry: !acting,
              ),
            ),
            onVisibleChanged: (visible) =>
                _replace(guide.copyWith(visible: visible)),
            onRename: () => unawaited(_rename(context, guide)),
            onDelete: () => _delete(guide.id),
          ),
        const Divider(height: 12),
        _GuideGroupHeader(
          label: strings.guideKindPerspective,
          onAdd: () => _add(GuideKind.perspective),
          addKey: 'guide-add-perspective',
        ),
        for (final guide in guides.perspectiveGuides)
          _GuideRow(
            guide: guide,
            selected: guide.id == selectedGuideId,
            acting: (guide.shape as PerspectiveShape).snapEnabled,
            onSelected: () => onGuideSelected(guide.id),
            onActingChanged: (snapping) => _replace(
              guide.copyWith(
                shape: (guide.shape as PerspectiveShape).copyWith(
                  snapEnabled: snapping,
                ),
              ),
            ),
            onVisibleChanged: (visible) =>
                _replace(guide.copyWith(visible: visible)),
            onRename: () => unawaited(_rename(context, guide)),
            onDelete: () => _delete(guide.id),
          ),
        if (guides.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              strings.guideLibraryEmpty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _GuideGroupHeader extends StatelessWidget {
  const _GuideGroupHeader({
    required this.label,
    required this.onAdd,
    required this.addKey,
  });

  final String label;
  final VoidCallback onAdd;
  final String addKey;

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
            tooltip: AppText.strings.guideAdd,
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
    required this.onSelected,
    required this.onActingChanged,
    required this.onVisibleChanged,
    required this.onRename,
    required this.onDelete,
  });

  final DrawingGuide guide;
  final bool selected;
  final bool acting;
  final VoidCallback onSelected;
  final ValueChanged<bool> onActingChanged;
  final ValueChanged<bool> onVisibleChanged;
  final VoidCallback onRename;
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
        // Selection reads from colour alone — no trailing check glyph.
        selected: selected,
        selectedTileColor: colorScheme.surfaceContainerHigh,
        onTap: onSelected,
        title: Text(guide.name),
        leading: AppIconButton(
          keyValue: 'guide-acting-${guide.id.value}',
          tooltip: acting ? strings.guideActsOn : strings.guideActsOff,
          isSelected: acting,
          // ⛔ONE GLYPH, and the state is the COLOUR. This used to swap
          // `circle_outlined` for `check_circle` — a check mark, which the
          // app's selection law names outright: 「선택 표시는 색상만」, never
          // a check and never a filled chip ([[ui-selection-style]]).
          //
          // 🚨THE INNER DOT — 유저 2026-09-10 (guide-sym): 「적용/미적용 동그란
          // 버튼에 **적용 시 안에 동그라미**(환경설정▸입력▸태블릿서비스
          // 버튼처럼)」. That button is a stock Material radio
          // (`input_settings_dialog.dart`, 'settings-tablet-standard'):
          // ON is a ring with a filled dot in the accent, OFF the bare
          // ring. `radio_button_checked`/`_unchecked` ARE that pair of
          // glyphs, so the model and the copy are the same drawing.
          //
          // ⚠️It does NOT reopen the line above. A check mark is a
          // DIFFERENT shape saying "done"; this is one shape whose middle
          // fills, at the same size, in the same accent the colour rule
          // already puts there. ⛔And still never a filled chip — the rim
          // stays a ring, so nothing about the button's box changes.
          icon: Icon(
            acting ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          ),
          onPressed: () => onActingChanged(!acting),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              onPressed: onRename,
            ),
            // ⛔NOT a hand-rolled eye. 유저 (F-58): 「비지블버튼은
            // 다른곳에서도 쓰니까 공용화/통일화」 — and this was the last
            // copy, the one that dimmed its OFF state in a colour of its
            // own while the five rails dimmed in none.
            LayerVisibilityToggleButton(
              keyValue: 'guide-visible-${guide.id.value}',
              isVisible: guide.visible,
              tooltip: strings.guideShow,
              onToggle: () => onVisibleChanged(!guide.visible),
            ),
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

/// The guide TOOL's entry in the tool SETTINGS panel — the knobs for the
/// selected guide. Same panel every other tool uses; guides get no panel of
/// their own.
class GuideSettings extends StatelessWidget {
  const GuideSettings({
    super.key,
    required this.guides,
    required this.selectedGuideId,
    required this.onGuidesCommitted,
  });

  final CutGuides guides;
  final GuideId? selectedGuideId;
  final ValueChanged<CutGuides> onGuidesCommitted;

  void _replaceShape(DrawingGuide guide, GuideShape shape) {
    onGuidesCommitted(guides.replacing(guide.copyWith(shape: shape)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final id = selectedGuideId;
    final guide = id == null ? null : guides.guideFor(id);
    if (guide == null) {
      return Padding(
        key: const ValueKey<String>('guide-settings-none'),
        padding: const EdgeInsets.all(12),
        child: SettingsPromptText(strings.guideSelectPrompt),
      );
    }
    final shape = guide.shape;
    return ListView(
      key: ValueKey<String>('guide-settings-${guide.id.value}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: switch (shape) {
        SymmetryShape() => _symmetryFields(context, guide, shape),
        PerspectiveShape() => _perspectiveFields(context, guide, shape),
      },
    );
  }

  List<Widget> _symmetryFields(
    BuildContext context,
    DrawingGuide guide,
    SymmetryShape shape,
  ) {
    final strings = AppText.strings;
    return [
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
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: FieldSlider(
          key: const ValueKey<String>('guide-line-count'),
          label: strings.guideLineCount,
          value: shape.lineCount.toDouble(),
          min: 2,
          max: maxSymmetryLineCount.toDouble(),
          // Mirrored copies come in pairs, so the count steps by two there.
          divisions: shape.lineSymmetry
              ? (maxSymmetryLineCount - 2) ~/ 2
              : maxSymmetryLineCount - 2,
          onChanged: (value) => _replaceShape(
            guide,
            shape.copyWith(lineCount: value.round()),
          ),
        ),
      ),
    ];
  }

  List<Widget> _perspectiveFields(
    BuildContext context,
    DrawingGuide guide,
    PerspectiveShape shape,
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
      SettingsSwitchRow(
        tileKey: const ValueKey<String>('guide-eye-level-visible'),
        label: strings.guideEyeLevelShow,
        value: shape.eyeLevelVisible,
        onChanged: (value) =>
            _replaceShape(guide, shape.copyWith(eyeLevelVisible: value)),
      ),
      SettingsSwitchRow(
        tileKey: const ValueKey<String>('guide-constrain-eye-level'),
        label: strings.guideConstrainToEyeLevel,
        help: strings.guideConstrainToEyeLevelNote,
        value: shape.constrainToEyeLevel,
        onChanged: (value) =>
            _replaceShape(guide, shape.copyWith(constrainToEyeLevel: value)),
      ),
      const Divider(height: 12),
      for (var index = 0; index < shape.vanishingPoints.length; index += 1)
        _VanishingPointRow(
          index: index,
          point: shape.vanishingPoints[index],
          onMadeVertical: () {
            final points = [...shape.vanishingPoints];
            // Exactly vertical, stated as a DIRECTION — the one form that
            // does not depend on two lines being parallel to the last bit.
            points[index] = VanishingPointTowards(dx: 0, dy: 1);
            _replaceShape(guide, shape.copyWith(vanishingPoints: points));
          },
          onRemoved: shape.vanishingPoints.length > 1
              ? () {
                  final points = [...shape.vanishingPoints]..removeAt(index);
                  _replaceShape(
                    guide,
                    shape.copyWith(vanishingPoints: points),
                  );
                }
              : null,
        ),
      if (shape.vanishingPoints.length < 3)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('guide-add-vanishing-point'),
              icon: Icon(
                Icons.add,
                size: 18,
                color: AppColors.addGlyph(enabled: true),
              ),
              label: Text(strings.guideAddVanishingPoint),
              onPressed: () => _replaceShape(
                guide,
                shape.copyWith(
                  vanishingPoints: [
                    ...shape.vanishingPoints,
                    // The third point is the vertical family far more often
                    // than not, so that is what a new one starts as.
                    VanishingPointTowards(dx: 0, dy: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

class _VanishingPointRow extends StatelessWidget {
  const _VanishingPointRow({
    required this.index,
    required this.point,
    required this.onMadeVertical,
    required this.onRemoved,
  });

  final int index;
  final VanishingPoint point;
  final VoidCallback onMadeVertical;
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
    final subtitle = resolved.isInfinite || position == null
        ? strings.guideVanishingPointAtInfinity
        : '${position.x.round()}, ${position.y.round()}';
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey<String>('guide-vanishing-point-$index'),
        dense: true,
        title: Text('${strings.guideVanishingPoint} ${index + 1}'),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'guide-make-vertical',
              tooltip: strings.guideMakeVertical,
              icon: const Icon(Icons.vertical_align_center),
              onPressed: onMadeVertical,
            ),
            AppIconButton(
              keyValue: 'guide-remove',
              tooltip: strings.guideDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemoved,
            ),
          ],
        ),
      ),
    );
  }
}
