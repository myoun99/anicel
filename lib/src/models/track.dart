import '../core/collection_equality.dart';
import 'cut.dart';
import 'layer.dart';
import 'layer_section_defaults.dart';
import 'track_id.dart';
import 'track_se_migration.dart';
import 'track_transform_migration.dart';
import 'transform_track.dart';

enum TrackType { video, audio }

class Track {
  Track({
    required this.id,
    required this.name,
    required List<Cut> cuts,
    List<Layer> seLayers = const [],
    TransformTrack? transformTrack,
    this.type = TrackType.video,
  }) : cuts = List.unmodifiable(cuts),
       seLayers = List.unmodifiable(seLayers),
       transformTrack = transformTrack ?? TransformTrack.empty();

  final TrackId id;
  final String name;
  final List<Cut> cuts;

  /// The track's SE rows (S1·S2·…): TRACK-owned, timeline keys on the
  /// track's GLOBAL frame axis so a sound may cross cut boundaries. Row
  /// order is list order and the display name is [Layer.name] — the single
  /// ordering every panel renders. Cut trims/reorders do NOT move SE
  /// content (NLE audio-track semantics — the precondition for
  /// cut-crossing sounds).
  final List<Layer> seLayers;

  /// The V track's own effects (R4): pose lanes + the fade's opacity lane,
  /// keys on the track's GLOBAL frame axis — TRACK-owned, exactly like
  /// [seLayers]. Cut trims/reorders do NOT move these keys, keys exist
  /// with no cut under them, and moving them together is a SELECTION (the
  /// user's independence rule, 2026-07-29). Display/export resolve per
  /// global frame; never baked into composites.
  final TransformTrack transformTrack;

  final TrackType type;

  Track copyWith({
    TrackId? id,
    String? name,
    List<Cut>? cuts,
    List<Layer>? seLayers,
    TransformTrack? transformTrack,
    TrackType? type,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      cuts: cuts ?? this.cuts,
      seLayers: seLayers ?? this.seLayers,
      transformTrack: transformTrack ?? this.transformTrack,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'cuts': cuts.map((cut) => cut.toJson()).toList(),
    'seLayers': seLayers.map((layer) => layer.toJson()).toList(),
    if (transformTrack.isNotEmpty) 'transform': transformTrack.toJson(),
    'type': type.name,
  };

  factory Track.fromJson(Map<String, dynamic> json) {
    final id = TrackId.fromJson(json['id'] as Map<String, dynamic>);
    final cutsJson = (json['cuts'] as List<dynamic>).cast<Map<String, dynamic>>();
    final cuts = cutsJson.map(Cut.fromJson).toList();
    // Legacy shape (no track transform key): the V effects lived on each
    // cut — lift them onto the global axis (shape-based migration, the SE
    // lift's convention; Cut.fromJson itself ignores 'transform' now).
    final transformJson = json['transform'];
    final transformTrack = transformJson is Map<String, dynamic>
        ? TransformTrack.fromJson(transformJson)
        : liftCutTransformsToTrack(cutsJson);
    final seLayersJson = json['seLayers'] as List<dynamic>?;
    if (seLayersJson != null) {
      return Track(
        id: id,
        name: json['name'] as String,
        cuts: cuts,
        seLayers: withEnsuredTrackSeLayers(
          id,
          seLayersJson
              .map((layer) => Layer.fromJson(layer as Map<String, dynamic>))
              .toList(),
        ),
        transformTrack: transformTrack,
        type: TrackType.values.byName(json['type'] as String),
      );
    }

    // Legacy shape (no seLayers key): SE rows lived on each cut — lift
    // them onto the track's global axis (shape-based migration, the
    // codebase's convention).
    final lifted = liftCutSeLayersToTrack(id, cuts);
    return Track(
      id: id,
      name: json['name'] as String,
      cuts: lifted.cuts,
      seLayers: lifted.seLayers,
      transformTrack: transformTrack,
      type: TrackType.values.byName(json['type'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          other.id == id &&
          other.name == name &&
          listEquals(other.cuts, cuts) &&
          listEquals(other.seLayers, seLayers) &&
          other.transformTrack == transformTrack &&
          other.type == type;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(cuts),
    Object.hashAll(seLayers),
    transformTrack,
    type,
  );

  @override
  String toString() =>
      'Track(id: $id, name: $name, cuts: $cuts, seLayers: $seLayers, '
      'transform: $transformTrack, type: $type)';
}
