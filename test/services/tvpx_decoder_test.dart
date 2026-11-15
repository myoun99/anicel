// A TVPaint panel export (`.tvpx`) read as brushes: a tar of the panel's
// buttons and, for each custom brush, its settings and its tip — a DEEP
// animation. The files here are made in the test in the shape the user's
// BRUSH.tvpx was measured to have (card I-86); the user's own is not in
// the repository.
import 'dart:convert';
import 'dart:typed_data';

import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_texture_mode.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/services/brush_import_result.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';
import 'package:anicel/src/services/tvpx/tvpx_decoder.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a button under a heading is a brush of its tip\'s frames, a positive '
      'skip keeping the frame before and a negative one clearing', () async {
    final result = await decodeTvpxBrushFile(
      _panelFile(
        heading: 'カスタム鉛筆  HB',
        buttons: [_button('8', 'pencil')],
        tools: {'pencil': (tool: _tool(size: '8.000000'), dip: _pencilDip)},
      ),
      sourceName: 'BRUSH',
    );

    final preset = result.presets.single;
    expect(preset.name, 'カスタム鉛筆 HB 8');
    final settings = preset.settings;
    expect([for (final tip in settings.tips) tip.alpha.toList()], [
      [10, 20, 30, 40, 50, 60, 70, 80, 90],
      [10, 20, 30, 99, 0, 0, 70, 0, 0],
    ]);
    expect(settings.tips.first.size, 3);
    expect(settings.size, 3 * 8 / 100);
    expect(settings.opacity, 0.6);
    expect(settings.spacing, BrushShape.generalSpacing);
    expect(settings.tipOrder, BrushTipOrder.random);
  });

  test('🎯the size is its share of the tip\'s longer side: at 100 the tip '
      'as TVPaint drew it, and with none said the same', () async {
    // Two wide, four high: the side a mask's square spans is its height.
    final tall = _dip(
      [
        [for (var row = 0; row < 4; row += 1) ..._literal([80, 90])],
      ],
      width: 2,
      height: 4,
    );
    const sizes = ['100', '20', '8'];
    final result = await decodeTvpxBrushFile(
      _panelFile(
        heading: 'HB',
        buttons: [for (final size in [...sizes, '']) _button(size, 'b$size')],
        tools: {
          for (final size in sizes)
            'b$size': (tool: _tool(size: '$size.000000'), dip: tall),
          'b': (tool: _tool(size: ''), dip: tall),
        },
      ),
      sourceName: 'BRUSH',
    );

    expect(
      [for (final preset in result.presets) preset.settings.size],
      [4, 4 * 20 / 100, 4 * 8 / 100, 4],
    );
  });

  test('🎯TVPaint\'s Cement Hard is laid as the nearest of the app\'s papers '
      'the way the user\'s hand matched it at hardness 70 — a texel a pixel, '
      'at full density, met by height — its size and turn as said; another '
      'hardness and a second paper are said to be not carried, the blending '
      'of a second paper there is none of is said nothing of, and a paper '
      'off is no paper', () async {
    final result = await decodeTvpxBrushFile(
      _panelFile(
        heading: 'H',
        buttons: [
          _button('a', 'pencil', paper: _paper()),
          _button(
            'b',
            'pencil',
            paper: _paper(
              hardness: '40',
              size: '2.000000',
              invert: '1',
              angle: '15.000000',
              dual: '1',
              blending: 'Screen',
            ),
          ),
          _button('c', 'pencil', paper: 'Active 0'),
          _button('d', 'pencil', paper: _paper(blending: '背後に描画')),
        ],
        tools: {'pencil': (tool: _tool(), dip: _pencilDip)},
      ),
      sourceName: 'BRUSH',
    );

    final [a, b, c, d] = [for (final p in result.presets) p.settings];
    expect(a.textureMaskSource, same(graphiteToothTextureMask));
    expect(
      [
        a.textureScale,
        a.textureDensity,
        a.textureContrast,
        a.textureBrightness,
      ],
      [1.0, 1.0, -0.54, 0.2],
    );
    expect(a.textureInvert, isFalse);
    expect(a.textureMode, BrushTextureMode.height);
    expect(a.tips, hasLength(2), reason: 'the tip is kept beside the paper');
    expect(a.size, 3 * 8 / 100);
    expect([b.textureScale, b.textureDensity], [2.0, 1.0]);
    expect(b.textureMode, BrushTextureMode.height);
    expect(b.textureInvert, isTrue);
    expect(c.textureMaskSource, isNull);
    expect(
      [d.textureScale, d.textureDensity, d.textureMode],
      [a.textureScale, a.textureDensity, a.textureMode],
      reason: 'the blending is a second paper\'s, and there is none',
    );
    const laid =
        'is TVPaint\'s own and not in the file; the nearest of the app\'s '
        'papers is laid instead.';
    expect(result.warnings, [
      'Button "H a": paper "Cement Hard" $laid',
      'Button "H b": paper "Cement Hard" $laid',
      'Button "H b": paper Hardness 40 is not carried; the paper is laid as '
          'at 70.',
      'Button "H b": paper Angle 15.000000 is not carried.',
      'Button "H b": paper DualPaper 1 is not carried.',
      'Button "H d": paper "Cement Hard" $laid',
    ]);
  });

  test('a tip that says no count of frames is a still: its one picture is '
      'the brush\'s one tip', () async {
    final result = await decodeTvpxBrushFile(
      _panelFile(
        heading: 'H',
        buttons: [_button('still', 'still')],
        tools: {'still': (tool: _tool(), dip: _stillDip)},
      ),
      sourceName: 'BRUSH',
    );

    expect(result.presets.single.settings.tips, hasLength(1));
    expect(result.warnings, isEmpty);
  });

  test('a tip not read as TVPaint wrote it — written over with what it '
      'already held, or not 8-bit BGRA — is refused, and only its button is '
      'left out', () async {
    final result = await decodeTvpxBrushFile(
      _panelFile(
        heading: 'H',
        buttons: [
          _button('8', 'pencil'),
          _button('9', 'stale'),
          _button('10', 'rgba'),
        ],
        tools: {
          'pencil': (tool: _tool(), dip: _pencilDip),
          'stale': (tool: _tool(), dip: _staleDip),
          'rgba': (tool: _tool(), dip: _rgbaDip),
        },
      ),
      sourceName: 'BRUSH',
    );

    expect([for (final preset in result.presets) preset.name], ['H 8']);
    expect(result.warnings, [
      'Button "H 9": its tip was not read '
          '(A frame wrote over pixels what they already held.).',
      'Button "H 10": its tip was not read (The tip is not 8-bit BGRA.).',
    ]);
  });

  test('what a brush sets and this reader does not carry is said — a brush '
      'that smears comes in by its tip, its smear said to be left — and a '
      'button whose tip it cannot carry is left out', () async {
    final result = await decodeTvpxBrushFile(
      _panelFile(
        heading: 'H',
        buttons: [
          _button('8', 'pencil', paper: _paper(name: '/Rough')),
          '1_cmd0=Tool:tv_wetbrush mode "color" size 20.000000',
          _button('origin', 'origin'),
          _button('smear', 'smear'),
          _button('source', 'source'),
          _button('hue', 'hue'),
        ],
        tools: {
          'pencil': (
            tool: _tool(angle: '10.000000', sizeCurve: '10;3 0 0 0 1 1 1'),
            dip: _pencilDip,
          ),
          'origin': (tool: _tool(stamp: '0'), dip: _pencilDip),
          'smear': (tool: _tool(stamp: '6'), dip: _pencilDip),
          'source': (tool: _tool(stamp: '7'), dip: _pencilDip),
          'hue': (tool: _tool(stamp: '5'), dip: _pencilDip),
        },
      ),
      sourceName: 'BRUSH',
    );

    expect(
      [for (final preset in result.presets) preset.name],
      ['H 8', 'H smear', 'H source'],
    );
    final [pencil, smear, source] = [
      for (final preset in result.presets) preset.settings,
    ];
    expect(pencil.textureMaskSource, isNull);
    for (final smears in [smear, source]) {
      expect(smears.tips, hasLength(2), reason: 'its tip, as a pencil\'s');
      expect([smears.size, smears.opacity], [pencil.size, pencil.opacity]);
      expect(smears.mixesGroundColor, isFalse, reason: 'the smear is left');
    }
    expect(result.warnings, [
      'Button "H" is not a custom brush; not imported.',
      'Button "H origin": stamp mode 0 is not Alpha; not imported.',
      'Button "H smear": stamp mode 6 smears; its smear is not carried.',
      'Button "H source": stamp mode 7 smears; its smear is not carried.',
      'Button "H hue": stamp mode 5 is not Alpha; not imported.',
      'Button "H 8": paper "Rough" is TVPaint\'s own and not in the file; '
          'imported without it.',
      'Brush "H 8": angle 10.000000 is not carried.',
      'Brush "H 8": curve c_size2 is not carried.',
    ]);
  });

  test('a file holding no custom panel is refused', () async {
    final noPanel = Uint8List.fromList(
      TarEncoder().encodeBytes(
        Archive()..addFile(ArchiveFile.string('config.txt', '[x]')),
      ),
    );
    for (final bytes in [noPanel, Uint8List.fromList(utf8.encode('junk'))]) {
      await expectLater(
        decodeTvpxBrushFile(bytes, sourceName: 'x'),
        throwsA(
          isA<TvpxDecodeException>().having(
            (refusal) => refusal.reason.key,
            'key',
            'tvpxNoPanel',
          ),
        ),
      );
    }
  });

  test('a panel with not one brush it can carry is refused in the word '
      'every brush reader says it in', () async {
    final panel = _panelFile(
      heading: 'H',
      buttons: ['1_cmd0=Tool:tv_wetbrush mode "color"'],
      tools: const {},
    );

    await expectLater(
      decodeTvpxBrushFile(panel, sourceName: 'BRUSH'),
      throwsA(
        isA<TvpxDecodeException>().having(
          (refusal) => refusal.reason,
          'reason',
          brushFileHoldsNothing,
        ),
      ),
    );
  });
}

