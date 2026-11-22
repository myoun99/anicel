import 'package:flutter/foundation.dart' show listEquals;

import '../../core/signed_memo.dart';
import '../../models/camera_row_reach.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/lane_key_walk.dart' show filmKeyFrames;
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
  final Map<({TrackId track, LayerId row}), FilmLaneKeys> _film = {};
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
    _film.removeWhere((owner, _) => !live.contains(owner.track));
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

  /// The keys of [track]'s projection row [row] on the film — every cut's
  /// ([FilmLaneKeys]) — read off each cut with [read]: what its lane
  /// labels' arrows walk (F-625). One per row while the track stands.
  FilmLaneKeys filmKeys(Track track, LayerId row, ProjectionKeysRead read) {
    _standOn();
    return _film.putIfAbsent(
      (track: track.id, row: row),
      FilmLaneKeys.new,
    ).._read = read;
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
        rowsLanesRead(track.seLayers),
        groupsOpenOn(layer.id, reads.expandedGroupKeys),
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
        rowsLanesRead(cut.layers),
        groupsOpenOn(layer.id, reads.expandedGroupKeys),
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

/// What a projection row's keys are read off a cut with: the layer the row
/// shows of it, and that layer's lanes there — every one, whatever the
/// twirls (the rail's `_ProjectionLanes`, the two its strips read too).
typedef ProjectionKeysRead = ({
  Layer? Function(Cut cut) layerOf,
  List<PropertyLaneRow> Function(Cut cut, Layer layer) lanesOf,
});

/// A PROJECTION ROW'S KEYS ON THE FILM (F-625): each cut's own keyed
/// frames by lane, and the track frames the row draws a lane's keys at
/// over all its cuts — what that lane's label walks with its arrows.
///
/// 🚨Read at every pass of the rail, for every lane label it shows, over
/// EVERY cut of the track — so nothing of it is read anew:
/// - while the track's cuts lie alike ([CameraRowReach.==], the cut by
///   identity — what the camera row itself is kept while, I-57) no lane
///   is walked again: one comparison of the reaches a pass, where each
///   lane asked every cut for its keys;
/// - a cut's keys are read once while the cut is the same OBJECT (an edit
///   makes a new cut of the one it touched and hands the rest back), and
///   a lane's keyed frames are the cut's alone — this device's plugins
///   grey a header and never take a key (`effectPropertyLanes`);
/// - a lane's frames are handed back — the SAME list — while they are the
///   same frames, so the label kept by them (`LaneKeyWalk.frames`, a fact
///   by identity) is kept through every edit that moved none of its keys,
///   and asked again by one that did, in whichever cut.
final class FilmLaneKeys {
  late ProjectionKeysRead _read;
  final Expando<Map<String, Set<int>>> _own = Expando('film lane keys');
  final Map<String, List<int>> _frames = {};

  /// The reaches [_frames] was last read over, and the lanes read over
  /// them since they last lay otherwise.
  List<CameraRowReach>? _over;
  final Set<String> _current = {};

  /// [cut]'s own keyed frames of the row's lane [laneId] — none where the
  /// cut holds no row there, or the row no such lane.
  Set<int> ownKeysOf(Cut cut, String laneId) =>
      (_own[cut] ??= _readOff(cut))[laneId] ?? const {};

  Map<String, Set<int>> _readOff(Cut cut) {
    final layer = _read.layerOf(cut);
    return {
      if (layer != null)
        for (final lane in _read.lanesOf(cut, layer))
          if (!lane.isGroupHeader) lane.laneId: lane.keyedFrames,
    };
  }

  /// The track frames the row draws a key of [laneId] at over [reaches]
  /// ([filmKeyFrames]), ascending — the same list while they are the same,
  /// and unread while [reaches] lie as they did.
  List<int> framesOf(String laneId, List<CameraRowReach> reaches) {
    if (!identical(reaches, _over)) {
      if (!listEquals(reaches, _over)) {
        _current.clear();
      }
      _over = reaches;
    }
    if (!_current.add(laneId)) {
      return _frames[laneId]!;
    }
    final frames = filmKeyFrames(reaches, (cut) => ownKeysOf(cut, laneId));
    final kept = _frames[laneId];
    return kept != null && listEquals(kept, frames)
        ? kept
        : _frames[laneId] = frames;
  }
}
