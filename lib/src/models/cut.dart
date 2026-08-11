import '../core/collection_equality.dart';
import 'canvas_size.dart';
import 'cut_camera.dart';
import 'cut_id.dart';
import 'cut_metadata.dart';
import 'drawing_guide.dart';
import 'layer.dart';
import 'layer_section_defaults.dart';

class Cut {
  Cut({
    required this.id,
    required this.name,
    required List<Layer> layers,
    required this.duration,
    required this.canvasSize,
    this.metadata = const CutMetadata.empty(),
    this.leadingGapFrames = 0,
    CutCamera? camera,
    CutGuides? guides,
  }) : assert(leadingGapFrames >= 0),
       layers = List.unmodifiable(layers),
       camera = camera ?? CutCamera.empty(),
       guides = guides ?? CutGuides.empty;

  final CutId id;
  final String name;
  final List<Layer> layers;
  final int duration;

  /// Empty frames BEFORE this cut on the track's global axis (black on
  /// playback/export). Track list order stays the single source of cut
  /// sequence — a gap is an attribute of the boundary, so overlap is
  /// unrepresentable and reorders need no renumbering.
  final int leadingGapFrames;

  final CanvasSize canvasSize;
  final CutMetadata metadata;
  final CutCamera camera;

  /// The drawing guides (symmetry/perspective) this cut draws with.
  ///
  /// Cut-level because a guide is set up for the BACKGROUND being drawn:
  /// pinned to the viewport it would slide off the artwork on zoom, pinned
  /// to a layer it would need redrawing on every new cel. 겸용 cuts show one
  /// physical cel in two places, so their guides are kept identical — see
  /// the guide command's fan-out over [Project.linkRegistry].
  final CutGuides guides;

  // The V-track transform/fade left the cut (R4): the effects live on
  // [Track.transformTrack], keys on the GLOBAL frame axis — moving a cut
  // does not move them, and a legacy cut-level 'transform' entry is
  // lifted onto the track at load (track_transform_migration.dart).

  Cut copyWith({
    CutId? id,
    String? name,
    List<Layer>? layers,
    int? duration,
    CanvasSize? canvasSize,
    CutMetadata? metadata,
    int? leadingGapFrames,
    CutCamera? camera,
    CutGuides? guides,
  }) {
    return Cut(
      id: id ?? this.id,
      name: name ?? this.name,
      layers: layers ?? this.layers,
      duration: duration ?? this.duration,
      canvasSize: canvasSize ?? this.canvasSize,
      metadata: metadata ?? this.metadata,
      leadingGapFrames: leadingGapFrames ?? this.leadingGapFrames,
      camera: camera ?? this.camera,
      guides: guides ?? this.guides,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'layers': layers.map((layer) => layer.toJson()).toList(),
    'duration': duration,
    'canvasSize': canvasSize.toJson(),
    'metadata': metadata.toJson(),
    // Omitted at 0: legacy files load gap-free with no migration.
    if (leadingGapFrames > 0) 'leadingGap': leadingGapFrames,
    'camera': camera.toJson(),
    // Omitted while empty, the same way the gap is: every existing file
    // loads guide-free with no migration step.
    if (guides.isNotEmpty) 'guides': guides.toJson(),
  };

  factory Cut.fromJson(Map<String, dynamic> json) {
    final id = CutId.fromJson(json['id'] as Map<String, dynamic>);
    return Cut(
      id: id,
      name: json['name'] as String,
      // Older files predate the SE/instruction fixture rows; backfill them
      // on load so every cut meets the S1·S2 + CAM floors.
      layers: withEnsuredSectionLayers(
        id,
        (json['layers'] as List<dynamic>)
            .map((layer) => Layer.fromJson(layer as Map<String, dynamic>))
            .toList(),
      ),
      duration: json['duration'] as int,
      canvasSize: CanvasSize.fromJson(
        json['canvasSize'] as Map<String, dynamic>,
      ),
      metadata: json['metadata'] == null
          ? const CutMetadata.empty()
          : CutMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      leadingGapFrames: (json['leadingGap'] as int?) ?? 0,
      camera: json['camera'] == null
          ? null
          : CutCamera.fromJson(json['camera'] as Map<String, dynamic>),
      guides: json['guides'] == null
          ? null
          : CutGuides.fromJson(json['guides'] as Map<String, dynamic>),
      // Legacy 'transform' entries are read by Track.fromJson's lift, not
      // here — the cut model carries no transform any more (R4). The old
      // 'folders' table stays ignored the same way (no production data).
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cut &&
          other.id == id &&
          other.name == name &&
          listEquals(other.layers, layers) &&
          other.duration == duration &&
          other.canvasSize == canvasSize &&
          other.metadata == metadata &&
          other.leadingGapFrames == leadingGapFrames &&
          other.camera == camera &&
          other.guides == guides;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(layers),
    duration,
    canvasSize,
    metadata,
    leadingGapFrames,
    camera,
    guides,
  );

  @override
  String toString() =>
      'Cut(id: $id, name: $name, layers: $layers, duration: $duration, canvasSize: $canvasSize, metadata: $metadata, camera: $camera)';
}
