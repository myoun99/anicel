import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'staff_process_folds.dart';

/// 컷 설정 — who does each stage's work on the cuts it is about: a name per
/// colour label a cut keeps — every stage but the conte's, the work's
/// (유저 2026-10-08, F-291-Q1: 「원화 작업자나 시아게는 컷마다 다름 …
/// 나머진 컷마다 스태프설정」). Pops the stages whose names were changed,
/// or null when cancelled: every other stage keeps each cut's own.
class CutSettingsWindow extends StatefulWidget {
  const CutSettingsWindow({super.key, required this.cutStaff});

  /// The cut's own names, by label slug (`CutMetadata.staff`).
  final Map<String, String> cutStaff;

  @override
  State<CutSettingsWindow> createState() => _CutSettingsWindowState();
}

class _CutSettingsWindowState extends State<CutSettingsWindow> {
  late final Map<LayerMark, TextEditingController> _staff = staffFieldsOf(
    _cutNameFor,
    holder: StaffHolder.cut,
  );

  String _cutNameFor(LayerMark mark) => widget.cutStaff[mark.keySlug] ?? '';

  @override
  void dispose() {
    for (final field in _staff.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(<LayerMark, String>{
      for (final MapEntry(key: mark, value: field) in _staff.entries)
        if (field.text.trim() != _cutNameFor(mark)) mark: field.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('cut-settings-window'),
      title: strings.cutSettingsTitle,
      titleIcon: Icons.tune,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      // ⛔No scroller of its own: `AppWindow` scrolls its body.
      body: SizedBox(
        width: 400,
        child: StaffProcessFolds(
          fields: _staff,
          keyPrefix: 'cut-settings',
          onSubmitted: _submit,
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('cut-settings-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('cut-settings-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
