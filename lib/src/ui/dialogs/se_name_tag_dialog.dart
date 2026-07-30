import 'package:flutter/material.dart';

import '../../models/se_name_tag.dart';
import '../../models/text_cel_style.dart';
import '../export/export_settings_modules.dart';
import '../text/app_strings.dart';
import 'instance_edit_dialog.dart';

/// What the SE name tag dialog resolved to: the tag, or a RESET (null
/// tag) putting the row back on the stacked default.
class SeNameTagDialogResult {
  const SeNameTagDialogResult(this.tag);

  final SeNameTag? tag;
}

/// The SE row's ON-CANVAS name tag editor (R5b, §6-z15): where this
/// speaker's アフレコ label sits on the picture and how it looks. The
/// tag's TEXT is not here — it is the SE block's own name and dialogue,
/// edited on the cell like always; this window places and styles it.
class SeNameTagDialog extends StatefulWidget {
  const SeNameTagDialog({super.key, required this.initialTag, this.rowName});

  /// The row's current tag, or the stacked default it draws with today.
  final SeNameTag initialTag;

  /// The SE row's name (S1/S2…) for the title.
  final String? rowName;

  @override
  State<SeNameTagDialog> createState() => _SeNameTagDialogState();
}

class _SeNameTagDialogState extends State<SeNameTagDialog> {
  late TextCelStyle _style = widget.initialTag.style;
  late final TextEditingController _x = TextEditingController(
    text: widget.initialTag.position.dx.round().toString(),
  );
  late final TextEditingController _y = TextEditingController(
    text: widget.initialTag.position.dy.round().toString(),
  );

  /// The tag's ink roster: white (on the red box), paper ink, and the
  /// two accents.
  static const List<int> _inkSwatches = [
    0xFFFFFFFF,
    0xFF202020,
    0xFFC95C5C,
    0xFF5C8AC9,
  ];

  /// The box roster: the danger red (the アフレコ default), black, and
  /// none.
  static const List<int?> _boxSwatches = [0xFFC95C5C, 0xFF202020, null];

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _submit() {
    final position = Offset(
      double.tryParse(_x.text.trim()) ?? widget.initialTag.position.dx,
      double.tryParse(_y.text.trim()) ?? widget.initialTag.position.dy,
    );
    Navigator.of(
      context,
    ).pop(SeNameTagDialogResult(SeNameTag(position: position, style: _style)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final theme = Theme.of(context);
    final rowName = widget.rowName;
    return InstanceEditDialogShell(
      title: rowName == null
          ? strings.seNameTagTitle
          : '${strings.seNameTagTitle} — $rowName',
      titleIcon: Icons.badge_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.seNameTagHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          ExportModuleRow(
            label: strings.seNameTagPositionLabel,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('se-name-tag-position-x'),
                    controller: _x,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: 'X ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('se-name-tag-position-y'),
                    controller: _y,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: 'Y ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ExportModuleRow(
            label: strings.textCelSizeLabel,
            child: Wrap(
              spacing: 4,
              children: [
                for (final size in const [24.0, 34.0, 48.0, 72.0])
                  ExportChip(
                    key: ValueKey<String>('se-name-tag-size-${size.round()}'),
                    label: '${size.round()}',
                    selected: _style.fontSize == size,
                    onTap: () => setState(
                      () => _style = _style.copyWith(fontSize: size),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ExportModuleRow(
            label: strings.textCelColorLabel,
            child: Wrap(
              spacing: 6,
              children: [
                for (final ink in _inkSwatches)
                  _Swatch(
                    key: ValueKey<String>(
                      'se-name-tag-ink-${ink.toRadixString(16)}',
                    ),
                    color: Color(ink),
                    selected: _style.color == ink,
                    onTap: () =>
                        setState(() => _style = _style.copyWith(color: ink)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ExportModuleRow(
            label: strings.seNameTagBoxLabel,
            child: Wrap(
              spacing: 6,
              children: [
                for (final box in _boxSwatches)
                  _Swatch(
                    key: ValueKey<String>(
                      'se-name-tag-box-${box?.toRadixString(16) ?? 'none'}',
                    ),
                    color: box == null ? null : Color(box),
                    selected: _style.backgroundColor == box,
                    onTap: () => setState(
                      () => _style = _style.copyWith(backgroundColor: box),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ExportToggleRow(
            widgetKey: const ValueKey<String>('se-name-tag-bold-toggle'),
            label: strings.textCelBoldLabel,
            value: _style.bold,
            onChanged: (value) =>
                setState(() => _style = _style.copyWith(bold: value)),
          ),
        ],
      ),
      preview: Container(
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 96),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            color: _style.backgroundColorValue,
            padding: _style.backgroundColor == null
                ? EdgeInsets.zero
                : const EdgeInsets.all(6),
            child: Text(
              '[${strings.seNameTagSampleName}] ${strings.seNameTagSampleLine}',
              key: const ValueKey<String>('se-name-tag-preview'),
              style: TextStyle(
                color: _style.colorValue,
                fontSize: _style.fontSize,
                fontWeight: _style.bold ? FontWeight.w700 : FontWeight.w400,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
      // Delete = reset to the stacked default (the field's null contract).
      onDelete: () =>
          Navigator.of(context).pop(const SeNameTagDialogResult(null)),
      onSubmit: _submit,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// Null draws the "no box" slot.
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: color != null
            ? null
            : Icon(Icons.block, size: 12, color: scheme.outline),
      ),
    );
  }
}
