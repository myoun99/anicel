import 'dart:ui' show Offset;

import 'canvas_size.dart';
import 'text_cel_style.dart';

/// An SE row's ON-CANVAS NAME TAG (R5b, §6-z15): the アフレコ label —
/// white text in a red box — that names who is speaking over the picture,
/// positioned per SE row so one character's tag keeps its place across
/// every cut ("캐릭터마다 이름표 위치 일정").
///
/// It is a DISPLAY-TIME annotation, never baked into the composite: the
/// camera's precedent (the frame is not part of the picture) and the same
/// reason — the text comes from the SE frame's own data, so a rename must
/// show instantly without invalidating a single cached composite.
///
/// The row's EYE decides whether it shows and [Layer.muted] decides
/// whether the sound plays, so a main-line export can drop the tags and
/// keep the audio with one toggle.
class SeNameTag {
  const SeNameTag({required this.position, this.style = defaultStyle});

  /// Canvas coordinates; the style's alignment spreads the tag around it
  /// and the first line's top sits here (the text-cel anchor grammar).
  final Offset position;

  final TextCelStyle style;

  /// The アフレコ look: white bold text in the danger-red box, the same
  /// red the SE bars and cut strikethroughs already speak.
  static const TextCelStyle defaultStyle = TextCelStyle(
    fontSize: 34,
    bold: true,
    align: TextCelAlign.left,
    color: 0xFFFFFFFF,
    backgroundColor: 0xFFC95C5C,
  );

  SeNameTag copyWith({Offset? position, TextCelStyle? style}) => SeNameTag(
    position: position ?? this.position,
    style: style ?? this.style,
  );

  Map<String, dynamic> toJson() => {
    'position': [position.dx, position.dy],
    'style': style.toJson(),
  };

  factory SeNameTag.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as List<dynamic>?;
    return SeNameTag(
      position: position == null
          ? Offset.zero
          : Offset(
              (position[0] as num).toDouble(),
              (position[1] as num).toDouble(),
            ),
      style: json['style'] is Map<String, dynamic>
          ? TextCelStyle.fromJson(json['style'] as Map<String, dynamic>)
          : defaultStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeNameTag && other.position == position && other.style == style;

  @override
  int get hashCode => Object.hash(position, style);
}

/// Where an UNCONFIGURED row's tag sits: stacked up from the bottom-left,
/// one line per SE row, so S1·S2·S3 read as separate speakers instead of
/// piling on one spot. [rowIndex] is the row's place in the track's SE
/// list (0 = first row, sitting lowest).
Offset defaultSeNameTagPosition({
  required CanvasSize canvas,
  required int rowIndex,
}) {
  final line = SeNameTag.defaultStyle.fontSize * 1.6;
  final margin = canvas.height * 0.06;
  return Offset(
    canvas.width * 0.06,
    canvas.height - margin - line * (rowIndex + 1),
  );
}

/// The tag's line: the speaker in the box, the dialogue beside it
/// (`[タモツ] 대사내용`, the user's format). Either half alone stands on
/// its own — a lone speaker needs no brackets, the box already frames it.
/// Empty on both sides means the block carries no writing yet, so the row
/// shows nothing at all rather than an empty red box.
String seNameTagText({required String? seName, required String? dialogue}) {
  final name = seName?.trim() ?? '';
  final line = dialogue?.trim() ?? '';
  if (name.isEmpty) {
    return line;
  }
  if (line.isEmpty) {
    return name;
  }
  return '[$name] $line';
}
