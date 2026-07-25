import 'string_id.dart';

final class BrushGroupId extends StringId {
  const BrushGroupId(super.value);

  factory BrushGroupId.fromJson(Map<String, dynamic> json) =>
      BrushGroupId(json['value'] as String);
}
