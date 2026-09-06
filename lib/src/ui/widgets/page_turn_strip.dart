import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_icon_button.dart';
import 'drag_value_label.dart';

/// The page cluster, on the panel's LEFT edge (유저 확정 ⑥ 2026-08-13) —
/// the timesheet's ◀ n/N ▶ grammar stood upright, drag/type on the
/// readout included. Empty below two pages: nothing to turn.
///
/// ONE cluster for the three sheets that turn pages (the timesheet, the
/// conte, the media viewer — 「최대한 통일」): the same chevrons, the same
/// 30px/9pt readout at ⅛ page per pixel, the same '3/7 → 3' parse, the
/// same disable-at-the-ends. What differs are values: the key prefix, the
/// readout text, whether turning is possible at all ([onTurnTo] null —
/// Flutter's disabled idiom — keeps the cluster MOUNTED and inert), and an
/// optional [leading] run that rides at the head of the cluster.
///
/// ⚠️Up/down rather than left/right: the strip reads vertically, so a
/// chevron pointing sideways would point at nothing.
List<Widget> pageTurnStrip({
  required String keyPrefix,
  required int pageIndex,
  required int pageCount,
  required String label,
  required ValueChanged<int>? onTurnTo,
  List<Widget> leading = const <Widget>[],
}) {
  if (pageCount <= 1) {
    return const <Widget>[];
  }
  final strings = AppText.strings;
  return [
    ...leading,
    AppIconButton(
      keyValue: '$keyPrefix-previous-page-button',
      tooltip: strings.sheetPreviousPage,
      icon: const Icon(Icons.keyboard_arrow_up),
      size: AppIconButtonSize.strip,
      onPressed: onTurnTo != null && pageIndex > 0
          ? () => onTurnTo(pageIndex - 1)
          : null,
    ),
    DragValueLabel(
      keyValue: '$keyPrefix-page-readout',
      inputKeyValue: '$keyPrefix-page-input',
      text: label,
      tooltip: strings.sheetPageDrag,
      width: 30,
      textStyle: const TextStyle(fontSize: 9),
      // One page per 8px of drag: a 1px-per-page rate flipped whole
      // documents on a twitch.
      unitsPerPixel: 1 / 8,
      onDragDelta: onTurnTo == null
          ? _noDrag
          : (units) => onTurnTo(pageIndex + units.round()),
      onEditSubmit: (text) {
        if (onTurnTo == null) {
          return;
        }
        // '3' and '3/7' both mean page three (the readout's own
        // spelling round-trips).
        final parsed = int.tryParse(text.split('/').first.trim());
        if (parsed != null) {
          onTurnTo(parsed - 1);
        }
      },
    ),
    AppIconButton(
      keyValue: '$keyPrefix-next-page-button',
      tooltip: strings.sheetNextPage,
      icon: const Icon(Icons.keyboard_arrow_down),
      size: AppIconButtonSize.strip,
      onPressed: onTurnTo != null && pageIndex < pageCount - 1
          ? () => onTurnTo(pageIndex + 1)
          : null,
    ),
  ];
}

void _noDrag(double units) {}
