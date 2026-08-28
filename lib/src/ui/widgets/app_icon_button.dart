import 'package:flutter/material.dart';

import '../layout/device_grid.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart';

/// What a button's box measures — a named token, or a box its PARENT
/// already promised.
///
/// 🚨★★★ONE FIELD, TWO KINDS. [AppIconButton] holds a single [size], so
/// "which of the two decides the box?" is not a question the widget can be
/// asked — a `size` token beside a nullable `box` would have let a caller
/// pass both, and the day they disagreed the button would have had two
/// owners for one number ([[make-the-invariant-unrepresentable]]).
abstract interface class AppIconButtonMetrics {
  double get minWidth;
  double get maxWidth;
  double get height;
  double get iconSize;

  /// True when a PARENT sized this box, so the numbers are used verbatim.
  /// A token's are quantized onto the device grid first; a promised box is
  /// not ours to round.
  bool get parentOwnsBox;
}

/// A box the parent already promised — the rails' 20–22px slots and the
/// top strip's 32px group, where the surrounding layout was built around a
/// number before the button existed.
///
/// ⛔THIS IS NOT A SIXTH TOKEN. A token names a PLACE and is reused; this
/// says "the caller owns this one" and is passed at the call site, so it
/// cannot quietly become a new default for anyone else. It exists because
/// 실측 on 2026-08-28 found 36 hand-rolled `IconButton`s that could not join
/// a token without their box changing, and a box that changes is exactly
/// what the rail cannot survive ([[widget-between-slot-and-plate]]).
class AppIconButtonBox implements AppIconButtonMetrics {
  const AppIconButtonBox({
    required double width,
    required this.height,
    required this.iconSize,
  }) : minWidth = width,
       maxWidth = width;

  @override
  final double minWidth;
  @override
  final double maxWidth;
  @override
  final double height;
  @override
  final double iconSize;

  @override
  bool get parentOwnsBox => true;
}

/// ⛔A NEW TOKEN IS NOT A FREE MOVE. Adding one because a number is off by
/// two is how five becomes fifteen; each token below names a PLACE that
/// argued for its size, and the argument is in its doc.
enum AppIconButtonSize implements AppIconButtonMetrics {
  /// Panel bottom bars — the reference size.
  bar(minWidth: 26, maxWidth: 30, height: 24, iconSize: 18),

  /// Slim panel status strips.
  strip(minWidth: 22, maxWidth: 26, height: 20, iconSize: 15),

  /// The TOOL RAIL's square. 42 is a stylus target the rail was narrowed
  /// AROUND (R9 #17: a tight box, so the slim rail holds the button instead
  /// of the button dictating a 72px rail) — shrinking it here would reopen
  /// that decision from the wrong end.
  tool(minWidth: 42, maxWidth: 42, height: 42, iconSize: 20),

  /// Timeline lanes and the workspace chrome: a bar button with a smaller
  /// glyph, because the row it sits in is shorter than a panel's.
  dense(minWidth: 24, maxWidth: 28, height: 22, iconSize: 16),

  /// Window chrome and the debug inspector — the smallest the app draws,
  /// where the button is beside text rather than in a row of its own.
  micro(minWidth: 20, maxWidth: 24, height: 18, iconSize: 14),

  /// Dialogs and menus, where the button sits among Material's own metrics
  /// and a 18px glyph would read as a different control.
  standard(minWidth: 36, maxWidth: 40, height: 36, iconSize: 24);

  const AppIconButtonSize({
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.iconSize,
  });

  @override
  final double minWidth;
  @override
  final double maxWidth;
  @override
  final double height;
  @override
  final double iconSize;

  @override
  bool get parentOwnsBox => false;
}

