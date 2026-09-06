import 'tile_coord.dart';

/// A pixel-space rectangle. Coordinates may be NEGATIVE (pasteboard
/// space) — only the right > left / bottom > top ordering is enforced.
class DirtyRegion {
  DirtyRegion({
    required this.left,
    required this.top,
    required this.rightExclusive,
    required this.bottomExclusive,
  }) {
    _validateBounds(
      left: left,
      top: top,
      rightExclusive: rightExclusive,
      bottomExclusive: bottomExclusive,
    );
  }

  factory DirtyRegion.fromLTBR({
    required int left,
    required int top,
    required int rightExclusive,
    required int bottomExclusive,
  }) {
    return DirtyRegion(
      left: left,
      top: top,
      rightExclusive: rightExclusive,
      bottomExclusive: bottomExclusive,
    );
  }

  factory DirtyRegion.fromXYWH({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    _validatePositive(width, 'width');
    _validatePositive(height, 'height');
    return DirtyRegion(
      left: x,
      top: y,
      rightExclusive: x + width,
      bottomExclusive: y + height,
    );
  }

  final int left;
  final int top;
  final int rightExclusive;
  final int bottomExclusive;

  int get width => rightExclusive - left;

  int get height => bottomExclusive - top;

  DirtyRegion copyWith({
    int? left,
    int? top,
    int? rightExclusive,
    int? bottomExclusive,
  }) {
    return DirtyRegion(
      left: left ?? this.left,
      top: top ?? this.top,
      rightExclusive: rightExclusive ?? this.rightExclusive,
      bottomExclusive: bottomExclusive ?? this.bottomExclusive,
    );
  }

  bool containsPixel({required int x, required int y}) {
    return left <= x && x < rightExclusive && top <= y && y < bottomExclusive;
  }

  bool intersects(DirtyRegion other) {
    return left < other.rightExclusive &&
        rightExclusive > other.left &&
        top < other.bottomExclusive &&
        bottomExclusive > other.top;
  }

  /// The overlap with [other], or null when there is none — a DirtyRegion
  /// cannot be empty, so "nothing survives the clip" is the null.
  ///
  /// 🚨ONE clip for every landing that meets a wall: the commit's stamp
  /// blend and stroke-blend landing and BrushDabPlan against the
  /// pasteboard, the fill's settling bounds against the canvas (round 8
  /// of the audit, 2026-09-06). Each of them used to write the four
  /// max/min lines and the emptiness test by hand.
  DirtyRegion? intersection(DirtyRegion other) {
    final clipLeft = _max(left, other.left);
    final clipTop = _max(top, other.top);
    final clipRight = _min(rightExclusive, other.rightExclusive);
    final clipBottom = _min(bottomExclusive, other.bottomExclusive);
    if (clipRight <= clipLeft || clipBottom <= clipTop) {
      return null;
    }
    return DirtyRegion(
      left: clipLeft,
      top: clipTop,
      rightExclusive: clipRight,
      bottomExclusive: clipBottom,
    );
  }

  DirtyRegion union(DirtyRegion other) {
    return DirtyRegion(
      left: _min(left, other.left),
      top: _min(top, other.top),
      rightExclusive: _max(rightExclusive, other.rightExclusive),
      bottomExclusive: _max(bottomExclusive, other.bottomExclusive),
    );
  }

  Set<TileCoord> toTileCoords({required int tileSize}) {
    _validatePositive(tileSize, 'tileSize');
    return tileCoordsIn(tileRange(tileSize: tileSize)).toSet();
  }

  /// The inclusive tile box this region touches — [tileAxisSpan] on both
  /// axes; the floorDiv law for negative pasteboard coordinates lives
  /// there, once.
  TileRange tileRange({required int tileSize}) {
    final x = tileAxisSpan(
      start: left,
      endExclusive: rightExclusive,
      tileSize: tileSize,
    );
    final y = tileAxisSpan(
      start: top,
      endExclusive: bottomExclusive,
      tileSize: tileSize,
    );
    return (firstX: x.first, lastX: x.last, firstY: y.first, lastY: y.last);
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'rightExclusive': rightExclusive,
    'bottomExclusive': bottomExclusive,
  };

  factory DirtyRegion.fromJson(Map<String, dynamic> json) {
    return DirtyRegion(
      left: json['left'] as int,
      top: json['top'] as int,
      rightExclusive: json['rightExclusive'] as int,
      bottomExclusive: json['bottomExclusive'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirtyRegion &&
          other.left == left &&
          other.top == top &&
          other.rightExclusive == rightExclusive &&
          other.bottomExclusive == bottomExclusive;

  @override
  int get hashCode => Object.hash(left, top, rightExclusive, bottomExclusive);

  @override
  String toString() =>
      'DirtyRegion(left: $left, top: $top, '
      'rightExclusive: $rightExclusive, bottomExclusive: $bottomExclusive)';
}

void _validateBounds({
  required int left,
  required int top,
  required int rightExclusive,
  required int bottomExclusive,
}) {
  if (rightExclusive <= left) {
    throw ArgumentError.value(
      rightExclusive,
      'rightExclusive',
      'DirtyRegion.rightExclusive must be greater than left.',
    );
  }
  if (bottomExclusive <= top) {
    throw ArgumentError.value(
      bottomExclusive,
      'bottomExclusive',
      'DirtyRegion.bottomExclusive must be greater than top.',
    );
  }
}

void _validatePositive(int value, String fieldName) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'DirtyRegion.$fieldName must be greater than 0.',
    );
  }
}

int _min(int a, int b) => a < b ? a : b;

int _max(int a, int b) => a > b ? a : b;
