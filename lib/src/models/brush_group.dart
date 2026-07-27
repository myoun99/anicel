import 'brush_group_icon.dart';
import 'brush_group_id.dart';

/// A collapsible section of the brush library (Clip Studio's sub-tool group).
///
/// A group is a FIRST-CLASS entity rather than a name repeated on each
/// member: presets point at one by [id], so renaming never rewrites the
/// members, a group can exist while it is still empty, and the display order
/// is the group list's own order instead of something derived from where
/// members happen to sit.
///
/// Groups are deliberately FLAT — one level, no nesting (a narrow dock reads
/// better without a tree). A later `parentId` field could add depth without
/// breaking the saved file.
class BrushGroup {
  const BrushGroup({
    required this.id,
    required this.name,
    this.icon,
    this.collapsed = false,
  });

  final BrushGroupId id;
  final String name;

  /// The tab's chosen face, or null to keep deriving one from the group's
  /// first brush. Null is the default because a tab that looks like its
  /// contents beats one that looks like whatever icon got picked — choosing
  /// is for when that guess reads wrong.
  final BrushGroupIcon? icon;

  /// Whether the section is folded shut in the panel. Persisted with the
  /// library: a pack the user collapsed stays collapsed across restarts.
  final bool collapsed;

  BrushGroup copyWith({
    BrushGroupId? id,
    String? name,
    // Clearing the icon has to WRITE null, which `?? this` cannot say.
    bool clearIcon = false,
    BrushGroupIcon? icon,
    bool? collapsed,
  }) {
    return BrushGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: clearIcon ? null : (icon ?? this.icon),
      collapsed: collapsed ?? this.collapsed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    if (icon != null) 'icon': icon!.name,
    if (collapsed) 'collapsed': true,
  };

  factory BrushGroup.fromJson(Map<String, dynamic> json) => BrushGroup(
    id: BrushGroupId.fromJson(json['id'] as Map<String, dynamic>),
    name: json['name'] as String,
    icon: BrushGroupIcon.byName(json['icon'] as String?),
    collapsed: json['collapsed'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushGroup &&
          other.id == id &&
          other.name == name &&
          other.icon == icon &&
          other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(id, name, icon, collapsed);

  @override
  String toString() =>
      'BrushGroup(id: $id, name: $name, icon: $icon, collapsed: $collapsed)';
}

/// The stable group id an imported brush file lands in, derived from the
/// file's base name. Re-importing the same file therefore finds its own
/// group again and replaces its contents instead of piling up duplicates.
///
/// Shared by the importer and by the legacy-library migration, which rebuilds
/// group entities from the group NAMES older files stored on each preset.
BrushGroupId importedBrushGroupId(String sourceName) =>
    BrushGroupId('imported-$sourceName');
