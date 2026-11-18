import '../core/collection_equality.dart';
import '../core/frozen_collections.dart';
import 'brush_settings.dart';
import 'stroke_id.dart';
import 'stroke_point.dart';

class Stroke {
  Stroke({
    required this.id,
    required List<StrokePoint> points,
    required this.brushSettings,
  }) : points = frozenList(points);

  final StrokeId id;
  final List<StrokePoint> points;
  final BrushSettings brushSettings;

  Stroke copyWith({
    StrokeId? id,
    List<StrokePoint>? points,
    BrushSettings? brushSettings,
  }) {
    return Stroke(
      id: id ?? this.id,
      points: points ?? this.points,
      brushSettings: brushSettings ?? this.brushSettings,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'points': points.map((point) => point.toJson()).toList(),
    'brushSettings': brushSettings.toJson(),
  };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: StrokeId.fromJson(json['id'] as Map<String, dynamic>),
      points: (json['points'] as List<dynamic>)
          .map((point) => StrokePoint.fromJson(point as Map<String, dynamic>))
          .toList(),
      brushSettings: BrushSettings.fromJson(
        json['brushSettings'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stroke &&
          other.id == id &&
          listEquals(other.points, points) &&
          other.brushSettings == brushSettings;

  @override
  int get hashCode => Object.hash(id, Object.hashAll(points), brushSettings);

  @override
  String toString() =>
      'Stroke(id: $id, points: $points, brushSettings: $brushSettings)';
}