/// A grey pixel of [alpha] as TVPaint stores it: premultiplied BGRA.
List<int> _ink(int alpha) => [0, 0, 0, alpha];

List<int> _literal(List<int> alphas) => [
  alphas.length - 1,
  for (final alpha in alphas) ..._ink(alpha),
];

List<int> _run(int count, int alpha) => [257 - count, ..._ink(alpha)];

/// A DBAN skip of [count] pixels — written negative when [negative].
List<int> _skip(int count, {bool negative = false}) => [
  0x80,
  if (negative) 256 - count else count,
];

/// Frame 0 a literal row each; frame 1 keeps row 0 by a skip, writes 99 and
/// clears the rest of row 1 by a negative skip, keeps one pixel of row 2 and
/// writes the other two clear.
final Uint8List _pencilDip = _dip([
  [
    ..._literal([10, 20, 30]),
    ..._literal([40, 50, 60]),
    ..._literal([70, 80, 90]),
  ],
  [
    ..._skip(3),
    ..._literal([99]),
    ..._skip(2, negative: true),
    ..._skip(1),
    ..._run(2, 0),
  ],
]);

/// Frame 1 writes row 0 over with the very pixels frame 0 has there.
final Uint8List _staleDip = _dip([
  [
    ..._literal([10, 20, 30]),
    ..._literal([40, 50, 60]),
    ..._literal([70, 80, 90]),
  ],
  [..._literal([10, 20, 30]), ..._skip(3), ..._skip(3)],
]);

