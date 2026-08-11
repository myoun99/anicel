import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/drawing_guide.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/field_slider.dart';

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
    onGuidesCommitted(
      guides.copyWith(
        guides: [
          for (final guide in guides.guides)
            if (guide.id != id) guide,
        ],
      ),
    );
    if (selectedGuideId == id) {
      onGuideSelected(null);
    }
  }

  void _replace(DrawingGuide guide) {
    onGuidesCommitted(
      guides.copyWith(
        guides: [
          for (final entry in guides.guides)
            if (entry.id == guide.id) guide else entry,
        ],
      ),
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
          IconButton(
            key: ValueKey<String>(addKey),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
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
    required this.onDelete,
  });

  final DrawingGuide guide;
  final bool selected;
  final bool acting;
  final VoidCallback onSelected;
  final ValueChanged<bool> onActingChanged;
  final ValueChanged<bool> onVisibleChanged;
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
        leading: IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: acting ? strings.guideActsOn : strings.guideActsOff,
          icon: Icon(
            acting ? Icons.check_circle : Icons.circle_outlined,
            color: acting ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          onPressed: () => onActingChanged(!acting),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: strings.guideShow,
              icon: Icon(
                guide.visible ? Icons.visibility : Icons.visibility_off,
                color: guide.visible
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: () => onVisibleChanged(!guide.visible),
            ),
            IconButton(
              key: ValueKey<String>('guide-delete-${guide.id.value}'),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
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
    onGuidesCommitted(
      guides.copyWith(
        guides: [
          for (final entry in guides.guides)
            if (entry.id == guide.id) entry.copyWith(shape: shape) else entry,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final theme = Theme.of(context);
    final id = selectedGuideId;
    final guide = id == null ? null : guides.guideFor(id);
    if (guide == null) {
      return Padding(
        key: const ValueKey<String>('guide-settings-none'),
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            strings.guideSelectPrompt,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
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
      SwitchListTile(
        key: const ValueKey<String>('guide-line-symmetry'),
        dense: true,
        title: Text(strings.guideMirrorMode),
        subtitle: Text(
          shape.lineSymmetry
              ? strings.guideMirrorModeOn
              : strings.guideMirrorModeOff,
        ),
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
          valueText: '${shape.lineCount}',
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
      SwitchListTile(
        key: const ValueKey<String>('guide-snap'),
        dense: true,
        title: Text(strings.guideSnap),
        subtitle: Text(strings.guideSnapNote),
        value: shape.snapEnabled,
        onChanged: (value) =>
            _replaceShape(guide, shape.copyWith(snapEnabled: value)),
      ),
      SwitchListTile(
        key: const ValueKey<String>('guide-eye-level-visible'),
        dense: true,
        title: Text(strings.guideEyeLevelShow),
        value: shape.eyeLevelVisible,
        onChanged: (value) =>
            _replaceShape(guide, shape.copyWith(eyeLevelVisible: value)),
      ),
      SwitchListTile(
        key: const ValueKey<String>('guide-constrain-eye-level'),
        dense: true,
        title: Text(strings.guideConstrainToEyeLevel),
        subtitle: Text(strings.guideConstrainToEyeLevelNote),
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
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: strings.guideMakeVertical,
              icon: const Icon(Icons.vertical_align_center),
              onPressed: onMadeVertical,
            ),
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
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
