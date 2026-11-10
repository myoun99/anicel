import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_outcomes.dart';
import 'package:anicel/src/ui/storyboard/storyboard_lane_lists.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a lane list is read from: the track and the cut it stands in, the
/// row's layer, whether the session stands in that cut, and what the rail
/// reads beside them.
typedef _Ask = ({
  Track track,
  Cut cut,
  Layer layer,
  bool stood,
  StoryboardLaneReads reads,
});

/// [of] with the lists it is handed in place of its own, each the very
/// object handed: a [Track] wraps every list it is built with anew, so a
/// copy of one changes all its lists at once — no fact a lane list reads
/// off a track could be changed alone (card
/// a-track-copy-wraps-its-unchanged-lists-anew — once a copy keeps the
/// lists it is not handed, this stand-in goes).
// A stand-in in a test, never compared: the value type it implements is
// read for its lists alone.
// ignore: avoid_implementing_value_types
class _TrackOf implements Track {
  _TrackOf(
    this.of, {
    List<LayerEffect>? effects,
    Set<String>? expandedLaneGroups,
    List<Layer>? seLayers,
  }) : effects = effects ?? of.effects,
       expandedLaneGroups = expandedLaneGroups ?? of.expandedLaneGroups,
       seLayers = seLayers ?? of.seLayers;

  final Track of;

  @override
  TrackId get id => of.id;

  @override
  final List<LayerEffect> effects;

  @override
  final Set<String> expandedLaneGroups;

  @override
  final List<Layer> seLayers;

