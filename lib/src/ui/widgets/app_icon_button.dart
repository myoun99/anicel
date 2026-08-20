import 'package:flutter/material.dart';

import '../layout/device_grid.dart';
import '../input/value_control_pointers.dart';
import '../theme/app_theme.dart';

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
/// into a slim status strip (same 18px glyph, tighter box). Callers pick a
/// token so a future style change lands everywhere at once.
enum AppIconButtonSize {
  /// Panel bottom bars — the reference size.
  bar(minWidth: 26, maxWidth: 30, height: 24, iconSize: 18),

  /// Slim panel status strips.
  strip(minWidth: 22, maxWidth: 26, height: 20, iconSize: 15);

  const AppIconButtonSize({
    required this.minWidth,
    required this.maxWidth,
    required this.height,
    required this.iconSize,
  });

  final double minWidth;
  final double maxWidth;
  final double height;
  final double iconSize;
}

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

  final AppIconButtonSize size;

  @override
  Widget build(BuildContext context) {
    final grid = DeviceGrid.of(context);
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
    // ⛔Released on CANCEL as well as UP: a claim that outlives its gesture
    // silently deafens every later press handed the same pointer id.
    return Listener(
      onPointerDown: (event) => claimTapForControl(event.pointer),
      onPointerUp: (event) => releaseTapForControl(event.pointer),
      onPointerCancel: (event) => releaseTapForControl(event.pointer),
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
          minimumSize: Size(
            grid.position(size.minWidth),
            grid.position(size.height),
          ),
          maximumSize: Size(
            grid.position(size.maxWidth),
            grid.position(size.height),
          ),
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
