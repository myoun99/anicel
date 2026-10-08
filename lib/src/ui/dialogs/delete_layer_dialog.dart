import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// Confirmation dialog for deleting a layer. Pops `true` to confirm.
class DeleteLayerDialog extends StatelessWidget {
  const DeleteLayerDialog({super.key, required this.rows});

  /// Every row that goes, by name, as the rail lists them — top first: the
  /// rows the delete names, and what they take along.
  ///
  /// 🗣️F-303 (유저 2026-10-06): 「ui 공용 리스트화 사용안하는거 연결. 지금
  /// 레이어 삭제시 아직도 하나하나 묻고있음. 여러 프레임 링크하는 창에서 쓰는
  /// 공용 리스트창 그대로 사용해서 **아래 레이어 삭제할까요하고 리스트
  /// 보여주는것처럼** 하도록」. ↩️The named rows were joined into the sentence
  /// (「레이어 "A, B, C"을(를) 삭제할까요?」) and only what they held was
  /// listed — the shape [AppConfirmDialog.details] exists to refuse: a
  /// sentence that grows with the list. One row or forty, the sentence is
  /// the same and the list says which.
  ///
  /// 🗣️F-305 (유저 2026-10-06): 「클튜는 아마 내용물도 삭제하시겠습니까?
  /// 라고 물어보는데 필요없어보임 … 다만 내용물도 삭제리스트에 보여지게는 하면
  /// 될듯」. No second question: the one this window already asks, with what
  /// it takes listed under it — OPEN, since the list is what there is to see.
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    final keys = confirmDialogKeys('delete-layer');
    final strings = AppText.strings;
    return AppConfirmDialog(
      windowKey: keys.window,
      title: strings.deleteLayerTitle,
      titleIcon: Icons.delete_outline,
      message: strings.deleteLayersMessage,
      details: rows,
      detailsHeading: strings.deleteLayersHeading,
      detailsOpen: true,
      actions: confirmActions(
        context,
        keys: keys,
        decline: ConfirmChoice(strings.commonCancel),
        accept: ConfirmChoice(strings.commonDelete),
      ),
    );
  }
}
