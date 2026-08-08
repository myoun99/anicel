import '../core/collection_equality.dart';
import 'cut.dart';
import 'layer.dart';
import 'layer_effect.dart';
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
    List<LayerEffect> effects = const [],
    this.type = TrackType.video,
    this.opacity = 1.0,
    this.fxEnabled = true,
  }) : cuts = List.unmodifiable(cuts),
       seLayers = List.unmodifiable(seLayers),
       effects = List.unmodifiable(effects),
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

  /// The V track's EFFECT CHAIN — the same [LayerEffect] vocabulary a layer
  /// carries, one level up: a layer's chain filters that layer's picture,
  /// and this one filters the whole COMPOSITED CUT under the playhead (user
  /// 2026-08-08: "레이어에 fx 거는 거랑 똑같이 컷에 fx를 거는 느낌").
  ///
  /// TRACK-owned with keys on the GLOBAL frame axis, exactly like
  /// [transformTrack] and for the same reason (R4): a cut trim or reorder
  /// must not drag the V row's authoring with it. A grade that should end
  /// with a cut is keyed to end there.
  ///
  /// Applied where the pose and the fade are applied — around the cut's
  /// composited picture in each render route, never baked — and bypassed
  /// together with them by [fxEnabled].
  final List<LayerEffect> effects;

  final TrackType type;

  /// The V track's STATIC opacity (R9 #21) — the resting value the
  /// animated fade lane multiplies, exactly as a layer's static opacity
  /// carries its animated one ([resolveOpacityTrackAt]'s contract). The
  /// track had only the animated lane, so "make this whole track 50%"
  /// meant authoring keys.
  ///
  /// Unlike the fade, this is NOT an fx: a layer's static opacity is not
  /// gated by its fx switch either, so [fxEnabled] off still composites
  /// at this value.
  final double opacity;

  /// The track's fx MASTER (R9 #21), persisted like every fx switch since
  /// R8. False bypasses the track's whole cut-level fx work — the pose, the
  /// fade AND the [effects] chain — on every cut it owns, which is what the
  /// V row's switch means when the user reaches for it: the per-cut switches
  /// under it stay as they were.
  final bool fxEnabled;

  Track copyWith({
    TrackId? id,
    String? name,
    List<Cut>? cuts,
    List<Layer>? seLayers,
    TransformTrack? transformTrack,
    List<LayerEffect>? effects,
    TrackType? type,
    double? opacity,
    bool? fxEnabled,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      cuts: cuts ?? this.cuts,
      seLayers: seLayers ?? this.seLayers,
      transformTrack: transformTrack ?? this.transformTrack,
      effects: effects ?? this.effects,
      type: type ?? this.type,
      opacity: opacity ?? this.opacity,
      fxEnabled: fxEnabled ?? this.fxEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'cuts': cuts.map((cut) => cut.toJson()).toList(),
    'seLayers': seLayers.map((layer) => layer.toJson()).toList(),
    if (transformTrack.isNotEmpty) 'transform': transformTrack.toJson(),
    if (effects.isNotEmpty)
      'effects': [for (final effect in effects) effect.toJson()],
    'type': type.name,
    // R8's rule: a default is silence. Files written before R9 carry
    // neither key and open at 1.0 / on, which is what they always were.
    if (opacity != 1.0) 'opacity': opacity,
    if (!fxEnabled) 'fxEnabled': false,
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
    final opacity = (json['opacity'] as num?)?.toDouble() ?? 1.0;
    final fxEnabled = json['fxEnabled'] as bool? ?? true;
    final effectsJson = json['effects'] as List<dynamic>?;
    final effects = <LayerEffect>[
      for (final effect in effectsJson ?? const [])
        LayerEffect.fromJson(effect as Map<String, dynamic>),
    ];
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
        effects: effects,
        type: TrackType.values.byName(json['type'] as String),
        opacity: opacity,
        fxEnabled: fxEnabled,
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
      effects: effects,
      type: TrackType.values.byName(json['type'] as String),
      opacity: opacity,
      fxEnabled: fxEnabled,
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
          listEquals(other.effects, effects) &&
          other.type == type &&
          other.opacity == opacity &&
          other.fxEnabled == fxEnabled;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(cuts),
    Object.hashAll(seLayers),
    transformTrack,
    Object.hashAll(effects),
    type,
    opacity,
    fxEnabled,
  );

  @override
  String toString() =>
      'Track(id: $id, name: $name, cuts: $cuts, seLayers: $seLayers, '
      'transform: $transformTrack, type: $type)';
}
