import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/rows_as_printed.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:flutter_test/flutter_test.dart';

// A page compares a track as `trackAsPrinted` makes it: every row a
// picture of it draws by — the conte's heads, which its rows wear, with
// them — has the rail's folds and twirls at rest, and its eye open where
// the page does not print it. Nothing else is touched. Cards
// an-eye-toggle-holds-the-ui-thread (step 3b) and
// a-frame-lane-band-lets-its-image-go-on-one-row-pick-and-not-another.

const _id = TrackId('t');

/// A row's folds and twirls, every one of them away from rest.
Layer _folded(Layer row) => row.copyWith(
  collapsed: true,
  foldedAttaches: {AttachedPlacement.above},
  lanesExpanded: true,
  expandedLaneGroups: {'transform'},
);

ConteHead _foldedHead(ConteHead head) => ConteHead(
  name: head.name,
  opacity: head.opacity,
  isVisible: head.isVisible,
  onTimesheet: head.onTimesheet,
  collapsed: true,
  foldedAttaches: {AttachedPlacement.below},
  lanesExpanded: true,
  expandedLaneGroups: {'transform'},
);

/// What a page leaves out of a row, as it reads on [row].
({bool shown, bool folded}) _leftOut(Layer row) => (
  shown: row.isVisible,
  folded:
      row.collapsed ||
      row.foldedAttaches.isNotEmpty ||
      row.lanesExpanded ||
      row.expandedLaneGroups.isNotEmpty,
);

({bool shown, bool folded}) _headLeftOut(ConteHead head) => (
  shown: head.isVisible,
  folded:
      head.collapsed ||
      head.foldedAttaches.isNotEmpty ||
      head.lanesExpanded ||
      head.expandedLaneGroups.isNotEmpty,
);

Layer _row(String id, {bool shown = true}) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  timeline: const {},
  isVisible: shown,
);

Track _track({
  Layer Function(Layer row) cutRow = _same,
  Layer Function(Layer row) seRow = _same,
  Layer Function(Layer row) transition = _same,
  ConteHead Function(ConteHead head) base = _sameHead,
  ConteHead Function(ConteHead head) below = _sameHead,
  ConteHead Function(ConteHead head) above = _sameHead,
}) => Track(
  id: _id,
  name: 'V1',
  cuts: [
    Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 24,
      canvasSize: const CanvasSize(width: 100, height: 100),
      layers: [_row('a'), cutRow(_row('b'))],
    ),
  ],
  seLayers: [seRow(createTrackSeLayer(trackId: _id, slot: 0))],
  transitionLayer: transition(createTrackTransitionLayer(_id)),
  conte: TrackConte(
    base: base(const ConteHead(name: 'conte')),
    below: [_entry('under', below)],
    above: [_entry('over', above)],
  ),
);

Layer _same(Layer row) => row;
ConteHead _sameHead(ConteHead head) => head;
Layer _hidden(Layer row) => row.copyWith(isVisible: false);
ConteHead _hiddenHead(ConteHead head) => ConteHead(
  name: head.name,
  opacity: head.opacity,
  isVisible: false,
  onTimesheet: head.onTimesheet,
);

ConteEntry _entry(String name, ConteHead Function(ConteHead head) made) =>
    ConteEntry(
      key: ConteKey(name),
      head: made(ConteHead(name: name, opacity: .5, onTimesheet: false)),
    );

void main() {
  for (final eye in EyeOnThePage.values) {
    group('a page with the eye ${eye.name}', () {
      final eyeOpened = eye == EyeOnThePage.notPrinted;

      test('a track with nothing to leave out is handed back as it is', () {
        final track = _track();
        expect(trackAsPrinted(track, eye), same(track));
      });

      test('a cut row\'s folds and twirls are put at rest, and only the '
          'cuts are new', () {
        final track = _track(cutRow: _folded);
        final printed = trackAsPrinted(track, eye);
        expect(
          printed.cuts.single.layers.map(_leftOut),
          everyElement((shown: true, folded: false)),
        );
        expect(printed.seLayers, same(track.seLayers));
        expect(printed.transitionLayer, same(track.transitionLayer));
        expect(printed.conte, same(track.conte));
      });

      test('an SE row\'s folds and twirls are put at rest, and only the SE '
          'rows are new', () {
        final track = _track(seRow: _folded);
        final printed = trackAsPrinted(track, eye);
        expect(_leftOut(printed.seLayers.single), (shown: true, folded: false));
        expect(printed.cuts, same(track.cuts));
        expect(printed.transitionLayer, same(track.transitionLayer));
      });

      test('the transition row\'s folds and twirls are put at rest, and '
          'only it is new', () {
        final track = _track(transition: _folded);
        final printed = trackAsPrinted(track, eye);
        expect(_leftOut(printed.transitionLayer), (shown: true, folded: false));
        expect(printed.cuts, same(track.cuts));
        expect(printed.seLayers, same(track.seLayers));
      });

      test('the track\'s own row\'s twirls are put at rest, and nothing '
          'under it is new', () {
        final track = _track().copyWith(
          lanesExpanded: true,
          expandedLaneGroups: {'transform'},
        );
        final printed = trackAsPrinted(track, eye);
        expect(printed.lanesExpanded, isFalse);
        expect(printed.expandedLaneGroups, isEmpty);
        expect(printed.cuts, same(track.cuts));
        expect(printed.seLayers, same(track.seLayers));
        expect(printed.transitionLayer, same(track.transitionLayer));
        expect(printed.conte, same(track.conte));
      });

      test('the conte\'s heads\' folds and twirls are put at rest — the '
          'base\'s, an entry\'s under it and over it — and nothing else of '
          'them', () {
        final track = _track(
          base: _foldedHead,
          below: _foldedHead,
          above: _foldedHead,
        );
        final printed = trackAsPrinted(track, eye);
        expect(
          [
            printed.conte.base!,
            for (final entry in [
              ...printed.conte.below,
              ...printed.conte.above,
            ])
              entry.head,
          ].map(_headLeftOut),
          everyElement((shown: true, folded: false)),
        );
        expect(
          printed.conte.below.single.head,
          const ConteHead(name: 'under', opacity: .5, onTimesheet: false),
          reason: 'its other fields the head\'s own',
        );
        expect(printed.cuts, same(track.cuts));
      });

      test('every eye shut: ${eyeOpened ? 'opened' : 'kept shut'}', () {
        final track = _track(
          cutRow: _hidden,
          seRow: _hidden,
          transition: _hidden,
          base: _hiddenHead,
          below: _hiddenHead,
          above: _hiddenHead,
        );
        final printed = trackAsPrinted(track, eye);
        expect(
          [
            ...printed.cuts.single.layers.skip(1),
            ...printed.seLayers,
            printed.transitionLayer,
          ].map(_leftOut),
          everyElement((shown: eyeOpened, folded: false)),
        );
        expect(
          [
            printed.conte.base!,
            printed.conte.below.single.head,
            printed.conte.above.single.head,
          ].map(_headLeftOut),
          everyElement((shown: eyeOpened, folded: false)),
        );
        if (!eyeOpened) {
          expect(printed, same(track), reason: 'nothing to leave out');
        }
      });

      test('a row shut and folded: both left out where the eye is not '
          'printed, the folds alone where it is', () {
        final track = _track(cutRow: (row) => _folded(_hidden(row)));
        final printed = trackAsPrinted(track, eye);
        expect(
          _leftOut(printed.cuts.single.layers.last),
          (shown: eyeOpened, folded: false),
        );
      });
    });
  }
}
