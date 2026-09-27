import 'package:flutter/material.dart';

import '../../models/timesheet_info.dart';
import '../export/export_settings_modules.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// 「타임시트 서식」: how the paper timesheet prints — which header boxes it
/// carries, the hold bar, the SE wash. Pops the edited [TimesheetInfo], or
/// null when cancelled.
///
/// ⛔The work's words are not here: its title, episode and staff are set in
/// the work's settings (`WorkSettingsWindow`, 유저 09-25 「작품명/화수는
/// 이제 타임시트패널같은곳에서 편집안하게 … 해당 설정은 프로젝트 설정쪽에」).
/// The sheet's own format stays with the sheet's panel (유저 09-25: 「이거는
/// 버튼둬서 바꿀수있게. 타임시트 서식 변경? 뭐 이런 버튼 둬서 창 열어서
/// 관련된거 편집하는창」).
///
/// Every choice is the export window's pill (유저 09-25: 「시트나 머리칸이나
/// 이런 설정 토글은 기존 출력창의 토글같은거 버튼 재사용해서 알기쉽게」):
/// the header boxes are one strip with several on at once, and each yes/no
/// is one [ExportTogglePill].
class TimesheetFormatWindow extends StatefulWidget {
  const TimesheetFormatWindow({super.key, required this.initialInfo});

  final TimesheetInfo initialInfo;

  @override
  State<TimesheetFormatWindow> createState() => _TimesheetFormatWindowState();
}

class _TimesheetFormatWindowState extends State<TimesheetFormatWindow> {
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

  void _toggleField(TimesheetHeaderField field) => setState(() {
    if (!_hiddenFields.remove(field)) {
      _hiddenFields.add(field);
    }
  });

  Widget _headerBoxes() => ExportPillStrip(
    items: [
      for (final field in TimesheetHeaderField.values)
        ExportPillItem(
          keyValue: 'timesheet-format-visible-${field.name}',
          label: _fieldLabel(field),
          selected: !_hiddenFields.contains(field),
          onTap: () => _toggleField(field),
        ),
    ],
  );

  Widget _holdBar() {
    final strings = AppText.strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExportTogglePill(
          keyValue: 'timesheet-format-exposure-bar',
          on: _exposureBarEnabled,
          words: (on: strings.sheetBarDrawn, off: strings.sheetBarNotDrawn),
          onChanged: (on) => setState(() => _exposureBarEnabled = on),
        ),
        const SizedBox(width: 12),
        // The threshold keeps its place while the bar is off, refusing
        // input rather than leaving (「없다가 생기는 UI 금지」) — it used to
        // appear only once the bar was switched on.
        AppTooltip(
          message: strings.sheetExposureBarHelp,
          child: SizedBox(
            width: 72,
            child: TextField(
              key: const ValueKey<String>(
                'timesheet-format-exposure-bar-threshold',
              ),
              controller: _exposureBarThresholdController,
              enabled: _exposureBarEnabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(prefixText: 'N  '),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('timesheet-format-window'),
      title: strings.sheetFormatTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      // ⛔The body does NOT bring its own scroller. `AppWindow` already
      // scrolls it, and it applies the body padding OUTSIDE that scroller —
      // so the window's bar lands on 12px of dead padding, while a bar
      // belonging to a scroller in HERE would lie across the right edge of
      // every field and swallow the taps that focus them.
      body: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            AppWindowField(
              label: strings.sheetVisibleBoxes,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _headerBoxes(),
              ),
            ),
            AppWindowField(
              label: strings.sheetExposureBar,
              child: Align(alignment: Alignment.centerLeft, child: _holdBar()),
            ),
            AppWindowField(
              label: strings.sheetSeEmptyFill,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ExportTogglePill(
                  keyValue: 'timesheet-format-se-empty-fill',
                  on: _seEmptyFill,
                  words: (on: strings.sheetFillOn, off: strings.sheetFillOff),
                  onChanged: (on) => setState(() => _seEmptyFill = on),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('timesheet-format-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('timesheet-format-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
