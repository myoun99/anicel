import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'layer.dart';
import 'track.dart';

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

/// [track] with every row's eye open that a picture of it draws by — its
/// cuts' rows ([cutWithEyesOpen]), its SE rows and its transition row.
/// The conte's heads ([Track.conte]) keep theirs: only these rows' eyes
/// are known to be heard by the picture itself.
///
/// 🔬For the canvas AREA (card an-eye-toggle-holds-the-ui-thread, 11-18,
/// step 3b): the picture prints these eyes and hears them itself; the area
/// prints only the stood row's and the camera's framed row's, which it
/// hears as the stood row's refusal and the camera backdrop.
Track trackWithEyesOpen(Track track) {
  final cuts = mappedOrSame(track.cuts, cutWithEyesOpen);
  final se = rowsWithEyesOpen(track.seLayers);
  final transition = rowWithEyeOpen(track.transitionLayer);
  return identical(cuts, track.cuts) &&
          identical(se, track.seLayers) &&
          identical(transition, track.transitionLayer)
      ? track
      : track.copyWith(cuts: cuts, seLayers: se, transitionLayer: transition);
}
