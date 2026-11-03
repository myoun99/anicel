import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The glyph that says a cut or a row shares its pictures — a row's badge,
/// a cut block's square: the link, or a 동기컷's sync, set apart from the
/// 겸용 (🗣️I-150-Q3: 「배지에도 겸용이란 이름이아니라 동기컷? 뭐 그런식으로
/// 따로 표시」). One answer, so the cut's icon stays the row's (I-25:
/// 「레이어에서 사용하는거랑 똑같은 것」).
IconData linkGlyph({required bool synced}) =>
    synced ? Icons.sync : Icons.link;

/// Opens [window] and waits for it to close. ↩️It took the window's
/// fields one by one and built it, a second list of them to keep in step.
Future<void> showLinkWindow(BuildContext context, LinkWindow window) =>
    showDialog<void>(context: context, builder: (context) => window);

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
    this.synced = const [],
    this.unsync,
  });

  /// The linked places, one line each — view only.
  final List<String> targets;

  /// The cut it is in the other timelines — its 동기컷's other cuts — one
  /// line each, under their own heading, apart from the 겸용 (🗣️I-150-Q3:
  /// 「배지에도 겸용이란 이름이아니라 동기컷? 뭐 그런식으로 따로 표시」).
  /// Empty: not a 동기컷.
  final List<String> synced;

  /// 동기 해제 (I-150-Q6, 유저 2026-11-04 「동기 해제 = 독립 컷」): the
  /// button beside [unlink] while [synced] lists a cut.
  final VoidCallback? unsync;

  /// What the button does; null keeps it in place, off, with
  /// [unlinkOffReason] as its tooltip.
  final VoidCallback? unlink;
  final String? unlinkOffReason;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final unlink = this.unlink;
    final unsync = this.unsync;
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
              if (synced.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 9, bottom: 3),
                  child: Text(
                    strings.linkWindowSynced,
                    key: const ValueKey<String>('link-window-synced'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              for (final (index, line) in synced.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    line,
                    key: ValueKey<String>('link-window-synced-$index'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (synced.isNotEmpty && unsync != null)
          AppWindowAction(
            label: strings.linkWindowUnsync,
            actionKey: const ValueKey<String>('link-window-unsync'),
            onPressed: () {
              Navigator.of(context).pop();
              unsync();
            },
          ),
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
