import 'package:flutter/material.dart';

import '../../models/timesheet_info.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// Edits the sheet-header text (title/episode/scene/artist) the paper
/// timesheet reads, and which header boxes the form prints. Pops the
/// edited [TimesheetInfo], or null when cancelled.
class TimesheetInfoDialog extends StatefulWidget {
  const TimesheetInfoDialog({super.key, required this.initialInfo});

  final TimesheetInfo initialInfo;

  @override
  State<TimesheetInfoDialog> createState() => _TimesheetInfoDialogState();
}

class _TimesheetInfoDialogState extends State<TimesheetInfoDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialInfo.title,
  );
  late final TextEditingController _episodeController = TextEditingController(
    text: widget.initialInfo.episode,
  );
  late final TextEditingController _sceneController = TextEditingController(
    text: widget.initialInfo.scene,
  );
  late final TextEditingController _artistController = TextEditingController(
    text: widget.initialInfo.artist,
  );
  late final Set<TimesheetHeaderField> _hiddenFields = {
    ...widget.initialInfo.hiddenFields,
  };
  late bool _exposureBarEnabled =
      widget.initialInfo.exposureBarThreshold != null;
  late final TextEditingController
  _exposureBarThresholdController = TextEditingController(
    text:
        '${widget.initialInfo.exposureBarThreshold ?? TimesheetInfo.defaultExposureBarThreshold}',
  );
  late bool _seEmptyFill = widget.initialInfo.seEmptyFill;

  static String _fieldLabel(TimesheetHeaderField field) {
    final strings = AppText.strings;
    return switch (field) {
      TimesheetHeaderField.title => strings.sheetFieldTitle,
      TimesheetHeaderField.episode => strings.sheetFieldEpisode,
      TimesheetHeaderField.scene => strings.sheetFieldScene,
      TimesheetHeaderField.cut => strings.sheetFieldCut,
      TimesheetHeaderField.time => strings.sheetFieldTime,
      TimesheetHeaderField.name => strings.sheetFieldName,
      TimesheetHeaderField.sheet => strings.sheetFieldSheet,
    };
  }

  @override
  void dispose() {
    _titleController.dispose();
    _episodeController.dispose();
    _sceneController.dispose();
    _artistController.dispose();
    _exposureBarThresholdController.dispose();
    super.dispose();
  }

  void _submit() {
    final threshold = int.tryParse(_exposureBarThresholdController.text.trim());
    Navigator.of(context).pop(
      TimesheetInfo(
        title: _titleController.text.trim(),
        episode: _episodeController.text.trim(),
        scene: _sceneController.text.trim(),
        artist: _artistController.text.trim(),
        hiddenFields: {..._hiddenFields},
        exposureBarThreshold: _exposureBarEnabled && threshold != null
            ? threshold.clamp(1, 999)
            : _exposureBarEnabled
            ? TimesheetInfo.defaultExposureBarThreshold
            : null,
        seEmptyFill: _seEmptyFill,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('timesheet-info-dialog'),
      title: strings.sheetInfoTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      body: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppWindowField(
                label: strings.sheetFieldTitle,
                emphasized: true,
                child: TextField(
                  key: const ValueKey<String>('timesheet-info-title-field'),
                  controller: _titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: strings.sheetTitleHint,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppWindowField(
                label: strings.sheetFieldEpisode,
                child: TextField(
                  key: const ValueKey<String>('timesheet-info-episode-field'),
                  controller: _episodeController,
                ),
              ),
              const SizedBox(height: 12),
              AppWindowField(
                label: strings.sheetFieldScene,
                child: TextField(
                  key: const ValueKey<String>('timesheet-info-scene-field'),
                  controller: _sceneController,
                ),
              ),
              const SizedBox(height: 12),
              AppWindowField(
                label: strings.sheetArtist,
                child: TextField(
                  key: const ValueKey<String>('timesheet-info-artist-field'),
                  controller: _artistController,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                strings.sheetVisibleBoxes,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final field in TimesheetHeaderField.values)
                    FilterChip(
                      key: ValueKey<String>(
                        'timesheet-info-visible-${field.name}',
                      ),
                      label: Text(_fieldLabel(field)),
                      selected: !_hiddenFields.contains(field),
                      onSelected: (visible) => setState(() {
                        if (visible) {
                          _hiddenFields.remove(field);
                        } else {
                          _hiddenFields.add(field);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                strings.sheetNotation,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              SwitchListTile(
                key: const ValueKey<String>('timesheet-info-exposure-bar'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(strings.sheetExposureBar),
                subtitle: Text(strings.sheetExposureBarHelp),
                value: _exposureBarEnabled,
                onChanged: (value) =>
                    setState(() => _exposureBarEnabled = value),
              ),
              if (_exposureBarEnabled)
                AppWindowField(
                  label: strings.sheetExposureBarN,
                  child: TextField(
                    key: const ValueKey<String>(
                      'timesheet-info-exposure-bar-threshold',
                    ),
                    controller: _exposureBarThresholdController,
                    keyboardType: TextInputType.number,
                  ),
                ),
              SwitchListTile(
                key: const ValueKey<String>('timesheet-info-se-empty-fill'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(strings.sheetSeEmptyFill),
                value: _seEmptyFill,
                onChanged: (value) => setState(() => _seEmptyFill = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('timesheet-info-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('timesheet-info-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
