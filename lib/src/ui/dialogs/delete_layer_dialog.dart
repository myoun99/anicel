import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// Confirmation dialog for deleting a layer. Pops `true` to confirm.
class DeleteLayerDialog extends StatelessWidget {
  const DeleteLayerDialog({
    super.key,
    required this.layerName,
    this.held = const [],
  });

  final String layerName;

  /// The rows that go WITH what [layerName] names — a deleted folder's — by
  /// name, top first.
  ///
  /// 🗣️F-305 (유저 2026-10-06): 「클튜는 아마 내용물도 삭제하시겠습니까?
  /// 라고 물어보는데 필요없어보임 … 다만 내용물도 삭제리스트에 보여지게는 하면
  /// 될듯」. No second question: the one this window already asks, with what
  /// it takes listed under it — OPEN, since the list is what there is to see.
  final List<String> held;

  @override
  Widget build(BuildContext context) {
    final keys = confirmDialogKeys('delete-layer');
    final strings = AppText.strings;
    return AppConfirmDialog(
      windowKey: keys.window,
      title: strings.deleteLayerTitle,
      titleIcon: Icons.delete_outline,
      message: strings.deleteLayerMessageTemplate.replaceAll(
        '{name}',
        layerName,
      ),
      details: held,
      detailsHeading: strings.deleteLayerHeldHeading,
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
