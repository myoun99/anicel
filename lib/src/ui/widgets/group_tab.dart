import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppCursors, AppShapes;
import 'instant_tap_region.dart';

/// One tab in a rail of groups down a panel's left side — the brush
/// library's groups, and the brush detail window's (I-141-Q4, 유저
/// 2026-10-29: 「클튜처럼 왼쪽에 두자. 브러시그룹/브러시목록이랑
/// 비슷한느낌으로」). ⛔ONE tab for both: the window's rail is this widget,
/// not one drawn to look like it.
class GroupTab extends StatelessWidget {
  const GroupTab({
    super.key,
    required this.keyValue,
    required this.label,
    required this.selected,
    required this.onTap,
    this.face,
    this.showName = true,
    this.trailing,
    this.onDoubleTap,
  });

  /// Height of one tab. Fixed, because the brush library's rail turns a
  /// pointer offset into a tab index while a brush is being dragged over it.
  ///
  /// 🚨TWO THIRDS OF A BRUSH CELL, WIDE RATHER THAN TALL.
  ///
  /// The shape came from `brush-group-tab-shape-Q1` 답 1 (2026-09-10): the
  /// spec was two sentences that fought each other in pixels — 「그룹도 **좀
  /// 더 길게**해서 그룹이름 어느정도 **제대로 보이도록**」 and 「비율적으로
  /// 그룹은 **브러시 프리뷰 세로길이의 반**」 — because a brush cell is 34 and
  /// an 11pt name had been sitting in 26. The answer reads 「길게」 as WIDTH:
  /// the tab gets shorter and the rail gets wider, so both sentences hold.
  ///
  /// The FRACTION then moved once, on sight: 유저 2026-09-10, 「지금 브러시의
  /// 절반인데 너무 작으니 2/3로 하고싶고」. A half was 17; two thirds of 34 is
  /// 22.67, and this is the nearest whole pixel to it.
  ///
  /// ⚠️ROUNDED ON PURPOSE. 34 does not divide by 3, and the rail is a list of
  /// fixed-height rows with backgrounds: a 22.67 row puts every boundary on a
  /// third of a logical pixel, which is a seam between tabs at every DPR. The
  /// pin asserts the rounding rather than the fraction, so it still fails if
  /// either number moves without the other.
  ///
  /// ⚠️AND THE COST WAS TAKEN WITH IT: at the stock 260px panel a rail of 120
  /// leaves 140 for the grid, which is ONE column of 130px cells. That is on
  /// the card as the price of the answer, not a regression to fix.
  static const double extent = 23;

  /// Rail width once names are showing.
  ///
  /// 96 cut a group name at two or three characters, which is what 「이름이
  /// 제대로 보이도록」 was about.
  static const double namedWidth = 120;

  /// The size a group's name is written at — and the key after it.
  static const double nameFontSize = 11;

  final String keyValue;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The tab's picture before its name, or null for a tab that is its name.
  final Widget? face;

  /// Whether the name shows — off, the [face] is the whole tab.
  final bool showName;

  /// What follows the name — the brush group's key.
  final Widget? trailing;

  /// A double tap — the brush group's editor. It cannot collide with the
  /// single tap that switches group, and does not DELAY it either (R10):
  /// the switch rides the raw pointer ([InstantTapRegion]).
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final face = this.face;
    final body = Material(
      color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
      shape: AppShapes.container(AppShapes.wellRadius),
      child: InkWell(
        mouseCursor: AppCursors.press,
        key: ValueKey<String>(keyValue),
        // The switch rides the raw pointer (R10) — see the wrapper below.
        // The InkWell keeps a no-op tap so its ripple and its semantics
        // stay, the same shape the timeline cells use.
        onTap: () {},
        onDoubleTap: onDoubleTap,
        customBorder: AppShapes.container(AppShapes.wellRadius),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // No fixed width: the selected tab's border is thicker, so a
              // hard-sized box overflows it by a pixel.
              if (face != null)
                if (showName)
                  SizedBox(width: 20, child: face)
                else
                  Expanded(child: face),
              if (showName)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: face != null ? 0 : 5,
                      right: 3,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      // Group names run long — a pack keeps the file's name
                      // — so the tail is what gives.
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: nameFontSize,
                        color: selected
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (showName) ?trailing,
            ],
          ),
        ),
      ),
    );
    // R10: the group switch acts on the raw pointer, so it no longer waits
    // out [onDoubleTap]'s window. Touch still commits on the release — the
    // rail scrolls, and a press that becomes a scroll must not switch
    // groups under the finger.
    return SizedBox(
      height: extent,
      child: InstantTapRegion(onTap: (_) => onTap(), child: body),
    );
  }
}
