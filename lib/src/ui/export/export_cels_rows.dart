import 'package:flutter/material.dart';

import '../../models/attached_layer_resolve.dart';
import '../../models/attached_mode.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../timeline/layer_label_controls.dart' show layerMarkColor;

/// The shared compact layer-label row (v10 간략 컴포넌트: 색마크바 +
/// 아이콘 + 이름): the Cels label list, the Add-from-timeline sub list
/// and the Layers member list all speak this one grammar.
class ExportLayerRow extends StatelessWidget {
  const ExportLayerRow({
    super.key,
    required this.layer,
    this.selected = false,
    this.dimmed = false,
    this.includeDot,
    this.dotKey,
    this.onDotTap,
    this.onRemove,
    this.onTap,
    this.trailingTag,
  });

  final Layer layer;
  final bool selected;
  final bool dimmed;

  /// Null hides the dot; otherwise the include state it shows.
  final bool? includeDot;
  final Key? dotKey;
  final VoidCallback? onDotTap;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  /// The small dim tag at the end (기준/sync/free).
  final String? trailingTag;

  static IconData kindIcon(LayerKind kind) => switch (kind) {
    LayerKind.animation => Icons.edit_outlined,
    LayerKind.storyboard => Icons.sticky_note_2_outlined,
    LayerKind.image => Icons.image_outlined,
    LayerKind.text => Icons.title_outlined,
    LayerKind.se => Icons.volume_up_outlined,
    LayerKind.instruction => Icons.swipe_right_alt_outlined,
    LayerKind.transition => Icons.compare_arrows_outlined,
    LayerKind.camera => Icons.videocam_outlined,
    LayerKind.folder => Icons.folder_outlined,
    LayerKind.adjustment => Icons.tune,
  };

  /// The trailing attach tag (기준 rows show none).
  static String? attachTag(Layer layer) {
    if (!isAttachedLayer(layer)) {
      return null;
    }
    return layer.attachedMode == AttachedMode.synced ? 'sync' : 'free';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final markColor = layerMarkColor(layer.mark);
    final textColor = dimmed
        ? theme.colorScheme.onSurfaceVariant
        : selected
        ? accent
        : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: selected ? accent : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (includeDot != null) ...[
              InkWell(
                key: dotKey,
                onTap: onDotTap,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: includeDot! ? accent : null,
                    border: Border.all(
                      color: includeDot! ? accent : theme.dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Container(
              width: 3.5,
              height: 11,
              decoration: BoxDecoration(
                // ⑳: every mark fills, `none` included — it is the paper
                // colour now rather than an absence, so the hairline that
                // used to outline the empty bar has nothing to outline.
                color: markColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              kindIcon(layer.kind),
              size: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                layer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: textColor),
              ),
            ),
            if (trailingTag != null)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(
                  trailingTag!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(Icons.close, size: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A disabled 2-slot mark selector row — 자리 확보 (마크 2중화와 함께
/// 활성). Both slots read "—".
class ExportMarkSlotsRow extends StatelessWidget {
  const ExportMarkSlotsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget slot() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '— ▾',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.disabledColor,
        ),
      ),
    );
    return Tooltip(
      message: 'Mark filters arrive with the two-tier layer marks.',
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              'Mark',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          slot(),
          const SizedBox(width: 5),
          slot(),
        ],
      ),
    );
  }
}
