import 'package:flutter/material.dart';

import '../../models/cut_metadata.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'dialog_verb.dart';
import 'staff_process_folds.dart';

/// What 컷 설정's 저장 gives: the stages whose [names] were changed — every
/// other stage keeps each cut's own — and the folds it was saved with
/// ([openFolds], F-291-Q4 「파일에, 저장 버튼을 누를 때만」).
typedef CutSettingsSave = ({
  Map<LayerMark, String> names,
  Set<LayerProcess> openFolds,
});

/// 컷 설정 — who does each stage's work on the cuts it is about: a name per
/// colour label a cut keeps — every stage but the conte's, the work's
/// (유저 2026-10-08, F-291-Q1: 「원화 작업자나 시아게는 컷마다 다름 …
/// 나머진 컷마다 스태프설정」). Opens on [cut]'s names and folds; pops a
/// [CutSettingsSave], or null when cancelled.
class CutSettingsWindow extends StatefulWidget {
  const CutSettingsWindow({super.key, required this.cut});

  /// The first addressed cut's: its own names, by label slug
  /// (`CutMetadata.staff`), and the folds it was last saved with.
  final CutMetadata cut;

  @override
  State<CutSettingsWindow> createState() => _CutSettingsWindowState();
}

class _CutSettingsWindowState extends State<CutSettingsWindow> {
  late final Map<LayerMark, TextEditingController> _staff = staffFieldsOf(
    widget.cut.staffNameFor,
    holder: StaffHolder.cut,
  );

  late Set<LayerProcess> _open = widget.cut.openStaffFolds;

  @override
  void dispose() {
    for (final field in _staff.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop<CutSettingsSave>((
      names: {
        for (final MapEntry(key: mark, value: field) in _staff.entries)
          if (field.text.trim() != widget.cut.staffNameFor(mark))
            mark: field.text.trim(),
      },
      openFolds: _open,
    ));
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
          open: widget.cut.openStaffFolds,
          onOpenChanged: (open) => _open = open,
        ),
      ),
      actions: saveActions(context, prefix: 'cut-settings', onSave: _submit),
    );
  }
}
