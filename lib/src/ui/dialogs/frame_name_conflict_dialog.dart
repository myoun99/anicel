import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// Asks whether to link frames to the frames already using the names they
/// were given, so identical names share the same material. Pops `true` to
/// link.
///
/// 🗣️I-18 (유저): 「이제 링크프레임이나 링크레이어 발동할때 뜨는 안내메시지를
/// 단일 변경만 대응하는게 아니라 복수 대응을 기본으로. 대상의 프레임을
/// 리스트로서 보여주도록」. One frame renamed or a whole 자동 이름 지정 press,
/// it is the same window: the sentence reads for one or many, and the frames
/// the link takes are listed under it — OPEN, because which ones is what the
/// window asks about (F-118's rule, [AppConfirmDialog.detailsOpen]).
class FrameNameConflictDialog extends StatelessWidget {
  const FrameNameConflictDialog({super.key, required this.targets});

  /// The frames the link takes, one line each.
  final List<String> targets;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    // ⚠️Spelled out rather than `confirmDialogKeys`: the accept answers
    // `-link-button`, not `-confirm-button`, so this window is not that
    // convention and keeps its own trio.
    const keys = (
      window: ValueKey<String>('frame-name-conflict-dialog'),
      decline: ValueKey<String>('frame-name-conflict-cancel-button'),
      accept: ValueKey<String>('frame-name-conflict-link-button'),
    );
    return AppConfirmDialog(
      windowKey: keys.window,
      title: strings.frameNameConflictTitle,
      titleIcon: Icons.link_outlined,
      message: strings.frameNameConflictBody,
      details: targets,
      detailsHeading: strings.frameNameConflictListHeading,
      detailsOpen: true,
      actions: confirmActions(
        context,
        keys: keys,
        decline: ConfirmChoice(strings.commonCancel),
        accept: ConfirmChoice(strings.commonLink),
      ),
    );
  }
}
