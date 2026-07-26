import 'package:flutter/material.dart';

import '../../models/export_preset.dart';
import '../../models/export_size_mode.dart';
import '../../models/export_spec.dart';
import '../dialogs/app_prompt_dialog.dart';
import 'export_settings_modules.dart';
import '../text/app_strings.dart';

/// The left drawer: per-tab presets (자동 규칙만). Selection highlight is
/// value equality against the live spec — editing any knob visibly
/// "leaves" the preset, applying one snaps back. Color only, no marks.
class ExportPresetRail extends StatelessWidget {
  const ExportPresetRail({
    super.key,
    required this.tab,
    required this.presets,
    required this.currentSpec,
    required this.enabled,
    required this.onApply,
    required this.onSaveCurrent,
    required this.onDelete,
  });

  final ExportTab tab;
  final List<ExportPreset> presets;
  final ExportTabSpec currentSpec;
  final bool enabled;
  final ValueChanged<ExportPreset> onApply;
  final VoidCallback onSaveCurrent;
  final ValueChanged<ExportPreset> onDelete;

  static String tabLabel(ExportTab tab) => switch (tab) {
    ExportTab.sequence => 'Sequence',
    ExportTab.image => AppText.strings.exImage,
    ExportTab.cels => AppText.strings.exCels,
    ExportTab.timesheet => 'Timesheet',
  };

  /// One-line rule summary under the preset name.
  static String describe(ExportTabSpec spec) => switch (spec) {
    SequenceExportSpec() =>
      '${ExportFormatModule.summarize(spec.format)} · '
          '${spec.sizeMode == ExportSizeMode.camera ? 'Camera' : 'Canvas'}',
    ImageExportSpec() => ExportFormatModule.summarize(spec.format),
    CelsExportSpec() =>
      '${ExportFormatModule.summarize(spec.format)}'
          '${spec.onTimesheetOnly ? ' · sheet only' : ''}',
    TimesheetExportSpec() => switch (spec.format) {
      ExportTimesheetFormat.sheetImage => 'Sheet image',
      ExportTimesheetFormat.xdts => 'XDTS',
    },
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            'PRESETS · ${tabLabel(tab).toUpperCase()}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              letterSpacing: 1.1,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (final preset in presets)
                _PresetEntry(
                  preset: preset,
                  selected: preset.spec == currentSpec,
                  enabled: enabled,
                  onApply: () => onApply(preset),
                  onDelete: () => onDelete(preset),
                ),
              InkWell(
                key: const ValueKey<String>('export-preset-save-current'),
                onTap: enabled ? onSaveCurrent : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.dividerColor,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+ Save current…',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: enabled
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.disabledColor,
                    ),
                  ),
                ),
              ),
              if (presets.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                  child: Text(
                    'Saved setups appear here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetEntry extends StatelessWidget {
  const _PresetEntry({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onApply,
    required this.onDelete,
  });

  final ExportPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return InkWell(
      key: ValueKey<String>('export-preset-${preset.id.value}'),
      onTap: enabled ? onApply : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.fromLTRB(7, 3, 4, 4),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: selected ? accent : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? accent : null,
                    ),
                  ),
                  Text(
                    ExportPresetRail.describe(preset.spec),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              key: ValueKey<String>('export-preset-delete-${preset.id.value}'),
              onTap: enabled ? onDelete : null,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "+ Save current…" name prompt.
Future<String?> showExportPresetNameDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => AppPromptDialog(
      windowKey: const ValueKey<String>('export-preset-name-dialog'),
      title: AppText.strings.exSavePreset,
      titleIcon: Icons.bookmark_add_outlined,
      fieldLabel: AppText.strings.brName,
      initialValue: '',
      confirmLabel: AppText.strings.commonSave,
      emptyError: AppText.strings.exPresetNameEmpty,
      fieldKey: const ValueKey<String>('export-preset-name-field'),
      confirmKey: const ValueKey<String>('export-preset-name-save'),
    ),
  );
}