/// R26 #42 — THE app's icon button.
///
/// The canvas panel's bottom bar (fit / 1:1 / zoom / rotate / flip) is the
/// style the user adopted as the default icon UI, so it lives here now and
/// every other surface mounts THIS widget instead of hand-rolling its own
/// `InkWell` + `Icon` pair: a compact square hit target, an 18px glyph, no
/// padding, and — the selection rule ([[ui-selection-style]]) — an accent
/// FOREGROUND for the on state, never a check mark or a filled chip.
///
/// Sizing is a token, not a per-call number: [AppIconButtonSize.bar] is the
/// canvas bottom bar's, [AppIconButtonSize.strip] the same button squeezed
/// into a slim status strip. Callers pick a token so a future style change
/// lands everywhere at once.
///
/// 🚨★★★THE TOKENS ARE THE ANSWER TO 「앱에 버튼은 한 종류」, not a betrayal of
/// it. 유저 2026-08-28 chose this over collapsing every button to one size:
/// lib had **50 hand-rolled `IconButton`s across 22 files** at five different
/// glyph sizes, and 실측 said not one of them could join without the box
/// changing. ⇒ 「한 종류」 means ONE PARENT — one shape, one selection rule,
/// one hit-target policy — with the size named rather than typed.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.keyValue,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isSelected = false,
    this.size = AppIconButtonSize.bar,
  });

  /// Stable widget key (the tests' handle).
  final String keyValue;
  final String tooltip;

  /// Usually an [Icon]; text glyphs ('1:1') are allowed — they inherit the
  /// same accent/foreground treatment.
  final Widget icon;
  final VoidCallback? onPressed;

  /// The ON state — accent ink only (UI-R21 #1: the M3 `isSelected`
  /// default was invisible in this theme, so the accent is explicit).
  final bool isSelected;

  /// The box: a named token, or an [AppIconButtonBox] the parent promised.
  final AppIconButtonMetrics size;

  @override
  Widget build(BuildContext context) {
    final grid = DeviceGrid.of(context);
    double onGrid(double v) => size.parentOwnsBox ? v : grid.position(v);
    // 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 다른 레이어의 버튼
    // 누르면 작동안함 … 레이어에 있는 **모든 버튼이나 편집이** 그럼」.
    //
    // ★A press that lands on a control belongs to that control
    // ([value_control_pointers.dart]). That law was written for sliders and
    // splitters — and the user's report says 「모든 버튼」, which is the same
    // sentence: a BUTTON is as much the thing under the finger as a slider
    // is. Claiming here is what stops a rail row's pick from firing too,
    // which moved the drawing target and rebuilt the row out from under the
    // press that was still running.
    //
    // ⛔The claim is MOUNTED, not written here. It used to be three inline
    // `Listener` lines that [ControlPressClaim] also had — and while the
    // law lived in two places the buttons that mounted neither (the
    // x-sheet's toggles, the toolbar's 1·2·3·4·N) went unnoticed.
    return ControlPressClaim(
      child: IconButton(
        key: ValueKey<String>(keyValue),
        tooltip: tooltip,
        onPressed: onPressed,
        isSelected: isSelected,
        style: IconButton.styleFrom(
          // 🎯The single largest source of off-grid PAINTED edges in this
          // app — 34 of them come from this one widget, because every
          // toolbar and rail button is an AppIconButton and each draws a
          // Material shape at its own bounds. `controlLarge` is 42, and
          // 42 × 1.25 = 52.5.
          //
          // ⚠️MEASURED, and smaller than it looks: painted boxes off the
          // grid go 350 → 340 at 1.25 and 356 → 356 at 1.35. Size
          // quantization alone buys almost nothing while ORIGINS are off,
          // because a box whose origin is fractional has a fractional far
          // edge whatever its width. What this actually earns is that the
          // button stops ADDING a fraction — it is what keeps the row on
          // the grid once the origins are fixed, not what fixes them.
          //
          // ⛔So do not read this as the pattern to copy across the other
          // wrappers: the same edit on five more of them would cost five
          // diffs for the same ~3%. The origins are the lever.
          // ⛔A PROMISED BOX IS NOT OURS TO ROUND. The rails' slots are
          // 20–22px numbers the surrounding layout was built around, and
          // [[widget-between-slot-and-plate]] is the record of what a
          // changed slot costs — a hundred tests that never mention it.
          // Quantizing a token is a style choice; quantizing a promise is
          // breaking it.
          minimumSize: Size(onGrid(size.minWidth), onGrid(size.height)),
          maximumSize: Size(onGrid(size.maxWidth), onGrid(size.height)),
          padding: EdgeInsets.zero,
          iconSize: size.iconSize,
          // Its own height, not the theme's default box: a bar button and a
          // strip button are different sizes, and the app's corner is a RATIO
          // of the short axis, so each has to ask for its own.
          shape: AppShapes.control(size.height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: isSelected ? AppColors.accent : null,
        ),
        icon: icon,
      ),
    );
  }
}
