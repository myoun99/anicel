import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;
import '../timeline/layer_label_controls.dart';
import '../timeline/layer_rail_columns.dart';
import '../timeline/timeline_grid_metrics.dart' show timelineLayerRowHeight;

/// The 9px boolean the export window's lists lead with: on = accent fill,
/// off = a hairline box, [indeterminate] = half filled (a folder whose
/// leaves are mixed). 유저 2026-09-09: 「라벨의 제일 왼쪽에 체크버튼? 불리언버튼
/// 넣고 … 지금은 뭐로 선택 바꾸는건지 전혀 모르겠으니」 — the dot IS how a
/// row is chosen, so it sits first on every row that can be chosen.
class ExportIncludeDot extends StatelessWidget {
  const ExportIncludeDot({
    super.key,
    required this.value,
    this.indeterminate = false,
    this.onTap,
  });

  final bool value;
  final bool indeterminate;

  /// Null = this row is not the user's to tick (paper is APPLIED, a camera
  /// row holds no cel): the dot stays in place, disabled.
  final VoidCallback? onTap;

  /// The slot the dot occupies on a row, dot centred.
  static const double slotWidth = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final lit = value || indeterminate;
    final edge = onTap == null
        ? theme.disabledColor.withValues(alpha: 0.4)
        : lit
        ? accent
        : theme.dividerColor;
    return ControlPressClaim(
      onPressed: onTap,
      child: InkWell(
        onTap: silentPress(onTap),
        child: SizedBox(
          width: slotWidth,
          height: slotWidth,
          child: Center(
            child: Container(
              width: 9,
              height: 9,
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: value && !indeterminate && onTap != null ? accent : null,
                shape: AppShapes.container(2, side: BorderSide(color: edge)),
              ),
              child: indeterminate
                  ? FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.5,
                      child: ColoredBox(color: accent),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the Cels tab's layer list — THE TIMELINE ROW'S LEADING CELLS,
/// not a likeness of them (유저 2026-09-09: 「셀의 선택부분은 진짜 타임라인
/// 아이콘이나 뭐나 싹 다 그대로 재사용해서 타임라인이랑 똑같이 생기도록」):
/// the include dot, then the rail's own mark plates, its attach arrow in the
/// sheet slot, its type button, its nesting guides and the name, at the
/// rail's slot widths and row height. What the rail carries that this list
/// does not need (lane toggle, sheet toggle, fx, eye, opacity, blend) is
/// simply not asked for — the four columns the user named show the
/// structure, and nothing else.
///
/// An unselected row dims to the rail's 「off」 alpha; nothing highlights
/// a 「current」 row (유저: 「오른쪽의 셀 리스트는 선택중인 상태가 필요한가」).
class ExportCelLayerRow extends StatelessWidget {
  const ExportCelLayerRow({
    super.key,
    required this.keyPrefix,
    required this.layer,
    required this.layers,
    required this.included,
    this.indeterminate = false,
    this.onToggle,
  });

  final String keyPrefix;
  final Layer layer;

  /// The cut's stack — the folder chain (depth) is read from it.
  final List<Layer> layers;

  final bool included;

  /// A folder whose leaves disagree.
  final bool indeterminate;

  /// Null = not tickable (see [ExportIncludeDot.onTap]).
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const axis = Axis.horizontal;
    final depth = layers.ancestryOf(layer.folderId).length;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: ExportIncludeDot.slotWidth,
          child: Center(
            child: ExportIncludeDot(
              key: ValueKey<String>('$keyPrefix-dot-${layer.id.value}'),
              value: included,
              indeterminate: indeterminate,
              onTap: onToggle,
            ),
          ),
        ),
        ..._railCells(axis),
        ?layerRailDepthGuides(axis, depth, color: colorScheme.outlineVariant),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              layer.name,
              key: ValueKey<String>('$keyPrefix-name-${layer.id.value}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: layerRowNameStyle(context),
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      height: timelineLayerRowHeight,
      child: Opacity(
        // ⚠️0.45 is the rail's own 「off」 alpha (F-56) — a row that is not in
        // reads as off in the language every other off state already uses.
        opacity: included || indeterminate ? 1 : layerRailOffAlpha,
        child: row,
      ),
    );
  }

  /// The rail's leading cells at the rail's slot widths: mark plates, the
  /// attach arrow in the sheet slot, the type button.
  List<Widget> _railCells(Axis axis) {
    final idValue = '${layer.id}';
    return [
      layerRailSlot(axis, layerLabelSlotWidth, LayerMarkPlates(mark: layer.mark)),
      layerRailSlot(axis, layerRailSectionGap),
      // The attach arrow rides the sheet slot on the rail too (R10 R3).
      layerRailSlot(
        axis,
        layerTimesheetSlotWidth,
        isAttachedLayer(layer)
            ? LayerAttachArrowCell(
                keyPrefix: keyPrefix,
                idValue: idValue,
                placement: layer.attachedPlacement,
              )
            : null,
      ),
      layerRailSlot(axis, layerControlChipGap),
      layerRailSlot(
        axis,
        layerTypeSlotWidth,
        LayerTypeButton(
          keyPrefix: keyPrefix,
          idValue: idValue,
          kind: layer.kind,
          folderCollapsed: layer.collapsed,
          onTap: onToggle,
        ),
      ),
      layerRailSlot(axis, layerControlChipGap),
    ];
  }
}
