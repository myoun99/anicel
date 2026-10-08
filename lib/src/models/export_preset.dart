import 'export_spec.dart';
import 'string_id.dart';

final class ExportPresetId extends StringId {
  const ExportPresetId(super.value);

  factory ExportPresetId.fromJson(Map<String, dynamic> json) =>
      ExportPresetId(json['value'] as String);
}

/// A named export configuration (창 내 프리셋, 탭별): AUTO RULES only —
/// per-cut manual exceptions never enter a preset (they live on the
/// project as `ExportProjectOverrides`).
class ExportPreset {
  const ExportPreset({required this.id, required this.name, required this.spec});

  final ExportPresetId id;
  final String name;
  final ExportTabSpec spec;

  ExportTab get tab => spec.tab;

  ExportPreset copyWith({ExportPresetId? id, String? name, ExportTabSpec? spec}) =>
      ExportPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        spec: spec ?? this.spec,
      );

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'tab': tab.jsonValue,
    'spec': spec.toJson(),
  };

  /// The preset [json] holds, or null when it was saved for a tab that is
  /// one no longer ([ExportTab.fromJsonOrNull]).
  static ExportPreset? fromJson(Map<String, dynamic> json) {
    final tab = ExportTab.fromJsonOrNull(json['tab']);
    if (tab == null) {
      return null;
    }
    return ExportPreset(
      id: ExportPresetId.fromJson(json['id'] as Map<String, dynamic>),
      name: json['name'] as String,
      spec: exportTabSpecFromJson(
        tab,
        (json['spec'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportPreset &&
          other.id == id &&
          other.name == name &&
          other.spec == spec;

  @override
  int get hashCode => Object.hash(id, name, spec);

  @override
  String toString() => 'ExportPreset(id: $id, name: $name, tab: $tab)';
}
