import 'brush_group_id.dart';
import 'brush_preset_id.dart';
import 'brush_settings.dart';

class BrushPreset {
  const BrushPreset({
    required this.id,
    required this.name,
    required this.settings,
    this.groupId,
  });

  final BrushPresetId id;
  final String name;
  final BrushSettings settings;

  /// The library group this preset sits in, by id (see `BrushGroup`).
  /// `null` — and, defensively, an id no group carries — means the preset
  /// belongs to the library's headerless root section.
  final BrushGroupId? groupId;

  static const Object _groupUnset = Object();

  /// [groupId] accepts an explicit `null` to clear the group (move the preset
  /// back to the root section); omitting it keeps the current group.
  BrushPreset copyWith({
    BrushPresetId? id,
    String? name,
    BrushSettings? settings,
    Object? groupId = _groupUnset,
  }) {
    return BrushPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      settings: settings ?? this.settings,
      groupId: identical(groupId, _groupUnset)
          ? this.groupId
          : groupId as BrushGroupId?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'settings': settings.toJson(),
    if (groupId != null) 'groupId': groupId!.toJson(),
  };

  factory BrushPreset.fromJson(Map<String, dynamic> json) {
    return BrushPreset(
      id: BrushPresetId.fromJson(json['id'] as Map<String, dynamic>),
      name: json['name'] as String,
      settings: BrushSettings.fromJson(
        json['settings'] as Map<String, dynamic>,
      ),
      groupId: json['groupId'] == null
          ? null
          : BrushGroupId.fromJson(json['groupId'] as Map<String, dynamic>),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushPreset &&
          other.id == id &&
          other.name == name &&
          other.settings == settings &&
          other.groupId == groupId;

  @override
  int get hashCode => Object.hash(id, name, settings, groupId);

  @override
  String toString() =>
      'BrushPreset(id: $id, name: $name, groupId: $groupId, '
      'settings: $settings)';
}
