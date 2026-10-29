import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'app_prompt_dialog.dart';
import 'app_confirm_dialog.dart';

/// Rename dialog for a cut. Pops the trimmed new name, or nothing on
/// cancel. Rejects an empty name inline — the cut's name IS its number on
/// every sheet and storyboard page that prints it.
///
/// 🗣️유저 2026-10-28 (F-291): 「컷 대상으로 한 이름편집에서 신이란 항목을
/// 위에 둬서 거기서도 편집가능 … 컷 이름편집누르면 텍스트 선택된상태는
/// 지금처럼 컷의 이름에 가도록. 신은 그리고 이름 비울수있음」 — the cut's
/// scene sits over its name, may be emptied, and is told to
/// [onSceneChanged] as it is typed; the name keeps the focus and its
/// selection.
class RenameCutDialog extends StatelessWidget {
  const RenameCutDialog({
    super.key,
    required this.initialName,
    required this.initialScene,
    required this.onSceneChanged,
  });

  final String initialName;
  final String initialScene;
  final ValueChanged<String> onSceneChanged;

  @override
  Widget build(BuildContext context) {
    final keys = confirmDialogKeys('rename-cut');
    final strings = AppText.strings;
    return AppPromptDialog(
      windowKey: keys.window,
      title: strings.windowTitleOn(strings.editNameAction, strings.tlCut),
      titleIcon: Icons.drive_file_rename_outline,
      initialValue: initialName,
      confirmLabel: strings.commonRename,
      emptyError: strings.renameCutEmpty,
      fieldKey: const ValueKey<String>('rename-cut-text-field'),
      cancelKey: keys.decline,
      confirmKey: keys.accept,
      lead: AppWindowField(
        label: strings.sheetFieldScene,
        child: _SceneField(initial: initialScene, onChanged: onSceneChanged),
      ),
    );
  }
}

class _SceneField extends StatefulWidget {
  const _SceneField({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SceneField> createState() => _SceneFieldState();
}

class _SceneFieldState extends State<_SceneField> {
  late final TextEditingController _scene = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey<String>('rename-cut-scene-field'),
    controller: _scene,
    textInputAction: TextInputAction.next,
    onChanged: widget.onChanged,
  );
}
