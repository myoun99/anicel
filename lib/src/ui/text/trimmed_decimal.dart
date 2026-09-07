/// THE numeric readout form for the value columns: round to
/// [fractionDigits] decimals, print an integer when the rounded value is
/// whole, and drop trailing zeros otherwise.
///
/// One law, because the timeline's lanes and the tool settings' drag
/// readouts are the same column to the user — a value that reads `12.5`
/// in one place must not read `12.50` in the other. The unit suffix
/// (`%`, `°`, ` px`) belongs to the lane, not to this, so it stays at the
/// call site.
String formatTrimmedDecimal(double value, {int fractionDigits = 1}) {
  final rounded = double.parse(value.toStringAsFixed(fractionDigits));
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toString();
}
