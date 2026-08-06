import '../../core/collection_equality.dart';

/// A rectangle in FORM space: fractions of the form's own box, never
/// pixels.
///
/// The form keeps its aspect ratio and is fitted into whichever paper the
/// envelope prints on (a real 봉투 size, or the cut's canvas), so a box
/// written in pixels would only be right for one of them. `models/` cannot
/// import `dart:ui`, which is why this is not a `Rect`.
class EnvelopeRect {
  const EnvelopeRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': width, 'h': height};

  factory EnvelopeRect.fromJson(Map<String, dynamic> json) => EnvelopeRect(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['w'] as num).toDouble(),
    height: (json['h'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvelopeRect &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'EnvelopeRect($x, $y, $width × $height)';
}

/// What a box holds — the CONTENT layer's three kinds.
enum EnvelopeContentKind {
  /// Nothing printed: handwriting space. The ink layer is the only thing
  /// that ever appears here.
  blank,

  /// Text resolved from a [EnvelopeBox.binding] token.
  text,

  /// A media asset (logo, 도장) resolved from a binding token.
  image;

  String toJson() => name;

  static EnvelopeContentKind fromJson(Object? json) =>
      values.asNameMap()[json] ?? EnvelopeContentKind.blank;
}

/// How a box's text sits inside it.
enum EnvelopeAlign {
  left,
  center,
  right;

  String toJson() => name;

  static EnvelopeAlign fromJson(Object? json) =>
      values.asNameMap()[json] ?? EnvelopeAlign.center;
}

/// One cell of a cut-envelope form.
///
/// A box carries at most one printed [label] (the FORM layer) and at most
/// one bound value (the CONTENT layer). Both are optional, because a real
/// envelope has boxes that only print a word, boxes that only take a
/// value, and boxes that are pure handwriting space.
class EnvelopeBox {
  const EnvelopeBox({
    required this.id,
    required this.rect,
    this.bordered = true,
    this.label,
    this.labelSize = 10,
    this.labelAlign = EnvelopeAlign.center,
    this.contentKind = EnvelopeContentKind.blank,
    this.binding,
    this.contentSize = 13,
    this.contentAlign = EnvelopeAlign.center,
    this.takesInk = true,
  }) : assert(
         contentKind == EnvelopeContentKind.blank || binding != null,
         'A text or image box needs a binding token.',
       );

  /// Stable within the form — the ink plane keys on it, so renaming a box
  /// orphans its annotations.
  final String id;

  final EnvelopeRect rect;

  /// Whether the FORM layer strokes this box's outline. False is how a
  /// form places a value (or a logo) without drawing a cell around it.
  final bool bordered;

  /// The printed word, in FORM-space text size (points at 1× form width).
  final String? label;
  final double labelSize;
  final EnvelopeAlign labelAlign;

  final EnvelopeContentKind contentKind;

  /// The binding this box resolves, e.g. `{cut[0].name}` or `{logo}`.
  final String? binding;
  final double contentSize;
  final EnvelopeAlign contentAlign;

  /// Whether this box ANCHORS ink.
  ///
  /// Every stroke belongs to a box (there is no page plane and no margin
  /// box — boxes simply meet), so a display-only box like the logo opts
  /// out and stops competing for strokes that belong to the cell beneath
  /// or beside it.
  final bool takesInk;

  Map<String, dynamic> toJson() => {
    'id': id,
    'rect': rect.toJson(),
    if (!bordered) 'bordered': false,
    if (label != null) 'label': label,
    if (labelSize != 10) 'labelSize': labelSize,
    if (labelAlign != EnvelopeAlign.center) 'labelAlign': labelAlign.toJson(),
    if (contentKind != EnvelopeContentKind.blank)
      'content': contentKind.toJson(),
    if (binding != null) 'binding': binding,
    if (contentSize != 13) 'contentSize': contentSize,
    if (contentAlign != EnvelopeAlign.center)
      'contentAlign': contentAlign.toJson(),
    if (!takesInk) 'takesInk': false,
  };

  factory EnvelopeBox.fromJson(Map<String, dynamic> json) => EnvelopeBox(
    id: json['id'] as String,
    rect: EnvelopeRect.fromJson(json['rect'] as Map<String, dynamic>),
    bordered: json['bordered'] as bool? ?? true,
    label: json['label'] as String?,
    labelSize: (json['labelSize'] as num?)?.toDouble() ?? 10,
    labelAlign: EnvelopeAlign.fromJson(json['labelAlign']),
    contentKind: EnvelopeContentKind.fromJson(json['content']),
    binding: json['binding'] as String?,
    contentSize: (json['contentSize'] as num?)?.toDouble() ?? 13,
    contentAlign: EnvelopeAlign.fromJson(json['contentAlign']),
    takesInk: json['takesInk'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvelopeBox &&
          other.id == id &&
          other.rect == rect &&
          other.bordered == bordered &&
          other.label == label &&
          other.labelSize == labelSize &&
          other.labelAlign == labelAlign &&
          other.contentKind == contentKind &&
          other.binding == binding &&
          other.contentSize == contentSize &&
          other.contentAlign == contentAlign &&
          other.takesInk == takesInk;

  @override
  int get hashCode => Object.hash(
    id,
    rect,
    bordered,
    label,
    labelSize,
    labelAlign,
    contentKind,
    binding,
    contentSize,
    contentAlign,
    takesInk,
  );

  @override
  String toString() => 'EnvelopeBox($id, $contentKind${binding ?? ''})';
}

/// A line the FORM layer draws that is not a box outline — the rules that
/// split a printed cell without making separate cells of it.
class EnvelopeRule {
  const EnvelopeRule({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  Map<String, dynamic> toJson() => {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2};

  factory EnvelopeRule.fromJson(Map<String, dynamic> json) => EnvelopeRule(
    x1: (json['x1'] as num).toDouble(),
    y1: (json['y1'] as num).toDouble(),
    x2: (json['x2'] as num).toDouble(),
    y2: (json['y2'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvelopeRule &&
          other.x1 == x1 &&
          other.y1 == y1 &&
          other.x2 == x2 &&
          other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

/// A whole cut-envelope form: the boxes, the paper it wants, and nothing
/// about the project it will be filled from.
///
/// Bindings are INDEXED rather than repeated — `{cut[0].name}` through
/// `{cut[3].name}` are four ordinary boxes. A printed envelope cannot grow
/// a row either, so the form saying how many rows exist is the honest
/// model; an index past the last box simply has nowhere to print.
class CutEnvelopeForm {
  const CutEnvelopeForm({
    required this.id,
    required this.name,
    required this.aspectRatio,
    required this.boxes,
    this.rules = const [],
    this.paperArgb = 0xFFFFFFFF,
    this.inkArgb = 0xFF2C2C2A,
  }) : assert(aspectRatio > 0, 'A form has a positive aspect ratio.');

  /// Stable id — a project remembers which form it uses by this.
  final String id;

  /// Display name for the preset picker.
  final String name;

  /// width / height of the FORM box. The paper may be a different shape;
  /// the form keeps this ratio and the remainder stays margin (user rule:
  /// "여백은 여백인 채로").
  final double aspectRatio;

  final List<EnvelopeBox> boxes;
  final List<EnvelopeRule> rules;

  /// The PAPER layer's fill — kraft for a real 봉투, white for a digital
  /// one.
  final int paperArgb;

  /// The FORM layer's line and label colour.
  final int inkArgb;

  EnvelopeBox? boxById(String id) {
    for (final box in boxes) {
      if (box.id == id) {
        return box;
      }
    }
    return null;
  }

  /// Boxes that anchor ink, in draw order — the panel's hit list.
  List<EnvelopeBox> get inkBoxes => [
    for (final box in boxes)
      if (box.takesInk) box,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'aspect': aspectRatio,
    'boxes': [for (final box in boxes) box.toJson()],
    if (rules.isNotEmpty) 'rules': [for (final rule in rules) rule.toJson()],
    'paper': paperArgb,
    'ink': inkArgb,
  };

  factory CutEnvelopeForm.fromJson(Map<String, dynamic> json) =>
      CutEnvelopeForm(
        id: json['id'] as String,
        name: json['name'] as String,
        aspectRatio: (json['aspect'] as num).toDouble(),
        boxes: [
          for (final box in json['boxes'] as List<dynamic>)
            EnvelopeBox.fromJson(box as Map<String, dynamic>),
        ],
        rules: [
          for (final rule in json['rules'] as List<dynamic>? ?? const [])
            EnvelopeRule.fromJson(rule as Map<String, dynamic>),
        ],
        paperArgb: json['paper'] as int? ?? 0xFFFFFFFF,
        inkArgb: json['ink'] as int? ?? 0xFF2C2C2A,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutEnvelopeForm &&
          other.id == id &&
          other.name == name &&
          other.aspectRatio == aspectRatio &&
          other.paperArgb == paperArgb &&
          other.inkArgb == inkArgb &&
          listEquals(other.boxes, boxes) &&
          listEquals(other.rules, rules);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    aspectRatio,
    paperArgb,
    inkArgb,
    Object.hashAll(boxes),
    Object.hashAll(rules),
  );

  @override
  String toString() => 'CutEnvelopeForm($id, ${boxes.length} boxes)';
}
