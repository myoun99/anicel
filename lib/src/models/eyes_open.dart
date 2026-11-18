import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'layer.dart';

// A row, a cut and a track's rows as a page that NEVER PRINTS THE EYE
// reads them: every eye open. The timesheet prints a row the same shown or
// hidden, so its memo compares what it prints as these make it
// (`EyesOpen`), and an eye toggled reprints none of it.
//
// 🔬Card an-eye-toggle-holds-the-ui-thread (11-18): an eye toggled made
// the cut anew, and the sheet, keyed on the cut's identity, built its
// document again and repainted every page — 85 widgets and 1.4 ms a
// toggle in the test VM — for a fact it does not print.
//
// Each hands back what it was given where every eye was already open
// ([mappedOrSame]): the common case is a walk and no copy.

/// [row] with its eye open.
Layer rowWithEyeOpen(Layer row) =>
    row.isVisible ? row : row.copyWith(isVisible: true);

/// [rows], each with its eye open ([rowWithEyeOpen]).
List<Layer> rowsWithEyesOpen(List<Layer> rows) =>
    mappedOrSame(rows, rowWithEyeOpen);

/// [cut] with every row's eye open ([rowWithEyeOpen]).
Cut cutWithEyesOpen(Cut cut) => switch (rowsWithEyesOpen(cut.layers)) {
  final rows when identical(rows, cut.layers) => cut,
  final rows => cut.copyWith(layers: rows),
};