  @override
  Object? noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// 🔬Card the-conte-rails-lane-rows-are-built-again-with-the-rail (11-08):
/// THE CONTE RAIL'S LANE LISTS ARE KEPT WHILE WHAT THEY ARE READ FROM HOLDS.
///
/// The rail keeps a lane's label while its lane is the same object
/// (`TimelineLaneControlsRow.facts`), so each of its four lists comes back
/// as the same list while every fact its reader reads holds
/// ([KeptStoryboardLanes]) — and is read again the moment one does not. A
/// fact left out of a key is a label kept across a change of it; this
/// changes one at a time, as the timeline's own lanes are pinned
/// (`a_kept_lane_row_sees_every_fact_it_shows`).
void main() {
  final glow = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'com.example.glow',
    'name': 'Glow',
    'vendor': 'Example',
    'version': '1',
    'can': ['cpu'],
    'params': [
      {
        'id': 'amount',
        'kind': 'number',
        'label': 'Amount',
        'default': 5,
        'min': 0,
        'max': 10,
      },
    ],
  })!;
  LayerEffect glowAs(String id) => LayerEffect.defaults(
    id: EffectId(id),
    kind: EffectKind.plugin,
    plugin: glow,
  );
  final camera = Layer(
    id: const LayerId('cam'),
    name: 'Camera',
    kind: LayerKind.camera,
    frames: const [],
  );
  final cel = Layer(
    id: const LayerId('cel'),
    name: 'cel',
    frames: const [],
    effects: [glowAs('fx-cel')],
  );
  final se = Layer(
    id: const LayerId('se'),
    name: 'S1',
    frames: const [],
    effects: [glowAs('fx-se')],
  );
  final cut = Cut(
    id: const CutId('a'),
    name: 'a',
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [camera, cel],
  );
  final track = Track(
    id: const TrackId('t1'),
    name: 'V1',
    cuts: [cut],
    seLayers: [se],
    effects: [glowAs('fx-track')],
  );
  final twirls = <String>{};
  late FxPluginOutcomes outcomes;
  late FxPluginOutcomes otherOutcomes;
  setUp(() {
    outcomes = FxPluginOutcomes();
    otherOutcomes = FxPluginOutcomes();
  });
  tearDown(() {
    outcomes.dispose();
    otherOutcomes.dispose();
  });

  // A fresh record and a fresh plugin closure at every ask, as at every
  // pass of the rail.
  StoryboardLaneReads readsOf({
    Set<String>? expanded,
    CanvasSize? pose,
    bool hasPlugin = true,
    FxPluginOutcomes? ran,
  }) => (
    expandedGroupKeys: expanded ?? twirls,
    poseCentre: pose,
    hasPlugin: (_) => hasPlugin,
    outcomes: ran ?? outcomes,
  );
  _Ask askOf(Layer layer) =>
      (track: track, cut: cut, layer: layer, stood: true, reads: readsOf());
  final project = Project(
    id: const ProjectId('kept-conte-lanes'),
    name: 'kept conte lanes',
    createdAt: DateTime.utc(2026, 11, 11),
    tracks: [track],
  );

  /// [read]'s list for [row], asked again, is the same list; under each of
  /// [readAgain], a list read anew; under each of [keeps] — what the reader
  /// does not read — the same list. Every ask is a fresh one ([askOf]).
  void pinReader(
    String reader,
    List<PropertyLaneRow> Function(KeptStoryboardLanes kept, _Ask ask) read, {
    required Layer row,
    required Map<String, _Ask Function(_Ask ask)> readAgain,
    Map<String, _Ask Function(_Ask ask)> keeps = const {},
  }) {
    group(reader, () {
      test('asked again with nothing changed, it is the same list', () {
        final kept = KeptStoryboardLanes(() => project);
        final first = read(kept, askOf(row));
        expect(first, isNotEmpty, reason: 'a list of no lanes pins nothing');
        expect(identical(read(kept, askOf(row)), first), isTrue);
      });
      test('the language is a fact its lanes are named in', () {
        final kept = KeptStoryboardLanes(() => project);
        final first = read(kept, askOf(row));
        final settings = AppText.settings.value;
        addTearDown(() => AppText.settings.value = settings);
        AppText.settings.value = settings.copyWith(
          programLanguage: settings.programLanguage == AppLanguage.ja
              ? AppLanguage.en
              : AppLanguage.ja,
        );
        expect(identical(read(kept, askOf(row)), first), isFalse);
      });
      for (final change in readAgain.entries) {
        test('${change.key} is a fact it reads — the list is read again', () {
          final kept = KeptStoryboardLanes(() => project);
          final first = read(kept, askOf(row));
          expect(
            identical(read(kept, change.value(askOf(row))), first),
            isFalse,
            reason: 'a label kept by the old lane shows ${change.key} stale',
          );
        });
      }
      for (final change in keeps.entries) {
        test('${change.key} is no fact it reads — the list holds', () {
          final kept = KeptStoryboardLanes(() => project);
          final first = read(kept, askOf(row));
          expect(
            identical(read(kept, change.value(askOf(row))), first),
            isTrue,
            reason: 'every pass that moves ${change.key} would draw the '
                'labels again',
          );
        });
      }
    });
  }

  pinReader(
    'a V row\'s fx chain',
    (kept, ask) => kept.trackEffects(ask.track, ask.reads),
    row: cel,
    readAgain: {
      'its chain': (ask) => (
        track: _TrackOf(ask.track, effects: [...ask.track.effects]),
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'its twirls': (ask) => (
        track: _TrackOf(
          ask.track,
          expandedLaneGroups: {...ask.track.expandedLaneGroups},
        ),
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'whether this device has its plugin': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(hasPlugin: false),
      ),
      'how its plugins ran': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(ran: otherOutcomes),
      ),
    },
    keeps: {
      'a layer\'s twirls': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(expanded: {'cel|fx-cel'}),
      ),
      'the pose centre': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(pose: const CanvasSize(width: 10, height: 10)),
      ),
    },
  );

  pinReader(
    'an S row',
    (kept, ask) => kept.seRow(ask.track, 0, ask.layer, ask.reads),
    row: se,
    readAgain: {
      'its layer': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer.copyWith(name: 'S1'),
        stood: ask.stood,
        reads: ask.reads,
      ),
      'the track\'s S rows': (ask) => (
        track: _TrackOf(ask.track, seLayers: [...ask.track.seLayers]),
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'the twirls': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(expanded: {...twirls}),
      ),
      'the pose centre': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(pose: const CanvasSize(width: 10, height: 10)),
      ),
      'whether this device has its plugin': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(hasPlugin: false),
      ),
      'how its plugins ran': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(ran: otherOutcomes),
      ),
    },
  );

  pinReader(
    'the camera row',
    (kept, ask) => kept.camera(ask.track, (
      cut: ask.cut,
      layer: ask.layer,
      stood: ask.stood,
    )),
    row: camera,
    readAgain: {
      'its layer': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer.copyWith(name: 'Camera'),
        stood: ask.stood,
        reads: ask.reads,
      ),
      'the cut\'s camera': (ask) => (
        track: ask.track,
        cut: ask.cut.copyWith(camera: CutCamera.fromTrack(TransformTrack())),
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'the canvas it is valued on': (ask) => (
        track: ask.track,
        cut: ask.cut.copyWith(
          canvasSize: const CanvasSize(width: 320, height: 180),
        ),
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'whether the session stands in its cut': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: false,
        reads: ask.reads,
      ),
    },
  );

  pinReader(
    'a conte row',
    (kept, ask) => kept.conteRow(
      ask.track,
      0,
      (cut: ask.cut, layer: ask.layer, stood: ask.stood),
      ask.reads,
    ),
    row: cel,
    readAgain: {
      'its layer': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer.copyWith(name: 'cel'),
        stood: ask.stood,
        reads: ask.reads,
      ),
      'the cut\'s rows': (ask) => (
        track: ask.track,
        cut: ask.cut.copyWith(layers: [...ask.cut.layers]),
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'the twirls': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(expanded: {...twirls}),
      ),
      'the canvas it is valued on': (ask) => (
        track: ask.track,
        cut: ask.cut.copyWith(
          canvasSize: const CanvasSize(width: 320, height: 180),
        ),
        layer: ask.layer,
        stood: ask.stood,
        reads: ask.reads,
      ),
      'whether the session stands in its cut': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: false,
        reads: ask.reads,
      ),
      'whether this device has its plugin': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(hasPlugin: false),
      ),
      'how its plugins ran': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(ran: otherOutcomes),
      ),
    },
    keeps: {
      'the pose centre': (ask) => (
        track: ask.track,
        cut: ask.cut,
        layer: ask.layer,
        stood: ask.stood,
        reads: readsOf(pose: const CanvasSize(width: 10, height: 10)),
      ),
    },
  );
}
