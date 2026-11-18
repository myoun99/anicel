import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/eyes_open.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:flutter_test/flutter_test.dart';

// The canvas area compares a track as `trackWithEyesOpen` makes it (card
// an-eye-toggle-holds-the-ui-thread, step 3b): every row the picture
// hears for itself has its eye opened, and nothing else is touched.

const _id = TrackId('t');

Layer _row(String id, {bool shown = true}) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  timeline: const {},
  isVisible: shown,
);

Track _track({
  bool cutRowShown = true,
  bool seRowShown = true,
  bool transitionShown = true,
  bool conteShown = true,
}) => Track(
  id: _id,
  name: 'V1',
  cuts: [
    Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 24,
      canvasSize: const CanvasSize(width: 100, height: 100),
      layers: [_row('a'), _row('b', shown: cutRowShown)],
    ),
  ],
  seLayers: [
    createTrackSeLayer(trackId: _id, slot: 0).copyWith(isVisible: seRowShown),
  ],
  transitionLayer: createTrackTransitionLayer(
    _id,
  ).copyWith(isVisible: transitionShown),
  conte: TrackConte(base: ConteHead(name: 'conte', isVisible: conteShown)),
);

void main() {
  test('a track with every eye open is handed back as it is', () {
    final track = _track();
    expect(trackWithEyesOpen(track), same(track));
  });

  test('a cut row\'s eye is opened, and only the cuts are new', () {
    final track = _track(cutRowShown: false);
    final open = trackWithEyesOpen(track);
    expect(open.cuts.single.layers.map((row) => row.isVisible), [true, true]);
    expect(open.seLayers, same(track.seLayers));
    expect(open.transitionLayer, same(track.transitionLayer));
  });

  test('an SE row\'s eye is opened, and only the SE rows are new', () {
    final track = _track(seRowShown: false);
    final open = trackWithEyesOpen(track);
    expect(open.seLayers.single.isVisible, isTrue);
    expect(open.cuts, same(track.cuts));
    expect(open.transitionLayer, same(track.transitionLayer));
  });

  test('the transition row\'s eye is opened, and only it is new', () {
    final track = _track(transitionShown: false);
    final open = trackWithEyesOpen(track);
    expect(open.transitionLayer.isVisible, isTrue);
    expect(open.cuts, same(track.cuts));
    expect(open.seLayers, same(track.seLayers));
  });

  test('the conte\'s head keeps its eye', () {
    final track = _track(cutRowShown: false, conteShown: false);
    final open = trackWithEyesOpen(track);
    expect(open.conte, same(track.conte));
    expect(open.conte.base!.isVisible, isFalse);
  });
}
