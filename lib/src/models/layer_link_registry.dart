import '../core/collection_equality.dart';
import 'brush_frame_key.dart';
import 'cut_id.dart';
import 'layer_id.dart';
import 'track_id.dart';

/// One use site of a linked layer: the (track, cut, layer) address of a
/// member. Linked members share the SAME FrameIds by construction (the
/// link-duplicate command copies them verbatim), so resolving a member's
/// cel to the canonical one only rewrites the cut/layer part of the key.
class LayerLinkMember {
  const LayerLinkMember({
    required this.trackId,
    required this.cutId,
    required this.layerId,
  });

  final TrackId trackId;
  final CutId cutId;
  final LayerId layerId;

  Map<String, dynamic> toJson() => {
    'trackId': trackId.toJson(),
    'cutId': cutId.toJson(),
    'layerId': layerId.toJson(),
  };

  factory LayerLinkMember.fromJson(Map<String, dynamic> json) {
    return LayerLinkMember(
      trackId: TrackId.fromJson(json['trackId'] as Map<String, dynamic>),
      cutId: CutId.fromJson(json['cutId'] as Map<String, dynamic>),
      layerId: LayerId.fromJson(json['layerId'] as Map<String, dynamic>),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerLinkMember &&
          other.trackId == trackId &&
          other.cutId == cutId &&
          other.layerId == layerId;

  @override
  int get hashCode => Object.hash(trackId, cutId, layerId);

  @override
  String toString() =>
      'LayerLinkMember(track: $trackId, cut: $cutId, layer: $layerId)';
}

/// One link group: layers that share ONE cel bank ("the picture exists
/// once; the members are windows onto it"). The FIRST member is the
/// CANONICAL one — its (cut, layer) address keys the physical cels in the
/// brush frame store and the .anicel archive; every other member's cel reads
/// and writes resolve to it.
class LayerLinkGroup {
  LayerLinkGroup({required this.id, required List<LayerLinkMember> members})
    : members = List.unmodifiable(members) {
    if (members.isEmpty) {
      throw ArgumentError.value(
        members,
        'members',
        'LayerLinkGroup.members must not be empty.',
      );
    }
  }

  final String id;

  /// Use sites, canonical first.
  final List<LayerLinkMember> members;

  LayerLinkMember get canonical => members.first;

  bool contains({required CutId cutId, required LayerId layerId}) {
    for (final member in members) {
      if (member.cutId == cutId && member.layerId == layerId) {
        return true;
      }
    }
    return false;
  }

  LayerLinkGroup copyWith({String? id, List<LayerLinkMember>? members}) {
    return LayerLinkGroup(id: id ?? this.id, members: members ?? this.members);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'members': members.map((member) => member.toJson()).toList(),
  };

  factory LayerLinkGroup.fromJson(Map<String, dynamic> json) {
    return LayerLinkGroup(
      id: json['id'] as String,
      members: [
        for (final member in json['members'] as List)
          LayerLinkMember.fromJson(member as Map<String, dynamic>),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerLinkGroup &&
          other.id == id &&
          listEquals(other.members, members);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(members));

  @override
  String toString() => 'LayerLinkGroup(id: $id, members: $members)';
}

/// The project's link table: every link group in the film. Lives on the
/// Project model (serialized in project.json) and is pushed into the
/// brush frame store as its canonical-key resolver — cel pixels stay ONE
/// physical entity per group, which is what makes drift impossible and
/// lets revision-based cache validation work unchanged.
class LayerLinkRegistry {
  LayerLinkRegistry({List<LayerLinkGroup> groups = const []})
    : groups = List.unmodifiable(groups);

  static final LayerLinkRegistry empty = LayerLinkRegistry();

  final List<LayerLinkGroup> groups;

  bool get isEmpty => groups.isEmpty;

  bool get isNotEmpty => groups.isNotEmpty;

  /// The group containing (cut, layer), or null when the layer is
  /// unlinked.
  LayerLinkGroup? groupOf({required CutId cutId, required LayerId layerId}) {
    for (final group in groups) {
      if (group.contains(cutId: cutId, layerId: layerId)) {
        return group;
      }
    }
    return null;
  }

  /// The canonical member for (cut, layer): itself when unlinked,
  /// otherwise its group's first member.
  LayerLinkMember canonicalOf({
    required TrackId trackId,
    required CutId cutId,
    required LayerId layerId,
  }) {
    return groupOf(cutId: cutId, layerId: layerId)?.canonical ??
        LayerLinkMember(trackId: trackId, cutId: cutId, layerId: layerId);
  }

  /// How many use sites share (cut, layer)'s pictures — 1 when unlinked
  /// (the link badge's "N곳에서 사용 중" count).
  int useCountOf({required CutId cutId, required LayerId layerId}) {
    return groupOf(cutId: cutId, layerId: layerId)?.members.length ?? 1;
  }

  /// The CANONICAL cel key for [key]: itself when the layer is unlinked
  /// or already canonical, otherwise the same frame under the group's
  /// canonical (track, cut, layer). Linked members share FrameIds by
  /// construction, so only the address part rewrites. Idempotent —
  /// resolving a canonical key returns it unchanged.
  BrushFrameKey canonicalCelKey(BrushFrameKey key) {
    final group = groupOf(cutId: key.cutId, layerId: key.layerId);
    if (group == null) {
      return key;
    }
    final canonical = group.canonical;
    if (canonical.cutId == key.cutId && canonical.layerId == key.layerId) {
      return key;
    }
    return BrushFrameKey(
      projectId: key.projectId,
      trackId: canonical.trackId,
      cutId: canonical.cutId,
      layerId: canonical.layerId,
      frameId: key.frameId,
    );
  }

  LayerLinkRegistry copyWith({List<LayerLinkGroup>? groups}) {
    return LayerLinkRegistry(groups: groups ?? this.groups);
  }

  Map<String, dynamic> toJson() => {
    'groups': groups.map((group) => group.toJson()).toList(),
  };

  factory LayerLinkRegistry.fromJson(Map<String, dynamic> json) {
    return LayerLinkRegistry(
      groups: [
        for (final group in json['groups'] as List? ?? const [])
          LayerLinkGroup.fromJson(group as Map<String, dynamic>),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerLinkRegistry && listEquals(other.groups, groups);

  @override
  int get hashCode => Object.hashAll(groups);

  @override
  String toString() => 'LayerLinkRegistry(groups: $groups)';
}