List<int> _u16(int value) => [value >> 8, value & 0xff];

List<int> _u32(int value) => [..._u16(value >> 16), ..._u16(value & 0xffff)];

List<int> _chunk(String id, List<int> body) => [
  ...id.codeUnits,
  ..._u32(body.length),
  ...body,
  if (body.length.isOdd) 0,
];

/// A still, as TVPaint writes a tip of one picture: no `NIMA`.
final Uint8List _stillDip = _dip(
  [
    [
      ..._literal([10, 20, 30]),
      ..._literal([40, 50, 60]),
      ..._literal([70, 80, 90]),
    ],
  ],
  counted: false,
);

/// The pencil's tip with its pixels laid out red first, as TVPaint's are
/// not.
final Uint8List _rgbaDip = _dip(
  [
    [
      ..._literal([10, 20, 30]),
      ..._literal([40, 50, 60]),
      ..._literal([70, 80, 90]),
    ],
  ],
  channels: const [1, 2, 3, 17],
);

/// A [width] × [height] DEEP animation of [frames]' rows: the first a DBOD,
/// the rest DBANs — its pixels' [channels] in the order DPEL names them, 8
/// bits each — saying how many frames it has where [counted].
Uint8List _dip(
  List<List<int>> frames, {
  List<int> channels = const [3, 2, 1, 17],
  int width = 3,
  int height = 3,
  bool counted = true,
}) {
  final chunks = [
    ..._chunk('DGBL', [
      ..._u16(width),
      ..._u16(height),
      ...List.filled(12, 0),
    ]),
    if (counted) ..._chunk('NIMA', _u32(frames.length)),
    ..._chunk('DPEL', [
      ..._u32(channels.length),
      for (final type in channels) ...[..._u16(type), ..._u16(8)],
    ]),
    ..._chunk('DLOC', [..._u16(width), ..._u16(height), ..._u32(0)]),
    ..._chunk('DBOD', frames.first),
    for (final frame in frames.skip(1)) ..._chunk('DBAN', frame),
  ];
  return Uint8List.fromList([
    ...'FORM'.codeUnits,
    ..._u32(4 + chunks.length),
    ...'DEEP'.codeUnits,
    ...chunks,
  ]);
}

