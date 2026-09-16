import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';

/// The app's small switch: the Material switch shrunk to a line's height.
///
/// ⛔ONE spelling of it. The export window's toggle rows wrote this shape in
/// place, and the import window's bake cells need the same one — two copies
/// of "a switch that fits a row" drift apart the first time either is
/// touched.
///
/// 🚨★★★AND IT CLAIMS ITS PRESS, like every other control in the app
/// (`ControlPressClaim` carries the law and 유저's four statements of it).
/// A switch sits in panels that scroll, and a mouse is hardcoded to a ONE
/// PIXEL drag threshold — so before this, a click that wobbled inside the
/// switch handed the pointer to the panel and the toggle was cancelled.
/// 유저 answered the shape on board `press-law-switches`: **탭만** — pressed
/// and released on it toggles, and Material's thumb drag is gone. That is
/// the default [PressFire.upInside] every other control outside a rail
/// column already has; the switch stops being the exception rather than
/// gaining a rule.
///
/// [width] bounds it where a column has to know its width in advance; left
/// null the switch keeps its own proportions at [height].
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 24,
    this.width,
    this.switchKey,
  });

  final bool value;

  /// Null draws it disabled — which is also how a value the context decided
  /// is shown: on screen, and not the user's to change.
  final ValueChanged<bool>? onChanged;
  final double height;
  final double? width;

  /// Put on the inner [Switch], where the tests and the rows find it.
  final Key? switchKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: FittedBox(
      // ⚠️The claim wraps the SWITCH ITSELF, not the box around it. The
      // press-law scan reads a control's ENCLOSING line, so a claim mounted
      // further out leaves the switch reading as bare — and a press on the
      // padding is not a press on the switch anyway.
      child: ControlPressClaim(
        // ⚠️Only this site knows what the press MEANS — for a switch, the
        // value it does not hold. The inner control keeps its enabled look
        // and stops firing (`silentChange`), so nothing fires twice.
        onPressed: onChanged == null ? null : () => onChanged!(!value),
        child: Switch(
          key: switchKey,
          value: value,
          onChanged: silentChange(onChanged),
        ),
      ),
    ),
  );
}
