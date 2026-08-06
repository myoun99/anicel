import 'cut_envelope_form.dart';

/// The bundled cut-envelope forms.
///
/// Both are written in the coordinates their reference sheets were
/// measured in — [_analogW]×[_analogH] for the 봉투, [_digitalW]×
/// [_digitalH] for the digital one — and divided into form fractions by
/// [_rect]. Keeping the measured numbers in the source is what lets a
/// change be checked against the photograph it came from.
abstract final class CutEnvelopePresets {
  static const String analogId = 'analog-wit';
  static const String digitalId = 'digital-check';

  static List<CutEnvelopeForm> get all => [analog, digital];

  static CutEnvelopeForm byId(String id) => id == digitalId ? digital : analog;

  /// The paper 봉투: a WIT STUDIO envelope, measured from the real sheet.
  static CutEnvelopeForm get analog => CutEnvelopeForm(
    id: analogId,
    name: 'カット袋 (アナログ)',
    aspectRatio: _analogW / _analogH,
    paperArgb: 0xFFE3D5B0,
    boxes: _analogBoxes(),
    rules: _analogRules(),
  );

  /// The digital envelope: a check grid and a large memo, the shape a
  /// studio ships as a layer inside the working file.
  static CutEnvelopeForm get digital => CutEnvelopeForm(
    id: digitalId,
    name: 'カット袋 (デジタル)',
    aspectRatio: _digitalW / _digitalH,
    boxes: _digitalBoxes(),
    rules: _digitalRules(),
  );
}

const double _analogW = 660;
const double _analogH = 497;
const double _digitalW = 660;
const double _digitalH = 452;

EnvelopeRect _rect(
  double x,
  double y,
  double w,
  double h, {
  required double formW,
  required double formH,
}) => EnvelopeRect(
  x: x / formW,
  y: y / formH,
  width: w / formW,
  height: h / formH,
);

EnvelopeRect _a(double x, double y, double w, double h) =>
    _rect(x, y, w, h, formW: _analogW, formH: _analogH);

EnvelopeRect _d(double x, double y, double w, double h) =>
    _rect(x, y, w, h, formW: _digitalW, formH: _digitalH);

EnvelopeRule _aRule(double x1, double y1, double x2, double y2) => EnvelopeRule(
  x1: x1 / _analogW,
  y1: y1 / _analogH,
  x2: x2 / _analogW,
  y2: y2 / _analogH,
);

/// The four approval boxes: a printed label above, a stamp space below.
List<EnvelopeBox> _approval(
  double x,
  double width,
  String label,
  String role,
) => [
  EnvelopeBox(
    id: 'approval-$role-label',
    rect: _a(x, 12, width, 22),
    label: label,
    labelSize: 10,
    takesInk: false,
  ),
  EnvelopeBox(
    id: 'approval-$role',
    rect: _a(x, 34, width, 46),
    contentKind: EnvelopeContentKind.image,
    binding: '{staff.$role.stamp}',
  ),
];

/// One CUT line: `C` printed at the left, the number beside it, then
/// seconds `+` frames inside a single cell.
List<EnvelopeBox> _cutLine(int index, double top) {
  final height = 52.5;
  return [
    EnvelopeBox(
      id: 'cut-$index-number',
      rect: _a(12, top, 79, height),
      label: 'C',
      labelSize: 13,
      labelAlign: EnvelopeAlign.left,
      contentKind: EnvelopeContentKind.text,
      binding: '{cut[$index].name}',
      contentSize: 14,
    ),
    // The length cell is ONE box (one ink home); the three readings sit on
    // top of it without borders of their own.
    EnvelopeBox(id: 'cut-$index-length', rect: _a(91, top, 177, height)),
    EnvelopeBox(
      id: 'cut-$index-seconds',
      rect: _a(91, top, 68, height),
      bordered: false,
      contentKind: EnvelopeContentKind.text,
      binding: '{cut[$index].seconds}',
      contentSize: 14,
      contentAlign: EnvelopeAlign.right,
      takesInk: false,
    ),
    EnvelopeBox(
      id: 'cut-$index-plus',
      rect: _a(159, top, 42, height),
      bordered: false,
      label: '+',
      labelSize: 13,
      takesInk: false,
    ),
    EnvelopeBox(
      id: 'cut-$index-frames',
      rect: _a(201, top, 67, height),
      bordered: false,
      contentKind: EnvelopeContentKind.text,
      binding: '{cut[$index].frames}',
      contentSize: 14,
      contentAlign: EnvelopeAlign.right,
      takesInk: false,
    ),
  ];
}

/// The 担当 table's columns: x, width, printed head, and the staff role
/// whose name fills the second row.
const List<(double, double, String, String?)> _staffColumns = [
  (28, 42, '原画', 'genga'),
  (70, 48, '動画', 'douga'),
  (118, 51, '色指定', 'colorDesign'),
  (169, 48, 'スキャン', 'scan'),
  (217, 51, 'トレス・ペイント', 'tracePaint'),
];