String _tool({
  String size = '8.000000',
  String stamp = '1',
  String angle = '0.000000',
  String sizeCurve = '0;2 0 1 0 0 1 1 ',
}) => [
  '﻿[tvp tool]',
  'angle=$angle',
  'anim=5',
  'c_size2=$sizeCurve',
  'opacity=60.000000',
  'size=$size',
  'smear=50.0000',
  'stamp=$stamp',
  'stepon=0',
  '',
  '[tvp tool_mapx]',
  'mode=1',
].join('\r\n');

/// A button's keys, numbered in place by [_panelFile], picking the custom
/// brush [guid] — with TVPaint's paper command after it when [paper]
/// ([_paper]).
String _button(String text, String guid, {String? paper}) => [
  '1_cmd0=CBTool:$guid',
  if (paper != null) '1_cmd1=cmd: tv_paper $paper',
  '1_text=$text',
  '1_type=1',
].join('\n');

/// A paper command's words in the order the user's BRUSH.tvpx writes them.
String _paper({
  String name = '/Cement Hard',
  String hardness = '70',
  String size = '1.000000',
  String invert = '0',
  String angle = '0.000000',
  String dual = '0',
  String blending = '乗算',
}) =>
    'Hardness $hardness Invert $invert Size $size Angle $angle '
    'OffsetX 0.000000 OffsetY 0.000000 FlipX 0 FlipY 0 Active 1 '
    'Name "$name" Name2 "/" DualPaper $dual BlendingMode $blending';

/// The tar of a panel: a heading over [buttons] (each item's keys numbered
/// in order after it), and each of [tools] as an INI and a tip.
Uint8List _panelFile({
  required String heading,
  required List<String> buttons,
  required Map<String, ({String tool, Uint8List dip})> tools,
}) {
  final items = [
    '0_text=$heading\n0_type=2',
    for (final (index, button) in buttons.indexed)
      button.replaceAll(RegExp('^1_', multiLine: true), '${index + 1}_') +
          (button.contains('_type=') ? '' : '\n${index + 1}_type=1'),
  ];
  final lines = items.join('\n').replaceAll('\n', '\r\n');
  final panel = '﻿[toolbox]\r\n$lines';
  final archive = Archive()
    ..addFile(ArchiveFile.string('config.txt', '[p]\r\nkind=CustomPanel'))
    ..addFile(ArchiveFile.bytes('P/custompanel.bin', utf8.encode(panel)));
  for (final MapEntry(key: guid, value: (:tool, :dip)) in tools.entries) {
    archive
      ..addFile(
        ArchiveFile.bytes('P/custompanel.data/$guid.ini', utf8.encode(tool)),
      )
      ..addFile(ArchiveFile.bytes('P/custompanel.data/$guid.dip', dip));
  }
  return Uint8List.fromList(TarEncoder().encodeBytes(archive));
}
