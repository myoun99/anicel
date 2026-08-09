import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'canvas_size.dart';
import 'property_track.dart';
import 'text_cel_style.dart';
import 'transform_track.dart' show lerpArgb, lerpBoolHold, lerpDouble;

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
///
/// (The class itself is [SeNameTag], below its keyable members.)

/// The name tag's KEYABLE members (R5 #7) — the AE-grade half.
///
/// Static slot plus track, exactly as `EffectParameter` does it: the styles
/// on [SeNameTag] carry the value while a member is unkeyed, and a track
/// here overrides it once one exists. Keying is additive — nothing about an
/// untouched tag changes, and its JSON does not grow a field.
///
/// Seven members, in the user's own grouping: size, tracking and bold are
/// SHARED by both runs (one lane drives the name and the line together);
/// the three inks and the dialogue switch are per-run.
class SeNameTagTrack {
  SeNameTagTrack({
    PropertyTrack<double>? fontSize,
    PropertyTrack<double>? letterSpacing,
    PropertyTrack<bool>? bold,
    PropertyTrack<int>? nameInk,
    PropertyTrack<int>? boxColor,
    PropertyTrack<int>? lineInk,
    PropertyTrack<bool>? showLine,
  }) : fontSize = fontSize ?? PropertyTrack<double>.empty(),
       letterSpacing = letterSpacing ?? PropertyTrack<double>.empty(),
       bold = bold ?? PropertyTrack<bool>.empty(),
       nameInk = nameInk ?? PropertyTrack<int>.empty(),
       boxColor = boxColor ?? PropertyTrack<int>.empty(),
       lineInk = lineInk ?? PropertyTrack<int>.empty(),
       showLine = showLine ?? PropertyTrack<bool>.empty();

  factory SeNameTagTrack.empty() => SeNameTagTrack();

  final PropertyTrack<double> fontSize;
  final PropertyTrack<double> letterSpacing;
  final PropertyTrack<bool> bold;
  final PropertyTrack<int> nameInk;
  final PropertyTrack<int> boxColor;
  final PropertyTrack<int> lineInk;
  final PropertyTrack<bool> showLine;

  bool get isEmpty =>
      fontSize.isEmpty &&
      letterSpacing.isEmpty &&
      bold.isEmpty &&
      nameInk.isEmpty &&
      boxColor.isEmpty &&
      lineInk.isEmpty &&
      showLine.isEmpty;

  /// Every frame any member keys — the group header's key union, the same
  /// summary the Transform header shows.
  Set<int> get keyedFrames => {
    ...fontSize.keys.keys,
    ...letterSpacing.keys.keys,
    ...bold.keys.keys,
    ...nameInk.keys.keys,
    ...boxColor.keys.keys,
    ...lineInk.keys.keys,
    ...showLine.keys.keys,
  };

  SeNameTagTrack copyWith({
    PropertyTrack<double>? fontSize,
    PropertyTrack<double>? letterSpacing,
    PropertyTrack<bool>? bold,
    PropertyTrack<int>? nameInk,
    PropertyTrack<int>? boxColor,
    PropertyTrack<int>? lineInk,
    PropertyTrack<bool>? showLine,
  }) => SeNameTagTrack(
    fontSize: fontSize ?? this.fontSize,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    bold: bold ?? this.bold,
    nameInk: nameInk ?? this.nameInk,
    boxColor: boxColor ?? this.boxColor,
    lineInk: lineInk ?? this.lineInk,
    showLine: showLine ?? this.showLine,
  );

  Map<String, dynamic> toJson() => {
    if (fontSize.isNotEmpty) 'fontSize': fontSize.toJson((v) => v),
    if (letterSpacing.isNotEmpty)
      'letterSpacing': letterSpacing.toJson((v) => v),
    if (bold.isNotEmpty) 'bold': bold.toJson((v) => v),
    if (nameInk.isNotEmpty) 'nameInk': nameInk.toJson((v) => v),
    if (boxColor.isNotEmpty) 'boxColor': boxColor.toJson((v) => v),
    if (lineInk.isNotEmpty) 'lineInk': lineInk.toJson((v) => v),
    if (showLine.isNotEmpty) 'showLine': showLine.toJson((v) => v),
  };

