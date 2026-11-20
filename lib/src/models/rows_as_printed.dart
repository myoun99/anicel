import '../core/mapped_or_same.dart';
import 'attached_placement.dart';
import 'cut.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'project.dart';
import 'track.dart';
import 'track_conte.dart';

// A row, a cut, a track and a project as a PAGE prints them, for a page
// that compares what it prints (`AsPrinted`) and so hears nothing it does
// not print.
//
// ⛔NO PAGE PRINTS THE RAIL'S FOLDS AND TWIRLS — a folder's fold, an attach
// group's, the property lanes' twirl and their groups' (`Layer.collapsed`,
// `foldedAttaches`, `lanesExpanded`, `expandedLaneGroups`; a track's own
// row's on the track): the rails read them (`RailView.readFolds`), and
// every page compares a row with them at rest.
// 🔬Card a-frame-lane-band-lets-its-image-go-on-one-row-pick-and-not-another
// (11-20): a twirl made the cut anew without a word to the session — the
// rails hear it by the history — and the timesheet, at the next word (the
// first row pick after it), built its document again and baked its canvas
// panel once more for a twirl it does not print.
//
// The EYE is the page's own to print or not ([EyeOnThePage]).
// 🔬Card an-eye-toggle-holds-the-ui-thread (11-18): an eye toggled made
// the cut anew, and the sheet, keyed on the cut's identity, built its
// document again and repainted every page — 85 widgets and 1.4 ms a
// toggle in the test VM — for a fact it does not print.
//
// Each hands back what it was given where nothing was left to put at rest
// ([mappedOrSame]): the common case is a walk and no copy.

/// Whether a page prints a row's eye — what decides whether it compares a
/// row with its eye as it is or open.
enum EyeOnThePage {
  /// A row hidden prints otherwise: the parts of the canvas that draw the
  /// rows.
  printed,

  /// A row prints the same shown or hidden: the timesheet, the canvas
  /// area.
  notPrinted,
}

/// [row] as a page prints it: its folds and twirls at rest, and its eye
/// open where the page does not print it.
Layer rowAsPrinted(Layer row, EyeOnThePage eye) => switch (eye) {
  EyeOnThePage.printed => _foldsAtRest(row),
  EyeOnThePage.notPrinted => _foldsAtRest(
    row.isVisible ? row : row.copyWith(isVisible: true),
  ),
};

Layer _foldsAtRest(Layer row) =>
    row.collapsed ||
        row.foldedAttaches.isNotEmpty ||
        row.lanesExpanded ||
        row.expandedLaneGroups.isNotEmpty
    ? row.copyWith(
        collapsed: false,
        foldedAttaches: const {},
        lanesExpanded: false,
        expandedLaneGroups: const {},
      )
    : row;

/// [rows], each as a page prints it ([rowAsPrinted]).
List<Layer> rowsAsPrinted(List<Layer> rows, EyeOnThePage eye) =>
    mappedOrSame(rows, (row) => rowAsPrinted(row, eye));

/// [cut] with every row as a page prints it ([rowAsPrinted]).
Cut cutAsPrinted(Cut cut, EyeOnThePage eye) =>
    switch (rowsAsPrinted(cut.layers, eye)) {
      final rows when identical(rows, cut.layers) => cut,
      final rows => cut.copyWith(layers: rows),
    };

// A row kept with every field a page may leave out unlike its print, and
// that print ([rowAsPrinted]): the edit a conte head takes from one to the
// other ([ConteHead.editedBy]) is the fields this page leaves out, and
// nothing else of the head.
final _asKept = Layer(
  id: const LayerId('as-kept'),
  name: '',
  frames: const [],
  timeline: const {},
  isVisible: false,
  collapsed: true,
  foldedAttaches: AttachedPlacement.values.toSet(),
  lanesExpanded: true,
  expandedLaneGroups: const {'as-kept'},
);
final _printOfKept = {
  for (final eye in EyeOnThePage.values) eye: rowAsPrinted(_asKept, eye),
};

/// [head] as a page prints the rows wearing it — [head] itself where it
/// was so already.
ConteHead headAsPrinted(ConteHead head, EyeOnThePage eye) {
  final printed = head.editedBy(_asKept, _printOfKept[eye]!);
  return printed == head ? head : printed;
}

ConteEntry _entryAsPrinted(ConteEntry entry, EyeOnThePage eye) =>
    switch (headAsPrinted(entry.head, eye)) {
      final head when identical(head, entry.head) => entry,
      final head => entry.copyWith(head: head),
    };

/// [conte] with every head as a page prints it ([headAsPrinted]) — its
/// base's and each entry's.
TrackConte conteAsPrinted(TrackConte conte, EyeOnThePage eye) {
  final base = switch (conte.base) {
    final head? => headAsPrinted(head, eye),
    null => null,
  };
  final below = mappedOrSame(
    conte.below,
    (entry) => _entryAsPrinted(entry, eye),
  );
  final above = mappedOrSame(
    conte.above,
    (entry) => _entryAsPrinted(entry, eye),
  );
  return identical(base, conte.base) &&
          identical(below, conte.below) &&
          identical(above, conte.above)
      ? conte
      : TrackConte(base: base, below: below, above: above);
}

/// [track] as a page prints it: every row a picture of it draws by — its
/// cuts' ([cutAsPrinted]), its SE rows, its transition row, and the conte's
/// heads ([conteAsPrinted]), which its rows wear: a row riding the conte
/// toggled writes its eye and its folds to its head too — and its own row's
/// twirls at rest.
///
/// 🔬For the canvas AREA (card an-eye-toggle-holds-the-ui-thread, 11-18,
/// step 3b): the picture prints these eyes and hears them itself; the area
/// prints only the stood row's and the camera's framed row's, which it
/// hears as the stood row's refusal and the camera backdrop. In the S5_BA
/// measuring copy the conte was the one thing an eye still changed.
Track trackAsPrinted(Track track, EyeOnThePage eye) {
  final cuts = mappedOrSame(track.cuts, (cut) => cutAsPrinted(cut, eye));
  final se = rowsAsPrinted(track.seLayers, eye);
  final transition = rowAsPrinted(track.transitionLayer, eye);
  final conte = conteAsPrinted(track.conte, eye);
  final twirled =
      track.lanesExpanded || track.expandedLaneGroups.isNotEmpty;
  return identical(cuts, track.cuts) &&
          identical(se, track.seLayers) &&
          identical(transition, track.transitionLayer) &&
          identical(conte, track.conte) &&
          !twirled
      ? track
      : track.copyWith(
          cuts: cuts,
          seLayers: se,
          transitionLayer: transition,
          conte: conte,
          lanesExpanded: false,
          expandedLaneGroups: const {},
        );
}

/// [project] as a page prints it: every track of every timeline
/// ([trackAsPrinted]).
Project projectAsPrinted(Project project, EyeOnThePage eye) =>
    project.withTracksOfEveryTimeline(
      (tracks) => mappedOrSame(tracks, (track) => trackAsPrinted(track, eye)),
    );
