import 'package:flutter/material.dart';

import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/window_number.dart';

/// 자동 이름 지정's one question (I-18): the number the first block takes.
///
/// 🗣️I-18 (유저): 「누르면 숫자 편집하는 창 나와서 숫자만 입력가능. 드래그로
/// 조절하거나 수동입력. 기본값은 1인상태」. The number is the app's operable
/// readout, the one every number window asks with ([WindowNumber]) — a drag
/// along it moves it, its ± step it, its pencil types it, digits alone —
/// and it opens at 1 EVERY time:
/// 「기본값은 1인상태」 names where it starts, not a number it keeps.
///
/// Pops the number on Apply, nothing on Cancel.
class StartNumberWindow extends StatefulWidget {
  const StartNumberWindow({super.key, required this.target});

  /// What the numbers go to — the title's brackets (I-24-open-entry: the
  /// timeline buttons' windows name what they act on).
  final String target;

  @override
  State<StartNumberWindow> createState() => _StartNumberWindowState();
}

class _StartNumberWindowState extends State<StartNumberWindow> {
  int _start = 1;

  /// A drag to the left stops at zero: 「숫자만 입력가능」 leaves typing no
  /// sign, so the drag does not reach a number the field could not take.
  void _setStart(int value) => setState(() => _start = value < 0 ? 0 : value);

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('auto-name-dialog'),
      title: strings.windowTitleOn(
        editorActionLabel(EditorActionIds.editAutoName),
        widget.target,
      ),
      titleIcon: Icons.format_list_numbered,
      onClose: () => Navigator.of(context).pop(),
      width: 300,
      body: AppWindowField(
        label: strings.autoNameStartField,
        emphasized: true,
        child: WindowNumber(
          keyValue: 'auto-name-start',
          value: _start,
          onChanged: _setStart,
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
