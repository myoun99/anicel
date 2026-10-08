/// What of the shape the shape tool lays (유저 답 I-69-Q7 메모, 2026-10-08:
/// 「새 도형도구에서도 선/채움을 고르는 줄을 넣음」).
enum ShapePart {
  /// 「선」 — the shape's line: its outline, or the segment a line is.
  line,

  /// 「채움」 — the shape's inside, as one area. 🚨It has nothing to do with
  /// the line's type (유저 답 I-69-Q9: 「채움은 타입과 무관하다」): no brush
  /// is read, and the result is the fill tool's shape fill, by its code.
  fill,
}

/// What lays the shape tool's line.
///
/// 🗣️I-69 (유저 2026-10-04): 「설정쪽에서 애초에 큰 타입으로서 브러시/자체?
/// 자체는 이름 뭘로할지 고민. 일반으로할까?」 → 답 I-69-Q1 (2026-10-08):
/// 「일반」.
enum ShapeLineType {
  /// The brush in hand, as it is: its size, its opacity, its texture.
  brush,

  /// 「일반」 — a plain line of the tool's own. 🚨It has NOTHING to do with
  /// the brush (유저 답 I-69-Q8: 「일반은 브러시랑 전혀 관계없는 독립적인것임」):
  /// every value it draws by is one of [ShapeToolOptions]' own.
  plain,
}

/// How a plain line turns a corner and ends (유저 답 I-69-Q8: 「둘 다 (설정에
/// 「모서리: 각지게 | 둥글게」)」).
enum ShapeCorners {
  /// A square's corners are corners, and a line's ends are cut square.
  sharp,

  /// Corners and ends are rounded by half the line's width.
  round,
}

/// The shape tool's own settings — one value, so the tool state carries one
/// field for them.
///
/// ⛔Not the composite mode: that is the tool state's, beside the fill's and
/// the stamp's (「블렌드모드 선택은 툴에 산다」), and whatever the tool lays
/// shares it (유저 답 I-69-Q2).
class ShapeToolOptions {
  const ShapeToolOptions({
    this.part = ShapePart.line,
    this.type = ShapeLineType.brush,
    this.size = defaultSize,
    this.opacity = 1,
    this.antiAlias = true,
    this.corners = ShapeCorners.sharp,
    this.ratioLock = false,
  });

  /// The tool's own line width before anyone has set one, in canvas pixels.
  static const double defaultSize = 4;

  final ShapePart part;

  /// What lays the line — read only where [part] is the line.
  final ShapeLineType type;

  /// 🚨THE TOOL'S OWN, each of them: what it draws by wherever it does not
  /// draw with the brush ([drawsWithTheBrush]). The line of the brush type
  /// reads the brush's size, opacity and edge instead, and none of these.
  ///
  /// [size] is the plain line's width in canvas pixels and [corners] how it
  /// turns; [opacity] (0 to 1) and [antiAlias] are the plain line's and the
  /// fill's alike.
  final double size;
  final double opacity;
  final bool antiAlias;
  final ShapeCorners corners;

  /// 「비율 고정」: a rectangle is a square, an ellipse a circle, and a line
  /// keeps to steps of 45° (유저 답 I-69-Q5: 「설정 스위치 + Shift」 — the
  /// modifier held turns this the other way round for as long as it is).
  final bool ratioLock;

  /// Whether what the tool lays is drawn with the brush in hand: a line, of
  /// the brush type. Everything else is the tool's own.
  bool get drawsWithTheBrush =>
      part == ShapePart.line && type == ShapeLineType.brush;

  ShapeToolOptions copyWith({
    ShapePart? part,
    ShapeLineType? type,
    double? size,
    double? opacity,
    bool? antiAlias,
    ShapeCorners? corners,
    bool? ratioLock,
  }) => ShapeToolOptions(
    part: part ?? this.part,
    type: type ?? this.type,
    size: size ?? this.size,
    opacity: opacity ?? this.opacity,
    antiAlias: antiAlias ?? this.antiAlias,
    corners: corners ?? this.corners,
    ratioLock: ratioLock ?? this.ratioLock,
  );

  Map<String, Object?> toJson() => {
    'part': part.name,
    'type': type.name,
    'size': size,
    'opacity': opacity,
    'antiAlias': antiAlias,
    'corners': corners.name,
    'ratioLock': ratioLock,
  };

  /// The options [json] holds, or null when it holds none. 🚨Every part
  /// answers for itself (the tool choice's law, F-123): a name this build
  /// does not know, a width that is not one — that part keeps its default
  /// and the rest still lands.
  static ShapeToolOptions? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    const fresh = ShapeToolOptions();
    final size = json['size'];
    final opacity = json['opacity'];
    final antiAlias = json['antiAlias'];
    final ratioLock = json['ratioLock'];
    return ShapeToolOptions(
      part: ShapePart.values.asNameMap()[json['part']] ?? fresh.part,
      type: ShapeLineType.values.asNameMap()[json['type']] ?? fresh.type,
      size: size is num && size > 0 && size.isFinite
          ? size.toDouble()
          : fresh.size,
      opacity: opacity is num && opacity >= 0 && opacity <= 1
          ? opacity.toDouble()
          : fresh.opacity,
      antiAlias: antiAlias is bool ? antiAlias : fresh.antiAlias,
      corners:
          ShapeCorners.values.asNameMap()[json['corners']] ?? fresh.corners,
      ratioLock: ratioLock is bool ? ratioLock : fresh.ratioLock,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShapeToolOptions &&
          other.part == part &&
          other.type == type &&
          other.size == size &&
          other.opacity == opacity &&
          other.antiAlias == antiAlias &&
          other.corners == corners &&
          other.ratioLock == ratioLock;

  @override
  int get hashCode =>
      Object.hash(part, type, size, opacity, antiAlias, corners, ratioLock);
}
