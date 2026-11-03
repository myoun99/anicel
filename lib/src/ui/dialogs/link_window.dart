import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// What a cut or a row shares, and so which of its two buttons and windows
/// answers: its pictures with a 겸용 (I-25) — the link — or, a 동기컷, its
/// very self with the cut it is in the other timelines (I-150-Q3) — the
/// sync. A glyph each, the cut's the row's (I-25: 「레이어에서 사용하는거랑
/// 똑같은 것」).
///
/// 🗣️유저 2026-11-04: 「동기컷이 지금 링크랑 같은 버튼인데, 그거말고 그냥
/// 버튼나누자. 동기 대상 뭐 이런식? 아이콘도 다른거쓰고」. ↩️A 동기컷 wore the
/// sync glyph on the link's one button, and the link window listed it under
/// a heading of its own with 동기 해제 beside 링크 해제.
enum LinkKind {
  link(Icons.link),
  sync(Icons.sync);

  const LinkKind(this.glyph);

  final IconData glyph;

  /// The window's title, which heads the button's tooltip too.
  String get title => switch (this) {
    link => AppText.strings.tlLinkedWith,
    sync => AppText.strings.syncedWith,
  };
}

/// Opens [window] and waits for it to close. ↩️It took the window's
/// fields one by one and built it, a second list of them to keep in step.
Future<void> showLinkWindow(BuildContext context, LinkWindow window) =>
    showDialog<void>(context: context, builder: (context) => window);

/// THE LINK WINDOW: what a cut or a row is linked to — or, its [kind] the
/// sync, the cut a 동기컷 is in the other timelines — and the one button that
/// takes it apart.
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
    required this.kind,
    required this.targets,
    required this.action,
    this.actionOffReason,
  });

  /// Which window: the link's or the sync's.
  final LinkKind kind;

  /// The places it shares with, one line each — view only.
  final List<String> targets;

  /// What the button does — 링크 해제, or 동기 해제 (I-150-Q6, 유저
  /// 2026-11-04 「동기 해제 = 독립 컷」); null keeps it in place, off, with
  /// [actionOffReason] as its tooltip.
  final VoidCallback? action;
  final String? actionOffReason;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final action = this.action;
    final name = kind.name;
    return AppWindow(
      windowKey: ValueKey<String>('$name-window'),
      title: kind.title,
      titleIcon: kind.glyph,
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
                    key: ValueKey<String>('$name-window-target-$index'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: switch (kind) {
            LinkKind.link => strings.linkWindowUnlink,
            LinkKind.sync => strings.linkWindowUnsync,
          },
          actionKey: ValueKey<String>(switch (kind) {
            LinkKind.link => 'link-window-unlink',
            LinkKind.sync => 'sync-window-unsync',
          }),
          emphasis: AppWindowActionEmphasis.primary,
          tooltip: action == null ? actionOffReason : null,
          onPressed: action == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  action();
                },
        ),
      ],
    );
  }
}
