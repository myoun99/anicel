import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../timeline/instruction_icon_palette.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// Edits the project's instruction vocabulary: rename defs, repick their
/// icons, add custom ones, delete. Pops the edited [CameraInstructionSet]
/// (or nothing on cancel); the caller commits it as one undo step.
///
/// Deleting a def leaves events referencing it dangling by design — they
/// render with the fallback glyph and the raw id, nothing breaks.
class InstructionSetEditorDialog extends StatefulWidget {
  const InstructionSetEditorDialog({super.key, required this.initialSet});

  final CameraInstructionSet initialSet;

  @override
  State<InstructionSetEditorDialog> createState() =>
      _InstructionSetEditorDialogState();
}

class _InstructionSetEditorDialogState
    extends State<InstructionSetEditorDialog> {
  late List<CameraInstructionDef> _defs = [...widget.initialSet.defs];

  String _nextCustomId() {
    final used = _defs.map((def) => def.id).toSet();
    var index = 1;
    while (used.contains('custom-$index')) {
      index += 1;
    }
    return 'custom-$index';
  }

  Future<void> _editDef(int index) async {
    final edited = await showDialog<CameraInstructionDef>(
      context: context,
      builder: (context) => _InstructionDefDialog(def: _defs[index]),
    );
    if (edited == null || !mounted) {
      return;
    }
    setState(() => _defs = [..._defs]..[index] = edited);
  }

  Future<void> _addDef() async {
    final created = await showDialog<CameraInstructionDef>(
      context: context,
      builder: (context) => _InstructionDefDialog(
        def: CameraInstructionDef(
          id: _nextCustomId(),
          name: '',
          iconKey: 'note',
        ),
      ),
    );
    if (created == null || !mounted || created.name.trim().isEmpty) {
      return;
    }
    setState(() => _defs = [..._defs, created]);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('instruction-set-dialog'),
      title: strings.instructionsTitle,
      titleIcon: Icons.videocam_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      height: 520,
      scrollBody: false,
      body: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _defs.length,
                itemBuilder: (context, index) {
                  final def = _defs[index];
                  return ListTile(
                    key: ValueKey<String>('instruction-def-row-${def.id}'),
                    dense: true,
                    leading: Icon(
                      instructionIconFor(def.iconKey),
                      size: 20,
                      color: def.colorValue == null
                          ? null
                          : Color(def.colorValue!),
                    ),
                    title: Text(def.name),
                    onTap: () => _editDef(index),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: ValueKey<String>(
                            'instruction-def-edit-${def.id}',
                          ),
                          tooltip: strings.instructionEditTooltip,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _editDef(index),
                        ),
                        IconButton(
                          key: ValueKey<String>(
                            'instruction-def-delete-${def.id}',
                          ),
                          tooltip: strings.instructionDeleteTooltip,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => setState(
                            () => _defs = [..._defs]..removeAt(index),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>('instruction-def-add-button'),
                onPressed: _addDef,
                icon: const Icon(Icons.add, size: 16),
                label: Text(strings.instructionAddButton),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('instruction-set-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('instruction-set-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () =>
              Navigator.of(context).pop(CameraInstructionSet(defs: _defs)),
        ),
      ],
    );
  }
}

/// Edits one def: the sheet label, an icon from the curated palette and the
/// span mark (duration line / FI / FO / O.L) — the user pairs any of them
/// with any name, which is the customization point.
class _InstructionDefDialog extends StatefulWidget {
  const _InstructionDefDialog({required this.def});

  final CameraInstructionDef def;

  @override
  State<_InstructionDefDialog> createState() => _InstructionDefDialogState();
}

/// Preset chip tints (readable on the dark theme); null = the default
/// row text color.
const List<int> instructionColorPalette = [
  0xFFE57373, // red
  0xFFFFB74D, // orange
  0xFFFFF176, // yellow
  0xFF81C784, // green
  0xFF4DB6AC, // teal
  0xFF64B5F6, // blue
  0xFFBA68C8, // purple
  0xFFF06292, // pink
];

/// Display labels for the mark picker; the shapes themselves live in the
/// row/sheet painters.
const Map<CameraInstructionMarkType, String> _markLabels = {
  CameraInstructionMarkType.bar: 'A⊢─⊣B',
  CameraInstructionMarkType.fi: 'FI ▷',
  CameraInstructionMarkType.fo: '◁ FO',
  CameraInstructionMarkType.ol: 'O.L ⋈',
};

class _InstructionDefDialogState extends State<_InstructionDefDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.def.name,
  );
  late String _iconKey = widget.def.iconKey;
  late int? _colorValue = widget.def.colorValue;
  late CameraInstructionMarkType _markType = widget.def.markType;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = AppText.strings;
    // The body scrolls: the option sections outgrow short screens.
    return AppWindow(
      windowKey: const ValueKey<String>('instruction-def-dialog'),
      title: strings.instructionDefTitle,
      titleIcon: Icons.edit_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 400,
      body: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppWindowField(
                label: strings.instructionDefNameLabel,
                emphasized: true,
                child: TextField(
                  key: const ValueKey<String>('instruction-def-name-field'),
                  controller: _nameController,
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Icon',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in instructionIconPalette.entries)
                    InkWell(
                      key: ValueKey<String>('instruction-icon-${entry.key}'),
                      onTap: () => setState(() => _iconKey = entry.key),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _iconKey == entry.key
                                ? colorScheme.secondary
                                : colorScheme.outlineVariant,
                            width: _iconKey == entry.key ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(entry.value, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Color',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  // Default = no tint: the chip uses the row text color.
                  InkWell(
                    key: const ValueKey<String>('instruction-color-default'),
                    onTap: () => setState(() => _colorValue = null),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _colorValue == null
                              ? colorScheme.secondary
                              : colorScheme.outlineVariant,
                          width: _colorValue == null ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.format_color_reset_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final color in instructionColorPalette)
                    InkWell(
                      key: ValueKey<String>(
                        'instruction-color-${color.toRadixString(16)}',
                      ),
                      onTap: () => setState(() => _colorValue = color),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(color),
                          border: Border.all(
                            color: _colorValue == color
                                ? colorScheme.secondary
                                : colorScheme.outlineVariant,
                            width: _colorValue == color ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mark',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: 4),
              // How this term's spans draw on rows and the printed sheet:
              // straight duration line, FI/FO fade wedge or O.L bowtie.
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in _markLabels.entries)
                    InkWell(
                      key: ValueKey<String>(
                        'instruction-mark-${entry.key.jsonValue}',
                      ),
                      onTap: () => setState(() => _markType = entry.key),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _markType == entry.key
                                ? colorScheme.secondary
                                : colorScheme.outlineVariant,
                            width: _markType == entry.key ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            entry.value,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('instruction-def-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('instruction-def-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(
            widget.def.copyWith(
              name: _nameController.text.trim(),
              iconKey: _iconKey,
              colorValue: () => _colorValue,
              markType: _markType,
            ),
          ),
        ),
      ],
    );
  }
}
