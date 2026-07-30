import '../core/collection_equality.dart';
import 'frame_id.dart';
import '../core/copy_with_sentinel.dart';
import 'stroke.dart';
import 'text_cel_style.dart';

/// One DRAWING in a layer's cel bank.
///
/// Memos are deliberately NOT here: a frame is the picture, and the same
/// picture may be exposed twice in a cut and shared across linked cuts, so
/// a memo hanging off it would be shared by everything that draws it. They
/// live on the exposure instead ([TimelineExposure.memo]).
class Frame {
  Frame({
    required this.id,
    required this.duration,
    required List<Stroke> strokes,
    this.name,
    this.seName,
    this.textContent,
  }) : strokes = List.unmodifiable(strokes);

  final FrameId id;
  final int duration;
  final List<Stroke> strokes;
  final String? name;

  /// SE rows only: the speaker/effect name shown in the accent box at the
  /// block start. [name] stays the dialogue there (it predates this field,
  /// so legacy SE labels keep reading as dialogue).
  final String? seName;

  /// Text rows only (R5, §6-s): the cel's PICTURE as parameters — the
  /// baked raster in the brush store is a projection re-baked on edit.
  /// Being a Frame field it shares across linked cuts and rides paste/
  /// duplicate exactly like the drawing it stands for.
  final TextCelContent? textContent;

  Frame copyWith({
    FrameId? id,
    int? duration,
    List<Stroke>? strokes,
    Object? name = copyWithSentinel,
    Object? seName = copyWithSentinel,
    Object? textContent = copyWithSentinel,
  }) {
    return Frame(
      id: id ?? this.id,
      duration: duration ?? this.duration,
      strokes: strokes ?? this.strokes,
      name: identical(name, copyWithSentinel) ? this.name : name as String?,
      seName: identical(seName, copyWithSentinel)
          ? this.seName
          : seName as String?,
      textContent: identical(textContent, copyWithSentinel)
          ? this.textContent
          : textContent as TextCelContent?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'duration': duration,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    if (name != null) 'name': name,
    if (seName != null) 'seName': seName,
    if (textContent != null) 'textContent': textContent!.toJson(),
  };

  factory Frame.fromJson(Map<String, dynamic> json) {
    return Frame(
      id: FrameId.fromJson(json['id'] as Map<String, dynamic>),
      duration: json['duration'] as int,
      strokes: (json['strokes'] as List<dynamic>)
          .map((stroke) => Stroke.fromJson(stroke as Map<String, dynamic>))
          .toList(),
      name: json['name'] as String?,
      seName: json['seName'] as String?,
      textContent: json['textContent'] is Map<String, dynamic>
          ? TextCelContent.fromJson(json['textContent'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Frame &&
          other.id == id &&
          other.duration == duration &&
          other.name == name &&
          other.seName == seName &&
          other.textContent == textContent &&
          listEquals(other.strokes, strokes);

  @override
  int get hashCode => Object.hash(
    id,
    duration,
    name,
    seName,
    textContent,
    Object.hashAll(strokes),
  );

  @override
  String toString() =>
      'Frame(id: $id, duration: $duration, name: $name, '
      'seName: $seName, textContent: $textContent, strokes: $strokes)';
}
