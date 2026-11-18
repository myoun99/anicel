import '../../core/signed_memo.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/fx_plugins/fx_plugin_outcomes.dart';
import '../text/app_strings.dart' show AppText;
import '../timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectPropertyLanes;
import '../timeline/memo_token.dart' show ByIdentity, ByList;
import '../timeline/property_lane_model.dart';
import '../timeline/property_lanes_for_row.dart';
import '../timeline/timeline_lane_provider.dart' show KeptLaneLists;
import '../timeline/transform_lane_policy.dart' show cameraPropertyLanes;

/// What the conte rail reads every row's lanes with, the row aside: the
/// groups twirled open, the shot an S row is posed in, and this device's
/// plugins — whether it has one, and how its runs went.
typedef StoryboardLaneReads = ({
  Set<String> expandedGroupKeys,
  CanvasSize? poseCentre,
  bool Function(FxPluginDescription plugin)? hasPlugin,
  FxPluginOutcomes? outcomes,
});

/// One V track's EFFECT lanes, below its Transform group — the same rows a
/// layer's chain gets, one level up: this chain filters the whole
/// composited cut (user 2026-08-08). Values resolve at GLOBAL frames, the
/// axis the keys live on. Its groups open as the track keeps them, by
/// lane id as a layer row keeps its own (F-360, `Track.expandedLaneGroups`).
List<PropertyLaneRow> trackEffectLanes(
  Track track,
  StoryboardLaneReads reads,
) {
  if (track.effects.isEmpty) {
    return const [];
  }
  return effectPropertyLanes(
    track.effects,
    // A track's chain is no cut's: it names no row.
    cutRows: const [],
    isExpanded: (effectId) =>
        track.expandedLaneGroups.contains(effectGroupLaneId(effectId)),
    valueAt: (effectId, parameterId, time) => effectParameterValueAtTime(
      track.effects,
      effectId,
      parameterId,
      time,
    ),
    hasPlugin: reads.hasPlugin,
    pluginOutcomes: switch (reads.outcomes) {
      final outcomes? => (outcomes: outcomes, owner: track.id),
      null => null,
    },
  );
}

/// One S row's lanes: THE list an SE row twirls down ([propertyLanesForRow],
/// F-101), read on [track]'s rail — [layer] itself at the rail's global
/// frame (the same raw-track resolution the timeline's value column uses —
/// fx bypass never touches authoring values), an unkeyed pose in the middle
/// of the camera frame. No cut is consulted: the row belongs to the track.
///
/// C5 (2026-08-17) holds by construction: the list is the timeline's lane
/// law's own, so an S row twirls down exactly the lanes its timeline twin
/// draws. ↩️The storyboard once mounted the Audio lane off the twirl alone,
/// and an empty S row showed a waveform strip its twin never drew.
///
/// The display size comes from the SESSION ([StoryboardLaneReads.poseCentre]),
/// exactly as the V row's lanes take it — never from "the cut that happens
/// to be open", which made another track's S row show its values as
/// defaults.
List<PropertyLaneRow> seRowLanes(
  Track track,
  Layer layer,
  StoryboardLaneReads reads,
) => propertyLanesForRow(
  layer: layer,
  rows: track.seLayers,
  expandedGroupKeys: reads.expandedGroupKeys,
  valueSourceAt: (frameIndex) => (layer: layer, frame: frameIndex),
  // The display size comes from the SESSION, exactly as the V row's
  // lanes take it — never from "the cut that happens to be open", which
  // made another track's S row show its values as defaults.
  poseCentre: reads.poseCentre,
  hasPlugin: reads.hasPlugin,
  pluginOutcomes: reads.outcomes,
);

/// [row]'s lanes in [cut] — THE list its timeline row twirls down
/// ([propertyLanesForRow]), with its groups twirled as the timeline's
/// are; [valued] reads them at a frame of the cut's own.
List<PropertyLaneRow> conteRowLanes(
  Cut cut,
  Layer row,
  StoryboardLaneReads reads, {
  required bool valued,
}) => propertyLanesForRow(
  layer: row,
  rows: cut.layers,
  expandedGroupKeys: reads.expandedGroupKeys,
  valueSourceAt: valued ? (frame) => (layer: row, frame: frame) : null,
  poseCentre: valued ? cut.canvasSize : null,
  hasPlugin: reads.hasPlugin,
  pluginOutcomes: reads.outcomes,
);

/// Whose lanes a list is on the conte's rail: a track's row — its fx chain,
/// its camera, its S row at a slot or its conte row at a seat.
/// [layer] — the layer a projection row has in hand — worn by the ROW,
/// under the row's own [rowId]: the rail stands on, lights and keys the
/// row's lanes by that id, its labels' and its strips' alike (I-73 ④ⓔ).
/// ONE object while [layer] is, as a lane row's facts name its layer by
/// identity (`TimelineLaneControlsRow.facts`).
Layer wornByRow(Layer layer, LayerId rowId) =>
    _wornByRow.resolve(layer, rowId, () => layer.copyWith(id: rowId));

final SignedMemo<LayerId, Layer> _wornByRow = SignedMemo(
  'layer worn by its row',
);

/// A projection row's layer in hand: the cut it is of, the layer, and
/// whether the session stands in that cut.
typedef ProjectionRowInHand = ({Cut cut, Layer layer, bool stood});

