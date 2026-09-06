import '../core/argb_channels.dart';

class RgbaColor {
  RgbaColor({
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  }) {
    _validateComponent(r, 'r');
    _validateComponent(g, 'g');
    _validateComponent(b, 'b');
    _validateComponent(a, 'a');
  }

  factory RgbaColor.fromArgbInt(int color) {
    _validateArgbInt(color);
    return RgbaColor(
      r: argbRed(color),
      g: argbGreen(color),
      b: argbBlue(color),
      a: argbAlpha(color),
    );
  }

  final int r;
  final int g;
  final int b;
  final int a;

  RgbaColor copyWith({int? r, int? g, int? b, int? a}) {
    return RgbaColor(
      r: r ?? this.r,
      g: g ?? this.g,
      b: b ?? this.b,
      a: a ?? this.a,
    );
  }

  int toArgbInt() => (a << 24) | (r << 16) | (g << 8) | b;

  List<int> toRgbaBytes() => [r, g, b, a];

  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b, 'a': a};

  factory RgbaColor.fromJson(Map<String, dynamic> json) {
    return RgbaColor(
      r: json['r'] as int,
      g: json['g'] as int,
      b: json['b'] as int,
      a: json['a'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RgbaColor &&
          other.r == r &&
          other.g == g &&
          other.b == b &&
          other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'RgbaColor(r: $r, g: $g, b: $b, a: $a)';
}

void _validateComponent(int value, String fieldName) {
  if (value < 0 || value > 255) {
    throw ArgumentError.value(
      value,
      fieldName,
      'RgbaColor.$fieldName must be between 0 and 255 inclusive.',
    );
  }
}

void _validateArgbInt(int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw ArgumentError.value(
      value,
      'color',
      'ARGB color must be between 0 and 0xFFFFFFFF inclusive.',
    );
  }
}