/// Cel rows: eight printed rows, the count the real sheet has room for.
const int _celRowCount = 8;
const double _celRowTop = 328;
const double _celRowHeight = 16;

List<EnvelopeBox> _analogBoxes() => [
  EnvelopeBox(
    id: 'episode',
    rect: _a(12, 12, 79, 68),
    contentKind: EnvelopeContentKind.text,
    binding: '{episode}',
    contentSize: 19,
  ),
  EnvelopeBox(
    id: 'title',
    rect: _a(91, 12, 328, 68),
    contentKind: EnvelopeContentKind.text,
    binding: '{title}',
    contentSize: 20,
  ),
  ..._approval(419, 55, '演出', 'director'),
  ..._approval(474, 51, '作監', 'animationDirector'),
  ..._approval(525, 55, '動検', 'inbetweenCheck'),
  ..._approval(580, 68, '色検査', 'colorCheck'),

  for (var index = 0; index < 4; index += 1)
    ..._cutLine(index, 80 + index * 52.5),

  const EnvelopeBox(
    id: 'sheet-space',
    rect: EnvelopeRect(
      x: 268 / _analogW,
      y: 80 / _analogH,
      width: 380 / _analogW,
      height: 210 / _analogH,
    ),
  ),

  // 担当 column: two glyphs stacked over the label and name rows, then a
  // cel letter per row.
  EnvelopeBox(
    id: 'staff-legend',
    rect: _a(12, 290, 16, 38),
    label: '担当',
    labelSize: 8,
  ),
  for (var row = 0; row < _celRowCount; row += 1)
    EnvelopeBox(
      id: 'cel-$row-name',
      rect: _a(12, _celRowTop + row * _celRowHeight, 16, _celRowHeight),
      contentKind: EnvelopeContentKind.text,
      binding: '{cel[$row].name}',
      contentSize: 10,
    ),
  EnvelopeBox(
    id: 'cel-total-label',
    rect: _a(12, 470, 16, 15),
    label: '計',
    labelSize: 9,
  ),

  for (final (x, width, head, role) in _staffColumns) ...[
    EnvelopeBox(
      id: 'staff-head-$head',
      rect: _a(x, 290, width, 16),
      label: head,
      labelSize: head.length > 4 ? 7 : 9,
      takesInk: false,
    ),
    EnvelopeBox(
      id: 'staff-name-${role ?? head}',
      rect: _a(x, 306, width, 22),
      contentKind: role == null
          ? EnvelopeContentKind.blank
          : EnvelopeContentKind.text,
      binding: role == null ? null : '{staff.$role.name}',
      contentSize: 10,
    ),
    for (var row = 0; row < _celRowCount; row += 1)
      EnvelopeBox(
        id: 'cel-$row-$head',
        rect: _a(x, _celRowTop + row * _celRowHeight, width, _celRowHeight),
        contentKind: head == '原画' || head == '動画'
            ? EnvelopeContentKind.text
            : EnvelopeContentKind.blank,
        binding: switch (head) {
          '原画' => '{cel[$row].genga}',
          '動画' => '{cel[$row].douga}',
          _ => null,
        },
        contentSize: 11,
      ),
    EnvelopeBox(
      id: 'cel-total-$head',
      rect: _a(x, 470, width, 15),
      contentKind: head == '原画' || head == '動画'
          ? EnvelopeContentKind.text
          : EnvelopeContentKind.blank,
      binding: switch (head) {
        '原画' => '{total.genga}',
        '動画' => '{total.douga}',
        _ => null,
      },
      contentSize: 11,
    ),
  ],

  // Right block: BG, 解像度 (dpi over scan/offset), 3D, 特効, 撮影.
  EnvelopeBox(
    id: 'bg-head',
    rect: _a(268, 290, 86, 16),
    label: 'BG',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(id: 'bg', rect: _a(268, 306, 86, 179)),
  EnvelopeBox(
    id: 'resolution-head',
    rect: _a(354, 290, 92, 15),
    label: '解像度',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(
    id: 'resolution-dpi',
    rect: _a(354, 305, 92, 20),
    label: 'dpi',
    labelSize: 9,
    labelAlign: EnvelopeAlign.right,
  ),
  EnvelopeBox(
    id: 'resolution-x-head',
    rect: _a(368, 325, 37, 20),
    label: 'X',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(
    id: 'resolution-y-head',
    rect: _a(405, 325, 41, 20),
    label: 'Y',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(
    id: 'scan-legend',
    rect: _a(354, 345, 14, 49),
    label: 'スキャン',
    labelSize: 7,
  ),
  EnvelopeBox(id: 'scan-x', rect: _a(368, 345, 37, 49)),
  EnvelopeBox(id: 'scan-y', rect: _a(405, 345, 41, 49)),
  EnvelopeBox(
    id: 'offset-legend',
    rect: _a(354, 394, 14, 91),
    label: 'オフセット',
    labelSize: 7,
  ),
  EnvelopeBox(id: 'offset-x', rect: _a(368, 394, 37, 91)),
  EnvelopeBox(id: 'offset-y', rect: _a(405, 394, 41, 91)),
  EnvelopeBox(
    id: '3d-head',
    rect: _a(446, 290, 52, 16),
    label: '3D',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(id: '3d', rect: _a(446, 306, 52, 60)),
  EnvelopeBox(
    id: 'fx-head',
    rect: _a(498, 290, 68, 16),
    label: '特効',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(id: 'fx', rect: _a(498, 306, 68, 60)),
  EnvelopeBox(
    id: 'photography-head',
    rect: _a(566, 290, 82, 16),
    label: '撮影',
    labelSize: 9,
    takesInk: false,
  ),
  EnvelopeBox(id: 'photography', rect: _a(566, 306, 82, 60)),
  // The logo cell runs the whole width under 3D…撮影 — no empty cell
  // beside it (user, 2026-08-06).
  EnvelopeBox(
    id: 'logo',
    rect: _a(446, 366, 202, 119),
    contentKind: EnvelopeContentKind.image,
    binding: '{logo}',
    takesInk: false,
  ),
];

List<EnvelopeRule> _analogRules() => [
  // Cut rows share one cell wall with the sheet space; the outer frame and
  // the block splits are boxes, so only the header's label rule is left.
  _aRule(419, 34, 648, 34),
];

List<EnvelopeBox> _digitalBoxes() => [
  EnvelopeBox(
    id: 'episode',
    rect: _d(30, 14, 62, 34),
    contentKind: EnvelopeContentKind.text,
    binding: '{episode}',
    contentSize: 17,
  ),
  EnvelopeBox(
    id: 'title',
    rect: _d(92, 14, 448, 34),
    contentKind: EnvelopeContentKind.text,
    binding: '{title}',
    contentSize: 18,
  ),
  EnvelopeBox(
    id: 'logo',
    rect: _d(540, 14, 104, 34),
    contentKind: EnvelopeContentKind.image,
    binding: '{logo}',
    takesInk: false,
  ),

  // L/O check: four approvers, each with a stamp space and a UP日 line,
  // then four correction rows.
  ..._digitalCheck(
    prefix: 'lo',
    left: 82,
    top: 82,
    columns: [
      ('演出', 'director'),
      ('監督', 'chiefDirector'),
      ('作画監督', 'animationDirector'),
      ('総作画監督', 'chiefAnimationDirector'),
    ],
  ),
  ..._digitalCheck(
    prefix: 'genga',
    left: 82,
    top: 270,
    columns: [('演出', 'director'), ('作画監督', 'animationDirector')],
  ),

  const EnvelopeBox(
    id: 'memo',
    rect: EnvelopeRect(
      x: 333 / _digitalW,
      y: 82 / _digitalH,
      width: 311 / _digitalW,
      height: 350 / _digitalH,
    ),
  ),
];

/// One check grid: a head row of roles, a stamp row, and the four
/// correction rows whose labels print OUTSIDE the table.
List<EnvelopeBox> _digitalCheck({
  required String prefix,
  required double left,
  required double top,
  required List<(String, String)> columns,
}) {
  const double columnWidth = 60;
  const double headHeight = 10;
  const double stampHeight = 62;
  const double rowHeight = 21;
  const List<String> corrections = ['シート修正', 'セル修正', '原図修正', 'frame修正'];
  return [
    for (var index = 0; index < columns.length; index += 1) ...[
      EnvelopeBox(
        id: '$prefix-head-$index',
        rect: _d(left + index * columnWidth, top, columnWidth, headHeight),
        label: columns[index].$1,
        labelSize: 9.5,
        takesInk: false,
      ),
      EnvelopeBox(
        id: '$prefix-stamp-$index',
        rect: _d(
          left + index * columnWidth,
          top + headHeight,
          columnWidth,
          stampHeight,
        ),
        label: 'UP日    /',
        labelSize: 8,
        labelAlign: EnvelopeAlign.left,
        contentKind: EnvelopeContentKind.image,
        binding: '{staff.${columns[index].$2}.stamp}',
      ),
      for (var row = 0; row < corrections.length; row += 1)
        EnvelopeBox(
          id: '$prefix-correction-$index-$row',
          rect: _d(
            left + index * columnWidth,
            top + headHeight + stampHeight + row * rowHeight,
            columnWidth,
            rowHeight,
          ),
        ),
    ],
    // Row labels sit OUTSIDE the grid, the way the reference sheet prints
    // them — form text with no cell of its own.
    for (var row = 0; row < corrections.length; row += 1)
      EnvelopeBox(
        id: '$prefix-correction-label-$row',
        rect: _d(
          left - 72,
          top + headHeight + stampHeight + row * rowHeight,
          70,
          rowHeight,
        ),
        bordered: false,
        label: corrections[row],
        labelSize: 10,
        labelAlign: EnvelopeAlign.right,
        takesInk: false,
      ),
  ];
}

List<EnvelopeRule> _digitalRules() => const [];