  factory SeNameTagTrack.fromJson(Map<String, dynamic> json) {
    PropertyTrack<double> number(String key) => PropertyTrack.fromJson(
      json[key] as List?,
      (v) => (v as num).toDouble(),
    );
    PropertyTrack<int> argb(String key) =>
        PropertyTrack.fromJson(json[key] as List?, (v) => (v as num).toInt());
    PropertyTrack<bool> flag(String key) =>
        PropertyTrack.fromJson(json[key] as List?, (v) => v as bool);
    return SeNameTagTrack(
      fontSize: number('fontSize'),
      letterSpacing: number('letterSpacing'),
      bold: flag('bold'),
      nameInk: argb('nameInk'),
      boxColor: argb('boxColor'),
      lineInk: argb('lineInk'),
      showLine: flag('showLine'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeNameTagTrack &&
          other.fontSize == fontSize &&
          other.letterSpacing == letterSpacing &&
          other.bold == bold &&
          other.nameInk == nameInk &&
          other.boxColor == boxColor &&
          other.lineInk == lineInk &&
          other.showLine == showLine;

  @override
  int get hashCode => Object.hash(
    fontSize,
    letterSpacing,
    bold,
    nameInk,
    boxColor,
    lineInk,
    showLine,
  );
}

class SeNameTag {
  const SeNameTag({
    this.position,
    this.style = defaultStyle,
    this.lineStyle = defaultLineStyle,
    this.showLine = true,
    this.track,
  });

  /// The keyable members (R5 #7). Null while the tag has never been keyed,
  /// which is every tag until someone does — so the common one stays as
  /// cheap as it was.
  final SeNameTagTrack? track;

  /// This tag as it stands at [frameIndex]: the styles with every KEYED
  /// member substituted in.
  ///
  /// ONE function, so the plan, the painter and the lane value column
  /// cannot disagree about what a frame looks like — the trap the pose
  /// resolver exists to avoid on the transform side.
  SeNameTag resolveAt(int frameIndex) {
    final keys = track;
    if (keys == null || keys.isEmpty) {
      return this;
    }
    double size(double fallback) => keys.fontSize.resolveAt(
      frameIndex: frameIndex,
      orElse: () => fallback,
      lerp: lerpDouble,
    );
    double tracking(double fallback) => keys.letterSpacing.resolveAt(
      frameIndex: frameIndex,
      orElse: () => fallback,
      lerp: lerpDouble,
    );
    bool weight(bool fallback) => keys.bold.resolveAt(
      frameIndex: frameIndex,
      orElse: () => fallback,
      lerp: lerpBoolHold,
    );
    int ink(PropertyTrack<int> lane, int fallback) => lane.resolveAt(
      frameIndex: frameIndex,
      orElse: () => fallback,
      lerp: lerpArgb,
    );
    return SeNameTag(
      position: position,
      style: style.copyWith(
        fontSize: size(style.fontSize),
        letterSpacing: tracking(style.letterSpacing),
        bold: weight(style.bold),
        color: ink(keys.nameInk, style.color),
        backgroundColor: keys.boxColor.isEmpty
            ? style.backgroundColor
            : ink(keys.boxColor, style.backgroundColor ?? 0),
      ),
      lineStyle: lineStyle.copyWith(
        // Size, tracking and bold are ONE lane driving both runs (the
        // user's grouping), so the line follows the name rather than
        // carrying a second set nobody asked to key.
        fontSize: size(lineStyle.fontSize),
        letterSpacing: tracking(lineStyle.letterSpacing),
        bold: weight(lineStyle.bold),
        color: ink(keys.lineInk, lineStyle.color),
      ),
      showLine: keys.showLine.resolveAt(
        frameIndex: frameIndex,
        orElse: () => showLine,
        lerp: lerpBoolHold,
      ),
      track: keys,
    );
  }

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
    SeNameTagTrack? track,
  }) => SeNameTag(
    position: identical(position, _sentinel)
        ? this.position
        : position as Offset?,
    style: style ?? this.style,
    lineStyle: lineStyle ?? this.lineStyle,
    showLine: showLine ?? this.showLine,
    track: track ?? this.track,
  );

  Map<String, dynamic> toJson() => {
    if (position != null) 'position': [position!.dx, position!.dy],
    'style': style.toJson(),
    'lineStyle': lineStyle.toJson(),
    if (!showLine) 'showLine': false,
    // Written only once a member is keyed, so an untouched tag's JSON is
    // byte-identical to what it was before keying existed.
    if (track != null && !track!.isEmpty) 'keys': track!.toJson(),
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
      track: json['keys'] is Map<String, dynamic>
          ? SeNameTagTrack.fromJson(json['keys'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeNameTag &&
          other.position == position &&
          other.style == style &&
          other.lineStyle == lineStyle &&
          other.showLine == showLine &&
          other.track == track;

  @override
  int get hashCode => Object.hash(position, style, lineStyle, showLine, track);

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
