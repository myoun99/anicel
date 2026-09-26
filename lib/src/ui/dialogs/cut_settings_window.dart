import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'staff_process_folds.dart';

/// 컷 설정 — who does each stage's work on the cuts it is about: a name per
/// colour label, the work's own shown faintly where the cut names nobody
/// (유저 09-25: 작품 설정에는 기본값, 컷 설정에는 컷별 이름 —
/// [[project-settings-window]]). Pops the stages whose names were changed,
/// or null when cancelled: every other stage keeps each cut's own.
class CutSettingsWindow extends StatefulWidget {
  const CutSettingsWindow({
    super.key,
    required this.cutStaff,
    required this.workStaff,
  });

  /// The cut's own names, by label slug (`CutMetadata.staff`).
  final Map<String, String> cutStaff;

  /// The work's names, by label slug (`TimesheetInfo.staff`) — what the
  /// forms print for a stage the cut does not name.
  final Map<String, String> workStaff;

  @override
  State<CutSettingsWindow> createState() => _CutSettingsWindowState();
}

class _CutSettingsWindowState extends State<CutSettingsWindow> {
  late final Map<LayerMark, TextEditingController> _staff = staffFieldsOf(
    _cutNameFor,
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
          hintFor: (mark) => widget.workStaff[mark.keySlug],
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
