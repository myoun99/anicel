import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// Opens [LinkWindow] and waits for it to close.
Future<void> showLinkWindow(
  BuildContext context, {
  required List<String> targets,
  required VoidCallback? unlink,
  String? unlinkOffReason,
}) => showDialog<void>(
  context: context,
  builder: (context) => LinkWindow(
    targets: targets,
    unlink: unlink,
    unlinkOffReason: unlinkOffReason,
  ),
);

/// THE LINK WINDOW: what a cut or a row is linked to, and the one button
/// that unlinks it.
///
/// 🗣️I-25 (유저 2026-09-14): 「링크컷/링크레이어 등 좀 더 알기쉽게. 우선
/// 링크컷이 발생해있는 경우, 모든 컷에 적용. 내용은 컷블록에서 컷 이름 오른쪽에
/// 링크아이콘(레이어에서 사용하는거랑 똑같은 것) 사용. 그리고 해당 버튼 클릭시
/// 공용창 띄움. 링크된 대상의 리스트(보기만). 그리고 링크해제 버튼. 해제버튼은
/// 현재 컷을 독립시킴. 레이어도 똑같이 버튼누르면 링크 대상 리스트 표시.
/// 여기서 링크컷일경우엔 링크해제버튼 비활성화하고 툴팁으로 링크컷이기때문에
/// 불가능하다고 띄움」 — ONE window for both entrances; each entrance says
/// what is listed and what the button does.
class LinkWindow extends StatelessWidget {
  const LinkWindow({
    super.key,
    required this.targets,
    required this.unlink,
    this.unlinkOffReason,
  });

  /// The linked places, one line each — view only.
  final List<String> targets;

  /// What the button does; null keeps it in place, off, with
  /// [unlinkOffReason] as its tooltip.
  final VoidCallback? unlink;
  final String? unlinkOffReason;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final unlink = this.unlink;
    return AppWindow(
      windowKey: const ValueKey<String>('link-window'),
      title: strings.tlLinkedWith,
      titleIcon: Icons.link,
      onClose: () => Navigator.of(context).pop(),
      width: 320,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, line) in targets.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    line,
                    key: ValueKey<String>('link-window-target-$index'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.linkWindowUnlink,
          actionKey: const ValueKey<String>('link-window-unlink'),
          emphasis: AppWindowActionEmphasis.primary,
          tooltip: unlink == null ? unlinkOffReason : null,
          onPressed: unlink == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  unlink();
                },
        ),
      ],
    );
  }
}
