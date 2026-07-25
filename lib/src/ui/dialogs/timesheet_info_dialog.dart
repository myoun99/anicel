import 'package:flutter/material.dart';

import '../../models/timesheet_info.dart';
import '../widgets/app_window.dart';

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

  static const Map<TimesheetHeaderField, String> _fieldLabels = {
    TimesheetHeaderField.title: 'Title',
    TimesheetHeaderField.episode: 'Episode',
    TimesheetHeaderField.scene: 'Scene',
    TimesheetHeaderField.cut: 'Cut',
    TimesheetHeaderField.time: 'Time',
    TimesheetHeaderField.name: 'Name',
    TimesheetHeaderField.sheet: 'Sheet',
  };

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
    return AppWindow(
      windowKey: const ValueKey<String>('timesheet-info-dialog'),
      title: 'Sheet info',
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      body: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey<String>('timesheet-info-title-field'),
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Project name when empty',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('timesheet-info-episode-field'),
                controller: _episodeController,
                decoration: const InputDecoration(labelText: 'Episode'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('timesheet-info-scene-field'),
                controller: _sceneController,
                decoration: const InputDecoration(labelText: 'Scene'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('timesheet-info-artist-field'),
                controller: _artistController,
                decoration: const InputDecoration(labelText: 'Artist'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Text(
                'Visible Boxes',
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
                      label: Text(_fieldLabels[field]!),
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
              Text('Notation', style: Theme.of(context).textTheme.labelMedium),
              SwitchListTile(
                key: const ValueKey<String>('timesheet-info-exposure-bar'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Exposure hold bar'),
                subtitle: const Text(
                  'Draw the hold bar from the (N+1)th comma of N+ holds',
                ),
                value: _exposureBarEnabled,
                onChanged: (value) =>
                    setState(() => _exposureBarEnabled = value),
              ),
              if (_exposureBarEnabled)
                TextField(
                  key: const ValueKey<String>(
                    'timesheet-info-exposure-bar-threshold',
                  ),
                  controller: _exposureBarThresholdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'N (industry standard 3)',
                    isDense: true,
                  ),
                ),
              SwitchListTile(
                key: const ValueKey<String>('timesheet-info-se-empty-fill'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Gray out empty SE stretches'),
                value: _seEmptyFill,
                onChanged: (value) => setState(() => _seEmptyFill = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: 'Cancel',
          actionKey: const ValueKey<String>('timesheet-info-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: 'Save',
          actionKey: const ValueKey<String>('timesheet-info-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
