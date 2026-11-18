import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'track.dart';
import 'track_conte.dart';

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

// A row's eye opened, as the edit its conte head takes it by
// ([ConteHead.editedBy]): that field, and nothing else of the head.
final _eyeShut = Layer(
  id: const LayerId('eye'),
  name: '',
  frames: const [],
  timeline: const {},
  isVisible: false,
);
final _eyeOpened = _eyeShut.copyWith(isVisible: true);

/// [head] with its eye open — [head] itself where it was open already.
ConteHead headWithEyeOpen(ConteHead head) {
  final open = head.editedBy(_eyeShut, _eyeOpened);
  return open == head ? head : open;
}

ConteEntry _entryWithEyeOpen(ConteEntry entry) =>
    switch (headWithEyeOpen(entry.head)) {
      final head when identical(head, entry.head) => entry,
      final head => entry.copyWith(head: head),
    };

/// [conte] with every head's eye open ([headWithEyeOpen]) — its base's and
/// each entry's.
TrackConte conteWithEyesOpen(TrackConte conte) {
  final base = switch (conte.base) {
    final head? => headWithEyeOpen(head),
    null => null,
  };
  final below = mappedOrSame(conte.below, _entryWithEyeOpen);
  final above = mappedOrSame(conte.above, _entryWithEyeOpen);
  return identical(base, conte.base) &&
          identical(below, conte.below) &&
          identical(above, conte.above)
      ? conte
      : TrackConte(base: base, below: below, above: above);
}

/// [track] with every eye open that a picture of it draws by — its cuts'
/// rows ([cutWithEyesOpen]), its SE rows, its transition row, and the
/// conte's heads ([conteWithEyesOpen]), which its rows wear: a row riding
/// the conte toggled writes its eye to its head too.
///
/// 🔬For the canvas AREA (card an-eye-toggle-holds-the-ui-thread, 11-18,
/// step 3b): the picture prints these eyes and hears them itself; the area
/// prints only the stood row's and the camera's framed row's, which it
/// hears as the stood row's refusal and the camera backdrop. In the S5_BA
/// measuring copy the conte was the one thing an eye still changed.
Track trackWithEyesOpen(Track track) {
  final cuts = mappedOrSame(track.cuts, cutWithEyesOpen);
  final se = rowsWithEyesOpen(track.seLayers);
  final transition = rowWithEyeOpen(track.transitionLayer);
  final conte = conteWithEyesOpen(track.conte);
  return identical(cuts, track.cuts) &&
          identical(se, track.seLayers) &&
          identical(transition, track.transitionLayer) &&
          identical(conte, track.conte)
      ? track
      : track.copyWith(
          cuts: cuts,
          seLayers: se,
          transitionLayer: transition,
          conte: conte,
        );
}
