import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../text/text_measure.dart';
import 'app_icon_button.dart';
import 'drag_value_label.dart';
import 'transport_bar.dart';

/// The page a turner stands on: [index] of [count], ZERO-based, and how its
/// host [spell]s a page.
///
/// The spelling travels with the position because the hosts do not agree
/// on it: the timesheet says '1/2', the spelling shared with the printed
/// ページ header (R26 #41), while the viewers say '1 / 2' ([viewerPage]).
/// Every one of them counts from the first page, and so does a typed 3.
typedef TurnedPage = ({
  int index,
  int count,
  String Function(int index) spell,
});

/// THE page turner: what a BOOK wears in the band under it, where a
/// document that runs wears the transport ([TransportBar]) — ◀ · the page ·
/// ▶ unbroken, the readout dragged, and after them a pencil to type a page
/// (tool-settings-panel-tidy, 유저 2026-10-10 — the chevrons are its steps).
///
/// 🗣️F-383 (유저 2026-10-17): 「뷰어패널이나 콘티용지패널이나 출력
/// 미리보기든 뭐든 캔버스베이스패널에서 왼쪽에 페이지뷰? 알약 뒀을텐데.
/// 그냥 불편하니 없애고 비디오파일이면 밑에 재생바같은거 뜨듯이 그런식으로
/// 페이지 전환하는거 구현. 같은식으로 밑에 알약말고 비디오파일일때 처럼
/// 공간만들고 거기다 기존 버튼 배치하는식으로」. ↩️It stood upright in a
/// capsule on the panel's LEFT edge (유저 확정 ⑥ 2026-08-13) — ▲ · page ·
/// ▼ and the pencil under them, its readout 30px wide in 9pt because the
/// capsule was 32 — and before that it rode in the pill.
///
/// ONE turner for every panel that turns pages (the timesheet, the conte,
/// the media viewer, the export window's book — 「최대한 통일」): the same
/// chevrons, the same readout at ⅛ page per pixel, the same '3/7 → 3'
/// parse, the same disable-at-the-ends. What differs are values: the key
/// prefix, the [page] it stands on and how that page is spelled, and
/// whether turning is possible at all ([onTurnTo] null — Flutter's
/// disabled idiom — keeps it MOUNTED and inert).
///
/// The readout is as wide as the widest page it could say, so the ▶ does
/// not walk out from under a hand turning page after page.
///
/// 🪦A `leading` run rode at the strip's head: the media viewer's PLAY,
/// under 「재생 = 페이지 넘김」. A document that runs wears the transport
/// (F-289, 유저 2026-10-06), and this is a book's alone.
class PageTurnBar extends StatelessWidget {
  const PageTurnBar({
    super.key,
    required this.keyPrefix,
    required this.page,
    required this.onTurnTo,
  });

  final String keyPrefix;
  final TurnedPage page;
  final ValueChanged<int>? onTurnTo;

  /// How tall its band stands: the transport's row of buttons, alone
  /// ([TransportBar.buttonRowHeightIn]) — the space a movie's player stands
  /// in, one row of it.
  static double heightIn(BuildContext context) =>
      TransportBar.buttonRowHeightIn(context);

  static final RegExp _digit = RegExp(r'\d');

  /// The widest the readout gets: the last page spelled, every digit of it
  /// each digit in turn.
  double _readoutWidthIn(BuildContext context) {
    final last = page.spell(page.count - 1);
    return TextMeasure(context, DragValueLabel.bareStyleIn(context))
        .widest(everyDigitIn((digit) => last.replaceAll(_digit, digit)))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final turnTo = onTurnTo;
    return Center(
      // A panel narrower than the turner gets the whole of it, smaller —
      // never a row that runs off its band, and never one missing a control.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: '$keyPrefix-previous-page-button',
              tooltip: strings.sheetPreviousPage,
              icon: const Icon(Icons.keyboard_arrow_left),
              size: AppIconButtonSize.strip,
              onPressed: turnTo != null && page.index > 0
                  ? () => turnTo(page.index - 1)
                  : null,
            ),
            DragValueLabel(
              keyValue: '$keyPrefix-page-readout',
              inputKeyValue: '$keyPrefix-page-input',
              text: page.spell(page.index),
              tooltip: strings.sheetPageDrag,
              width: _readoutWidthIn(context),
              // Off with the chevrons beside it: nothing here can turn.
              enabled: turnTo != null,
              // One page per 8px of drag: a 1px-per-page rate flipped whole
              // documents on a twitch.
              unitsPerPixel: 1 / 8,
              onDragDelta: (units) => turnTo?.call(page.index + units.round()),
              onEditSubmit: (text) {
                // '3' and '3/7' both mean page three (the readout's own
                // spelling round-trips).
                final parsed = int.tryParse(text.split('/').first.trim());
                if (parsed != null) {
                  turnTo?.call(parsed - 1);
                }
              },
              stepBeforePencil: AppIconButton(
                keyValue: '$keyPrefix-next-page-button',
                tooltip: strings.sheetNextPage,
                icon: const Icon(Icons.keyboard_arrow_right),
                size: AppIconButtonSize.strip,
                onPressed: turnTo != null && page.index < page.count - 1
                    ? () => turnTo(page.index + 1)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page [index] of [count] as a VIEWER numbers it: its first page is 1,
/// written '1 / 2' — the media viewer's and the conte's, one rule (유저
/// 2026-09-26: 「뷰어패널로서는 첫 페이지가 1이되도록 … 뷰어패널의 규칙
/// 동일하게」).
///
/// ↩️The conte numbered its BODY here, as its pages print: the cover and
/// its blank back read 「Cover」 · 「Blank」 and a typed 3 counted from the
/// body. The printed numbers stay the body's; the viewer's count is the
/// book's.
TurnedPage viewerPage(int index, int count) =>
    (index: index, count: count, spell: (page) => '${page + 1} / $count');
