import 'package:flutter/material.dart';

import '../../models/timesheet_info.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';

/// Edits how the paper timesheet prints: which header boxes it carries,
/// the hold bar, the SE wash. Pops the edited [TimesheetInfo], or null when
/// cancelled.
///
/// ⛔The work's words are not here: its title, episode and staff are set in
/// the work's settings (`WorkSettingsWindow`, 유저 09-25 「작품명/화수는
/// 이제 타임시트패널같은곳에서 편집안하게 … 해당 설정은 프로젝트 설정쪽에」).
class TimesheetInfoDialog extends StatefulWidget {
  const TimesheetInfoDialog({super.key, required this.initialInfo});

  final TimesheetInfo initialInfo;

  @override
  State<TimesheetInfoDialog> createState() => _TimesheetInfoDialogState();
}

class _TimesheetInfoDialogState extends State<TimesheetInfoDialog> {
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
    _exposureBarThresholdController.dispose();
    super.dispose();
  }

  void _submit() {
    final threshold = int.tryParse(_exposureBarThresholdController.text.trim());
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
      widget.initialInfo.copyWith(
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
