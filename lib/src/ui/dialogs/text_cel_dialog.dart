import 'package:flutter/material.dart';

import '../../models/text_cel_style.dart';
import '../conte/conte_fonts.dart';
import '../export/export_settings_modules.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_window.dart';
import 'instance_edit_dialog.dart';

/// The TEXT layer's instance editor (R5, §6-s): the cel's parameters —
/// text, face, size, weight, alignment, ink/outline/box — behind the same
/// instance-edit shell every other kind uses. Pops a [TextCelContent], or
/// nothing on cancel. The preview types through the very style the bake
/// renders (engine text both ways), so what the dialog shows is what the
/// canvas gets.
class TextCelDialog extends StatefulWidget {
  const TextCelDialog({
    super.key,
    this.initialContent,
    this.creating = false,
    this.defaultPosition,
  });

  final TextCelContent? initialContent;

  /// Whether a new cel is being written (title wording only).
  final bool creating;

  /// Seed for the position fields when the cel has none yet (the canvas
  /// center, from the active cut).
  final Offset? defaultPosition;

  @override
  State<TextCelDialog> createState() => _TextCelDialogState();
}

class _TextCelDialogState extends State<TextCelDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialContent?.text ?? '',
  );
  late TextCelStyle _style =
      widget.initialContent?.style ?? const TextCelStyle();
  // Only a SAVED anchor seeds the field values — the canvas-center
  // default is a HINT, not a value: committing it as numbers would pin
  // the first line's top at mid-canvas, a different placement than the
  // true null default (block-centered), and re-saving a null-position cel
  // would silently convert it.
  late final TextEditingController _x = TextEditingController(
    text: widget.initialContent?.position?.dx.round().toString() ?? '',
  );
  late final TextEditingController _y = TextEditingController(
    text: widget.initialContent?.position?.dy.round().toString() ?? '',
  );

  /// The ink swatch roster: paper ink, white, the danger red (the アフレコ
  /// vocabulary) and the accent.
  static const List<int> _inkSwatches = [
    0xFF202020,
    0xFFFFFFFF,
    0xFFC95C5C,
    0xFF5C8AC9,
  ];

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _text.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _submit() {
    // A cleared or mistyped field falls back PER AXIS to the saved
    // anchor — never silently re-centering text the user only retyped.
    final saved = widget.initialContent?.position;
    final x = double.tryParse(_x.text.trim()) ?? saved?.dx;
    final y = double.tryParse(_y.text.trim()) ?? saved?.dy;
    Navigator.of(context).pop(
      TextCelContent(
        text: _text.text,
        style: _style,
        position: x != null && y != null ? Offset(x, y) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final theme = Theme.of(context);
    return InstanceEditDialogShell(
      title: widget.creating
          ? strings.textCelNewTitle
          : strings.textCelEditTitle,
      titleIcon: Icons.title_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: strings.textCelTextLabel,
            emphasized: true,
            child: TextField(
              key: const ValueKey<String>('text-cel-text-field'),
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: null,
            ),
          ),
          const SizedBox(height: 10),
          ExportModuleRow(
            label: strings.textCelFontLabel,
            child: Wrap(
              spacing: 4,
              children: [
                ExportChip(
                  key: const ValueKey<String>('text-cel-font-system'),
                  label: strings.textCelFontSystem,
                  selected: _style.fontFamily == null,
                  onTap: () => setState(
                    () => _style = _style.copyWith(fontFamily: null),
                  ),
                ),
                for (final family in const [
                  conteJpFontFamily,
                  conteKrFontFamily,
                ])
                  ExportChip(
                    key: ValueKey<String>('text-cel-font-$family'),
                    label: family,
                    selected: _style.fontFamily == family,
                    onTap: () => setState(
                      () => _style = _style.copyWith(fontFamily: family),
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
                for (final size in const [24.0, 48.0, 96.0, 160.0])
                  ExportChip(
                    key: ValueKey<String>('text-cel-size-${size.round()}'),
                    label: '${size.round()}',
                    selected: _style.fontSize == size,
                    // The outline width is DERIVED from the size — resizing
                    // with the outline on re-derives it, so toggle order
                    // can't bake two different widths for one look.
                    onTap: () => setState(
                      () => _style = _style.copyWith(
                        fontSize: size,
                        outlineWidth: _style.outlineColor == null
                            ? null
                            : (size / 12).clamp(2.0, 8.0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ExportModuleRow(
            label: strings.textCelAlignLabel,
            child: Wrap(
              spacing: 4,
              children: [
                for (final align in TextCelAlign.values)
                  ExportChip(
                    key: ValueKey<String>('text-cel-align-${align.jsonValue}'),
                    label: switch (align) {
                      TextCelAlign.left => strings.textCelAlignLeft,
                      TextCelAlign.center => strings.textCelAlignCenter,
                      TextCelAlign.right => strings.textCelAlignRight,
                    },
                    selected: _style.align == align,
                    onTap: () =>
                        setState(() => _style = _style.copyWith(align: align)),
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
                  _InkSwatch(
                    key: ValueKey<String>(
                      'text-cel-ink-${ink.toRadixString(16)}',
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
          ExportToggleRow(
            widgetKey: const ValueKey<String>('text-cel-bold-toggle'),
            label: strings.textCelBoldLabel,
            value: _style.bold,
            onChanged: (value) =>
                setState(() => _style = _style.copyWith(bold: value)),
          ),
          ExportToggleRow(
            widgetKey: const ValueKey<String>('text-cel-outline-toggle'),
            label: strings.textCelOutlineLabel,
            value: _style.outlineColor != null,
            onChanged: (value) => setState(
              () => _style = _style.copyWith(
                outlineColor: value ? 0xFFFFFFFF : null,
                outlineWidth: value
                    ? (_style.fontSize / 12).clamp(2.0, 8.0)
                    : 0,
              ),
            ),
          ),
          ExportToggleRow(
            widgetKey: const ValueKey<String>('text-cel-background-toggle'),
            label: strings.textCelBackgroundLabel,
            value: _style.backgroundColor != null,
            onChanged: (value) => setState(
              () => _style = _style.copyWith(
                // The アフレコ red box (AppColors.danger).
                backgroundColor: value ? 0xFFC95C5C : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ExportModuleRow(
            label: strings.textCelPositionLabel,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('text-cel-position-x'),
                    controller: _x,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: 'X ',
                      hintText: widget.defaultPosition?.dx.round().toString(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('text-cel-position-y'),
                    controller: _y,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: 'Y ',
                      hintText: widget.defaultPosition?.dy.round().toString(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      preview: Container(
        constraints: const BoxConstraints(minHeight: 56, maxHeight: 120),
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
              _text.text.isEmpty ? ' ' : _text.text,
              key: const ValueKey<String>('text-cel-preview'),
              textAlign: switch (_style.align) {
                TextCelAlign.left => TextAlign.left,
                TextCelAlign.center => TextAlign.center,
                TextCelAlign.right => TextAlign.right,
              },
              style: TextStyle(
                color: _style.colorValue,
                fontSize: _style.fontSize,
                fontWeight: _style.bold ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: _style.letterSpacing == 0
                    ? null
                    : _style.letterSpacing,
                fontFamily: _style.fontFamily,
                fontFamilyFallback: const [
                  conteJpFontFamily,
                  conteKrFontFamily,
                ],
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
      onSubmit: _submit,
    );
  }
}

class _InkSwatch extends StatelessWidget {
  const _InkSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Selection reads as COLOR only (the app's selection grammar — no
    // checkmarks): the accent ring is the selected state.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
