import 'package:flutter/material.dart';

import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/drag_value_label.dart';

/// 자동 이름 지정's one question (I-18): the number the first block takes.
///
/// 🗣️I-18 (유저): 「누르면 숫자 편집하는 창 나와서 숫자만 입력가능. 드래그로
/// 조절하거나 수동입력. 기본값은 1인상태」. The number is the app's operable
/// readout ([DragValueLabel]) — a drag along it moves it, a tap types it,
/// digits alone — and it opens at 1 EVERY time: 「기본값은 1인상태」 names
/// where it starts, not a number it keeps.
///
/// Pops the number on Apply, nothing on Cancel.
class StartNumberWindow extends StatefulWidget {
  const StartNumberWindow({super.key});

  @override
  State<StartNumberWindow> createState() => _StartNumberWindowState();
}

class _StartNumberWindowState extends State<StartNumberWindow> {
  int _start = 1;

  /// A drag to the left stops at zero: 「숫자만 입력가능」 leaves typing no
  /// sign, so the drag does not reach a number the field could not take.
  void _setStart(int value) => setState(() => _start = value < 0 ? 0 : value);

  void _typed(String text) {
    final typed = int.tryParse(text);
    if (typed != null) {
      _setStart(typed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('auto-name-dialog'),
      title: editorActionLabel(EditorActionIds.editAutoName),
      titleIcon: Icons.format_list_numbered,
      onClose: () => Navigator.of(context).pop(),
      width: 300,
      body: AppWindowField(
        label: strings.autoNameStartField,
        emphasized: true,
        child: DragValueLabel(
          keyValue: 'auto-name-start',
          text: '$_start',
          unitsPerPixel: 1 / 8,
          width: 96,
          textStyle: Theme.of(context).textTheme.titleMedium,
          digitsOnly: true,
          onDragDelta: (delta) => _setStart(_start + delta.round()),
          onEditSubmit: _typed,
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('auto-name-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonApply,
          actionKey: const ValueKey<String>('auto-name-apply-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(_start),
        ),
      ],
    );
  }
}
