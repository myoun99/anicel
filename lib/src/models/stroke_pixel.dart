import 'rgba_color.dart';

/// One pixel of a stroke as its dabs pile it up: the 16-bit plane a dab
/// reads what is under it from — a channel * 257 in [r], [g], [b], the
/// alpha * 65535 in [a] — and [bytes], what that plane shows everything
/// downstream.
///
/// 🚨The law and its reasons are written once, beside `qa_dab_store` in
/// qa_engine.c (ABI 40, 유저 2026-10-01 「a는 제안한대로 16비트?」). This is
/// the reference's half of it; the tile kernels hold the same two planes as
/// typed lists (`BrushDabTileBuffers`).
class StrokePixel {
  StrokePixel._({
    required this.bytes,
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  /// [bytes] widened onto the plane: every value reads back as exactly its
  /// byte (a byte * 257 / 257, a byte * 257 / 65535 = byte / 255).
  factory StrokePixel.widened(RgbaColor bytes) => StrokePixel._(
    bytes: bytes,
    r: bytes.r * 257,
    g: bytes.g * 257,
    b: bytes.b * 257,
    a: bytes.a * 257,
  );

  /// A straight-alpha result — channels in [0, 255], [alpha] in [0, 1] —
  /// rounded onto both planes from the same doubles: the view from the
  /// double, never from the plane, so a first dab over nothing lands
  /// exactly the byte it always did.
  ///
  /// 🚨THE VIEW HOLDS NO COLOUR UNDER A ZERO ALPHA (2026-10-25). A round
  /// tip's square reaches half a pixel past its rim (`RoundTipProfile`),
  /// and what a dab lays there rounds to an alpha of 0 while its channels
  /// stand — and the premultiplied copies downstream drop such a colour
  /// where a straight composite keeps it, so one stroke landed as two
  /// artworks (`stroke_promotion_parity_test`, measured). The plane keeps
  /// its colour: the dabs that pile on read it there. Both kernels round
  /// the view the same way (`qa_dab_store`).
  factory StrokePixel.rounded({
    required double red,
    required double green,
    required double blue,
    required double alpha,
  }) {
    final viewAlpha = (alpha * 255.0).round().clamp(0, 255);
    return StrokePixel._(
      bytes: viewAlpha == 0
          ? _clearView
          : RgbaColor(
              r: red.round().clamp(0, 255),
              g: green.round().clamp(0, 255),
              b: blue.round().clamp(0, 255),
              a: viewAlpha,
            ),
      r: (red * 257.0).round().clamp(0, 65535),
      g: (green * 257.0).round().clamp(0, 65535),
      b: (blue * 257.0).round().clamp(0, 65535),
      a: (alpha * 65535.0).round().clamp(0, 65535),
    );
  }

  /// A pixel of a second tip's plane: its [level], alpha * 65535, and no
  /// colour — what that tip's dabs pile over (ABI 60, `qa_dual_view_rows`).
  /// Its view is no one's: the stroke shows the two planes through its own.
  factory StrokePixel.level(int level) => StrokePixel._(
    bytes: _clearView,
    r: 0,
    g: 0,
    b: 0,
    a: level,
  );

  /// [destination] with only its alpha replaced by [alpha] in [0, 1],
  /// rounded onto both planes — what an erase leaves, and no colour in the
  /// view under a zero alpha ([StrokePixel.rounded]).
  factory StrokePixel.withAlpha(StrokePixel destination, double alpha) {
    final viewAlpha = (alpha * 255.0).round().clamp(0, 255);
    return StrokePixel._(
      bytes: viewAlpha == 0
          ? _clearView
          : destination.bytes.copyWith(a: viewAlpha),
      r: destination.r,
      g: destination.g,
      b: destination.b,
      a: (alpha * 65535.0).round().clamp(0, 65535),
    );
  }

  static final RgbaColor _clearView = RgbaColor(r: 0, g: 0, b: 0, a: 0);

  /// Nothing at all, on both planes.
  static final StrokePixel transparent = StrokePixel._(
    bytes: RgbaColor(r: 0, g: 0, b: 0, a: 0),
    r: 0,
    g: 0,
    b: 0,
    a: 0,
  );

  final RgbaColor bytes;
  final int r;
  final int g;
  final int b;
  final int a;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokePixel &&
          other.bytes == bytes &&
          other.r == r &&
          other.g == g &&
          other.b == b &&
          other.a == a;

  @override
  int get hashCode => Object.hash(bytes, r, g, b, a);

  @override
  String toString() => 'StrokePixel($bytes, wide: $r $g $b $a)';
}
