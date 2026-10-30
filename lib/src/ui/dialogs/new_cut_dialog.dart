import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import 'app_prompt_dialog.dart';
import 'canvas_size_dialog.dart';
import 'size_fields_row.dart';

/// The window the ＋ of the cut pill opens: the new cut's name over its
/// canvas's size. Pops the trimmed name, or nothing on cancel; the size is
/// told to [onSizeChanged] as it is typed or picked, as the cut rename's
/// scene is.
///
/// 🗣️I-100 (유저 2026-10-14): 「컷 만들기 버튼 누르면 컷 생성창 열려서,
/// 거기서 이름(기본값 넣어줌), 캔버스 사이즈(기본값 a4 200dpi) 정하도록.
/// 거기서 정한값으로 만들어짐」 — the size is the canvas size window's own
/// fields and presets. ⛔No 「캔버스에서 조정」: there is no canvas yet to
/// adjust ([SizePresetsRow] says why a window that has one keeps it).
///
/// 🗣️I-100-Q1 (유저 2026-10-30 「겸용 컷 만들기도 창을 연다(이름만)」): a 겸용
/// cut's window too ([action]) — its size its source's, fixed, since the
/// two share their pictures ([onSizeChanged] null).
class NewCutDialog extends StatefulWidget {
  const NewCutDialog({
    super.key,
    this.action = EditorActionIds.cutNew,
    required this.initialName,
    required this.initialSize,
    required this.onSizeChanged,
  });

  /// The action that opens it, which names it.
  final String action;
  final String initialName;
  final CanvasSize initialSize;

  /// The size typed or picked. Null where it is fixed.
  final ValueChanged<CanvasSize>? onSizeChanged;

  @override
  State<NewCutDialog> createState() => _NewCutDialogState();
}

class _NewCutDialogState extends State<NewCutDialog> {
  late final TextEditingController _widthController = TextEditingController(
    text: '${widget.initialSize.width}',
  );
  late final TextEditingController _heightController = TextEditingController(
    text: '${widget.initialSize.height}',
  );

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  CanvasSize? get _entered =>
      CanvasSizeDialog.enteredSize(_widthController, _heightController);

  void _sizeChanged() {
    setState(() {});
    final size = _entered;
    if (size != null) {
      widget.onSizeChanged?.call(size);
    }
  }

  void _picked(CanvasSize size) {
    _widthController.text = '${size.width}';
    _heightController.text = '${size.height}';
    _sizeChanged();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final entered = _entered;
    final sizable = widget.onSizeChanged != null;
    return AppPromptDialog.keyed(
      keyPrefix: 'new-cut',
      title: editorActionLabel(widget.action),
      // Not the ＋ the button wears: every ＋ glyph is the add accent
      // (`add_glyph_accent_test`), and a window's title is no button.
      titleIcon: Icons.movie_outlined,
      fieldLabel: strings.commonNameField,
      initialValue: widget.initialName,
      confirmLabel: strings.commonCreate,
      emptyError: strings.renameCutEmpty,
      width: 460,
      extraHolds: entered != null,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizeFieldsRow(
            keyPrefix: 'new-cut',
            widthController: _widthController,
            heightController: _heightController,
            onChanged: sizable ? _sizeChanged : null,
          ),
          const SizedBox(height: 12),
          SizePresetsButton(
            keyPrefix: 'new-cut',
            groups: canvasSizePresetGroups,
            entered: entered,
            onPicked: sizable ? _picked : null,
          ),
        ],
      ),
    );
  }
}