typedef _LaneOwner = ({TrackId track, String row, int at});

/// THE conte rail's lane lists as its rows ask them: a row's handed back —
/// the same list, the same lanes — while all it is read from holds, so a
/// lane row kept while its lane is the same object
/// ([TimelineLaneControlsRow.facts]) is kept through a pass that changed
/// nothing. The keep is the timeline's ([KeptLaneLists]); what each list is
/// read from is said here, beside the reader it keys.
///
/// 🔬Card the-conte-rails-lane-rows-are-built-again-with-the-rail (11-08):
/// read anew at every pass, every lane was a new object — and the V row's
/// lanes rode a carrier made anew too — so no lane row of the rail could be
/// told it had not changed: a pick of an S row drew both tracks' fx heads
/// again, and each let its image go.
///
/// ⛔Each key is EVERYTHING its reader reads, each as the value it reads: a
/// read added to a reader and left out here is a lane kept across a change
/// of it. A track's lists live while the track is one of the project's.
final class KeptStoryboardLanes {
  /// Lists kept for the rows of [project] as it stands at each ask.
  KeptStoryboardLanes(this.project);

  final Project Function() project;
  final KeptLaneLists<_LaneOwner> _lists = KeptLaneLists();
  final Map<TrackId, Layer> _carriers = {};
  List<Track>? _tracks;

  /// Lets go of every track [project] no longer holds.
  void _standOn() {
    final tracks = project().tracks;
    if (identical(tracks, _tracks)) {
      return;
    }
    _tracks = tracks;
    final live = {for (final track in tracks) track.id};
    _lists.keepWhere((owner) => live.contains(owner.track));
    _carriers.removeWhere((id, _) => !live.contains(id));
  }

  /// The layer [track]'s V row wears its own lanes on, on this rail — its
  /// lane carrier ([trackTransformLaneCarrierId]) — by its labels, its
  /// strips and the graphs over them alike: one object while the track
  /// stands, as a lane row's facts name it by identity.
  Layer carrierOf(Track track) {
    _standOn();
    return _carriers.putIfAbsent(
      track.id,
      () => Layer(
        id: trackTransformLaneCarrierId(track.id),
        name: 'V',
        frames: const [],
      ),
    );
  }

  /// [track]'s fx chain's lanes ([trackEffectLanes]).
  List<PropertyLaneRow> trackEffects(
    Track track,
    StoryboardLaneReads reads,
  ) {
    _standOn();
    return _lists.of(
      (track: track.id, row: 'fx', at: 0),
      identity: track.effects,
      key: (
        ByIdentity(track.expandedLaneGroups),
        _plugins(track.effects, reads),
        // A lane's name is a word of the app's language.
        AppText.settings.value,
      ),
      build: () => trackEffectLanes(track, reads),
    );
  }

  /// [layer]'s lanes, [track]'s S row at [slot] ([seRowLanes]).
  List<PropertyLaneRow> seRow(
    Track track,
    int slot,
    Layer layer,
    StoryboardLaneReads reads,
  ) {
    _standOn();
    return _lists.of(
      (track: track.id, row: 'se', at: slot),
      identity: layer,
      key: (
        ByIdentity(track.seLayers),
        ByIdentity(reads.expandedGroupKeys),
        reads.poseCentre,
        _plugins(layer.effects, reads),
        AppText.settings.value,
      ),
      build: () => seRowLanes(track, layer, reads),
    );
  }

  /// The camera lanes of [track]'s camera row, its layer [inHand] in its
  /// cut ([cameraPropertyLanes]) — valued in the cut where stood.
  List<PropertyLaneRow> camera(Track track, ProjectionRowInHand inHand) {
    final (:cut, :layer, :stood) = inHand;
    _standOn();
    final canvasSize = stood ? cut.canvasSize : null;
    return _lists.of(
      (track: track.id, row: 'camera', at: 0),
      identity: layer,
      key: (ByIdentity(cut.camera.track), canvasSize, AppText.settings.value),
      build: () =>
          cameraPropertyLanes(layer, cut.camera.track, canvasSize: canvasSize),
    );
  }

  /// The lanes of [track]'s conte row at [seat], its layer [inHand] in
  /// its cut ([conteRowLanes]) — valued in the cut where stood.
  List<PropertyLaneRow> conteRow(
    Track track,
    int seat,
    ProjectionRowInHand inHand,
    StoryboardLaneReads reads,
  ) {
    final (:cut, :layer, :stood) = inHand;
    _standOn();
    return _lists.of(
      (track: track.id, row: 'conte', at: seat),
      identity: layer,
      key: (
        ByIdentity(cut.layers),
        ByIdentity(reads.expandedGroupKeys),
        // Valued where stood, on its canvas; the canvas, or none, says which.
        stood ? cut.canvasSize : null,
        _plugins(layer.effects, reads),
        AppText.settings.value,
      ),
      build: () => conteRowLanes(cut, layer, reads, valued: stood),
    );
  }

  /// What a chain of [effects]' lanes read of this device's plugins:
  /// whether it has each one, and how their runs went.
  static Object? _plugins(
    List<LayerEffect> effects,
    StoryboardLaneReads reads,
  ) => (
    ByList([
      for (final effect in effects)
        if (effect.plugin case final plugin?) reads.hasPlugin?.call(plugin),
    ]),
    ByIdentity(reads.outcomes),
  );
}
