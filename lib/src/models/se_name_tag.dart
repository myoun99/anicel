import 'dart:math' as math;
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
  const SeNameTag({
    this.position,
    this.style = defaultStyle,
    this.lineStyle = defaultLineStyle,
    this.showLine = true,
  });

  /// Canvas coordinates — the exact geometric CENTRE of the name box
  /// (R5 #7, the user's rule).
  ///
  /// The centre of the box, not of the whole tag: the dialogue hangs to
  /// the box's right and must not move it. Anchoring on the pair's centre
  /// would make turning the dialogue off slide the name somewhere else,
  /// which is precisely the thing the user rejected.
  ///
  /// NULL keeps the row on the stacked default — which is per CUT (the
  /// shot's geometry) and per row, so a style-only edit must not freeze
  /// today's default into absolute pixels that then miss a differently
  /// sized cut.
  final Offset? position;

  /// The NAME run: the white-on-red box.
  final TextCelStyle style;

  /// The DIALOGUE run, hanging to the box's right — its own ink, so the
  /// line can be read against the picture while the name stays in its box.
  final TextCelStyle lineStyle;

  /// Whether the dialogue shows at all (R5 #7: a keyable member, because a
  /// name tag with no line is the ordinary アフレコ case).
  final bool showLine;

  /// The アフレコ look: white bold text in the danger-red box, the same
  /// red the SE bars and cut strikethroughs already speak.
  static const TextCelStyle defaultStyle = TextCelStyle(
    fontSize: 34,
    bold: true,
    align: TextCelAlign.left,
    color: 0xFFFFFFFF,
    backgroundColor: 0xFFC95C5C,
  );

  /// The line reads on the picture, so it takes an outline instead of a
  /// box — a second filled box beside the first would read as two names.
  static const TextCelStyle defaultLineStyle = TextCelStyle(
    fontSize: 34,
    bold: true,
    align: TextCelAlign.left,
    color: 0xFFFFFFFF,
    outlineColor: 0xFF202020,
    outlineWidth: 3,
  );

  SeNameTag copyWith({
    Object? position = _sentinel,
    TextCelStyle? style,
    TextCelStyle? lineStyle,
    bool? showLine,
  }) => SeNameTag(
    position: identical(position, _sentinel)
        ? this.position
        : position as Offset?,
    style: style ?? this.style,
    lineStyle: lineStyle ?? this.lineStyle,
    showLine: showLine ?? this.showLine,
  );

  Map<String, dynamic> toJson() => {
    if (position != null) 'position': [position!.dx, position!.dy],
    'style': style.toJson(),
    'lineStyle': lineStyle.toJson(),
    if (!showLine) 'showLine': false,
  };

  factory SeNameTag.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as List<dynamic>?;
    return SeNameTag(
      position: position == null
          ? null
          : Offset(
              (position[0] as num).toDouble(),
              (position[1] as num).toDouble(),
            ),
      style: json['style'] is Map<String, dynamic>
          ? TextCelStyle.fromJson(json['style'] as Map<String, dynamic>)
          : defaultStyle,
      lineStyle: json['lineStyle'] is Map<String, dynamic>
          ? TextCelStyle.fromJson(json['lineStyle'] as Map<String, dynamic>)
          : defaultLineStyle,
      showLine: json['showLine'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeNameTag &&
          other.position == position &&
          other.style == style &&
          other.lineStyle == lineStyle &&
          other.showLine == showLine;

  @override
  int get hashCode => Object.hash(position, style, lineStyle, showLine);

  static const Object _sentinel = Object();
}

/// The camera's rect in CANVAS coordinates at the resting pose (centered,
/// zoom 1) — the SHOT, which is what every framed surface shows. The
/// canvas is bigger than the frame by default (2340×1654 paper against a
/// 1920×1080 camera), so anything placed relative to the canvas can sit
/// perfectly visible while editing and be clipped away in playback's
/// camera view and in the delivered video.
({double left, double top, double width, double height}) shotRectIn({
  required CanvasSize canvas,
  required CanvasSize cameraFrame,
}) {
  final width = math.min(cameraFrame.width, canvas.width).toDouble();
  final height = math.min(cameraFrame.height, canvas.height).toDouble();
  return (
    left: (canvas.width - width) / 2,
    top: (canvas.height - height) / 2,
    width: width,
    height: height,
  );
}

/// Where an UNCONFIGURED row's tag sits: stacked up from the SHOT's
/// bottom-left, one line per SE row, so S1·S2·S3 read as separate
/// speakers instead of piling on one spot — and so the default actually
/// reaches the framed surfaces.
///
/// [rowOffset] shifts the stack for rows on the tracks BELOW this one, so
/// two covered tracks in the multitrack stack never land on the same
/// spot.
Offset defaultSeNameTagPosition({
  required CanvasSize canvas,
  required CanvasSize cameraFrame,
  required int rowIndex,
  int rowOffset = 0,
}) {
  final shot = shotRectIn(canvas: canvas, cameraFrame: cameraFrame);
  // The painted box is the text line plus the background pad on each side
  // (TextCelStyle's line height + 2× box pad ≈ 1.77em), so a tighter
  // pitch fuses consecutive rows' red boxes into one stepped blob.
  final line = SeNameTag.defaultStyle.fontSize * seNameTagStackPitchFactor;
  final margin = shot.height * 0.06;
  return Offset(
    shot.left + shot.width * 0.06,
    shot.top + shot.height - margin - line * (rowIndex + rowOffset + 1),
  );
}

/// The stacked default's pitch in ems — above the painted box height so
/// neighbouring rows keep a visible gap.
const double seNameTagStackPitchFactor = 2.0;

/// The width a tag may occupy before it shrinks to fit: the shot's width
/// minus the same 6% margin on both sides. Without a budget a long line
/// runs off the picture and is silently cropped.
double seNameTagWidthBudget({
  required CanvasSize canvas,
  required CanvasSize cameraFrame,
}) {
  final shot = shotRectIn(canvas: canvas, cameraFrame: cameraFrame);
  return shot.width * 0.88;
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
