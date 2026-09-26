import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../../models/timesheet_info.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';

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

  /// One name field per 공정's worker — the colour label with no
  /// correction, which the cut envelope binds by (`{staff.<label>.name}`).
  ///
  /// ⛔EVERY process gets a row, including 用紙. Leaving one out would be a
  /// 「~는 제외한다」 rule nobody asked for, and an empty row costs a line
  /// while a missing one costs a question — the same reason a rail row
  /// reserves every slot.
  late final Map<LayerMark, TextEditingController> _staffControllers = {
    for (final process in LayerProcess.values)
      LayerMark(process: process): TextEditingController(
        text: widget.initialInfo.staffNameFor(LayerMark(process: process)),
      ),
  };

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
    for (final controller in _staffControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final threshold = int.tryParse(_exposureBarThresholdController.text.trim());
    var staffed = widget.initialInfo;
    for (final entry in _staffControllers.entries) {
      staffed = staffed.withStaffName(entry.key, entry.value.text.trim());
    }
    // 🚨★★★copyWith, NOT a fresh TimesheetInfo. Building one from scratch
    // listed the fields this dialog edits and silently dropped every field
    // it does not — `staff` and `logoAssetPath` both default to empty, so
    // opening this window and pressing save WIPED the production staff and
    // the logo. Nothing said so; they simply were not there afterwards.
    //
    // ⛔A re-construction cannot be made safe by remembering to add the
    // next field: remembering is the part that failed. `copyWith` carries
    // what it was not asked about ([[make-the-invariant-unrepresentable]]).
    Navigator.of(context).pop(
      staffed.copyWith(
        title: _titleController.text.trim(),
        episode: _episodeController.text.trim(),
        scene: _sceneController.text.trim(),
        artist: _artistController.text.trim(),
        hiddenFields: {..._hiddenFields},
        exposureBarThreshold: () => _exposureBarEnabled && threshold != null
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
      // ⛔The body does NOT bring its own scroller. `AppWindow` already
      // scrolls it, and it applies the body padding OUTSIDE that scroller —
      // so the window's bar lands on 12px of dead padding, while a bar
      // belonging to a scroller in HERE would lie across the right edge of
      // every field and swallow the taps that focus them.
      body: SizedBox(
        width: 360,
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
                decoration: InputDecoration(hintText: strings.sheetTitleHint),
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
              strings.sheetStaffByProcess,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            // 🚨One row per 공정, always all of them — the cut envelope binds
            // `{staff.<label>.name}` by this same key, so what the form can
            // fill and what a form can print are one list.
            for (final entry in _staffControllers.entries) ...[
              AppWindowField(
                label: entry.key.displayName,
                child: TextField(
                  key: ValueKey<String>(
                    'timesheet-info-staff-${entry.key.keySlug}',
                  ),
                  controller: entry.value,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            Text(
              strings.sheetVisibleBoxes,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            // The app's one boolean (guide-sym ⑥⑧: 「진짜 불리언값 모든곳에
            // 적용」). These were FilterChips, which mark ON with a check — the
            // mark 「선택 표시는 색상만」 names — and did not claim their press
            // in a window that scrolls.
            for (final field in TimesheetHeaderField.values)
              SettingsSwitchRow(
                tileKey: ValueKey<String>(
                  'timesheet-info-visible-${field.name}',
                ),
                label: _fieldLabel(field),
                value: !_hiddenFields.contains(field),
                onChanged: (visible) => setState(() {
                  if (visible) {
                    _hiddenFields.remove(field);
                  } else {
                    _hiddenFields.add(field);
                  }
                }),
              ),
            const SizedBox(height: 16),
            Text(
              strings.sheetNotation,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('timesheet-info-exposure-bar'),
              label: strings.sheetExposureBar,
              help: strings.sheetExposureBarHelp,
              value: _exposureBarEnabled,
              onChanged: (value) => setState(() => _exposureBarEnabled = value),
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
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('timesheet-info-se-empty-fill'),
              label: strings.sheetSeEmptyFill,
              value: _seEmptyFill,
              onChanged: (value) => setState(() => _seEmptyFill = value),
            ),
          ],
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
