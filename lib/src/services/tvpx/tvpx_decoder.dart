import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/brush_preset.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_shape.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_order.dart';
import '../../models/import/import_warning.dart';
import '../brush_import_result.dart';
import '../brush_preset_id_mint.dart';
import '../brush_tip_coverage.dart';
import '../import/tvpp_raster_decoder.dart';

/// Thrown when the file cannot be read as a TVPaint panel export at all.
class TvpxDecodeException extends ImportRefusal {
  const TvpxDecodeException(super.reason);
}

/// Decodes a TVPaint `.tvpx` — a custom panel exported as a tar — into a
/// brush preset for each of its buttons that picks a custom brush.
///
/// Inside (measured 2026-11-14 on the user's BRUSH.tvpx, card I-86):
/// `<panel>/custompanel.bin` holds the panel's items as INI keys — `<n>_type`
/// 1 a button, 2 a heading over the buttons after it; a button's `<n>_cmd0`
/// `CBTool:<guid>` picks the custom brush whose settings are
/// `<panel>/custompanel.data/<guid>.ini` (`[tvp tool]`) and whose tip is the
/// `<guid>.dip` beside it — an IFF DEEP animation, each frame one tip
/// ([decodeDeepFrameWords]).
///
/// The archive is read on a worker, as a Clip Studio brush's rows are; the
/// tips are made here.
Future<BrushImportResult> decodeTvpxBrushFile(
  Uint8List bytes, {
  required String sourceName,
}) async {
  final read = await Isolate.run(() => _readPanels(bytes));
  final warnings = [...read.warnings];
  final mint = BrushPresetIdMint();
  final tipsByKey = <int, List<BrushTipMask>>{};
  final presets = <BrushPreset>[];
  for (final (index, button) in read.buttons.indexed) {
    final tips = tipsByKey[button.tip.key] ??= await _masksOf(button.tip);
    final name = button.name.isEmpty
        ? '$sourceName brush ${index + 1}'
        : button.name;
    presets.add(
      BrushPreset(
        id: mint.next('tvpx-${button.guid}'),
        name: name,
        settings: _settingsOf(
          button.tool,
          tips: tips,
          name: name,
          warnings: warnings,
        ),
      ),
    );
  }
  if (presets.isEmpty) {
    throw const TvpxDecodeException(brushFileHoldsNothing);
  }
  return BrushImportResult(presets: presets, warnings: warnings);
}

/// A tip as the worker read it: the frames' coverage, [width] × [height]
/// each, and [key], its file's checksum — buttons that share a tip share
/// its masks.
typedef _Tip = ({int key, int width, int height, List<Uint8List> frames});

/// A button whose custom brush came out of the file whole.
typedef _ButtonRead = ({
  String name,
  String guid,
  Map<String, String> tool,
  _Tip tip,
});

/// A panel's button: its label (under its heading) and its commands.
typedef _PanelButton = ({String name, List<String> commands});

const _customBrush = 'CBTool:';

final RegExp _itemLine = RegExp(r'^(\d+)_(\w+)=(.*)$');

final RegExp _paperName = RegExp('tv_paper .*Name "([^"]*)"');

final RegExp _spaces = RegExp(r'\s+');

({List<_ButtonRead> buttons, List<String> warnings}) _readPanels(
  Uint8List bytes,
) {
  final Archive archive;
  try {
    archive = TarDecoder().decodeBytes(bytes);
  } on Object {
    throw _noPanel;
  }
  const panelName = 'custompanel.bin';
  final buttons = <_ButtonRead>[];
  final warnings = <String>[];
  var panels = 0;
  for (final file in archive.files) {
    if (!file.isFile || !file.name.endsWith('/$panelName')) {
      continue;
    }
    panels += 1;
    final folder = file.name.substring(
      0,
      file.name.length - panelName.length,
    );
    for (final button in _buttonsOf(_textOf(file.content))) {
      final read = _readButton(
        archive,
        '${folder}custompanel.data/',
        button,
        warnings,
      );
      if (read != null) {
        buttons.add(read);
      }
    }
  }
  if (panels == 0) {
    throw _noPanel;
  }
  return (buttons: buttons, warnings: warnings);
}

const _noPanel = TvpxDecodeException(
  ImportWarning('tvpxNoPanel', 'The file holds no TVPaint custom panel.'),
);

String _textOf(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// The buttons of [panel] in its order, each named by the heading over it
/// and its own label.
List<_PanelButton> _buttonsOf(String panel) {
  final items = <int, Map<String, String>>{};
  for (final line in const LineSplitter().convert(panel)) {
    final match = _itemLine.firstMatch(line);
    if (match != null) {
      (items[int.parse(match[1]!)] ??= {})[match[2]!] = match[3]!;
    }
  }
  final buttons = <_PanelButton>[];
  var heading = '';
  for (final index in items.keys.toList()..sort()) {
    final item = items[index]!;
    final label = (item['text'] ?? '').trim().replaceAll(_spaces, ' ');
    switch (item['type']) {
      case '2':
        heading = label;
      case '1':
        buttons.add((
          name: [heading, label].where((part) => part.isNotEmpty).join(' '),
          commands: [
            for (var n = 0; item['cmd$n'] != null; n += 1) item['cmd$n']!,
          ],
        ));
    }
  }
  return buttons;
}

/// [button]'s custom brush out of [archive] — or null, and a warning says
/// why, where it picks none or one this reader cannot carry whole.
_ButtonRead? _readButton(
  Archive archive,
  String data,
  _PanelButton button,
  List<String> warnings,
) {
  final name = button.name;
  final command = button.commands.firstOrNull ?? '';
  if (!command.startsWith(_customBrush)) {
    warnings.add('Button "$name" is not a custom brush; not imported.');
    return null;
  }
  final guid = command.substring(_customBrush.length).trim();
  final ini = archive.findFile('$data$guid.ini');
  final dip = archive.findFile('$data$guid.dip');
  if (ini == null || dip == null) {
    warnings.add('Button "$name": its brush is not in the file.');
    return null;
  }
  final tool = _toolOf(_textOf(ini.content));
  // ⏳The stamp menu's order as TVPaint's own page lists it (Origin, Alpha,
  // Alpha Max, Luma, …) — 1 Alpha: the tip's alpha, coloured with the A
  // colour, which is what a tip mask is (card I-86). The others colour the
  // tip by its own pixels, which a mask cannot hold.
  if (tool['stamp'] != '1') {
    warnings.add(
      'Button "$name": stamp mode ${tool['stamp']} is not Alpha; '
      'not imported.',
    );
    return null;
  }
  final _Tip tip;
  try {
    tip = _tipOf(dip.content);
  } on TvppRasterDecodeException catch (error) {
    warnings.add('Button "$name": its tip was not read (${error.message}).');
    return null;
  }
  for (final extra in button.commands.skip(1)) {
    final paper = _paperName.firstMatch(extra)?.group(1);
    warnings.add(
      paper == null
          ? 'Button "$name": "$extra" is not carried.'
          : 'Button "$name": paper "$paper" is TVPaint\'s own and not in '
                'the file; imported without it.',
    );
  }
  return (name: name, guid: guid, tool: tool, tip: tip);
}

/// The `[tvp tool]` section of a brush's INI, key by key.
Map<String, String> _toolOf(String ini) {
  final tool = <String, String>{};
  var inTool = false;
  for (final line in const LineSplitter().convert(ini)) {
    if (line.startsWith('[')) {
      inTool = line.trim() == '[tvp tool]';
      continue;
    }
    final equals = line.indexOf('=');
    if (inTool && equals > 0) {
      tool[line.substring(0, equals)] = line.substring(equals + 1).trim();
    }
  }
  return tool;
}

/// `DPEL`: four 8-bit elements — blue, green, red, then alpha (type 17) —
/// the premultiplied BGRA words [decodeDeepFrameWords] reads.
const List<int> _bgra = [
  ...[0, 0, 0, 4],
  ...[0, 3, 0, 8],
  ...[0, 2, 0, 8],
  ...[0, 1, 0, 8],
  ...[0, 17, 0, 8],
];

/// The frames of the DEEP animation [dip]: its `DBOD` the first, each
/// `DBAN` over the one before, as many as `NIMA` says.
_Tip _tipOf(Uint8List dip) {
  final data = ByteData.sublistView(dip);
  if (dip.length < 12 ||
      String.fromCharCodes(dip, 0, 4) != 'FORM' ||
      String.fromCharCodes(dip, 8, 12) != 'DEEP') {
    throw const TvppRasterDecodeException('The tip is not a DEEP picture.');
  }
  var width = 0;
  var height = 0;
  var count = 0;
  var layout = const <int>[];
  final bodies = <Uint8List>[];
  var at = 12;
  while (at + 8 <= dip.length) {
    final id = String.fromCharCodes(dip, at, at + 4);
    final length = data.getUint32(at + 4);
    if (at + 8 + length > dip.length) {
      throw const TvppRasterDecodeException('The tip is cut short.');
    }
    final body = Uint8List.sublistView(dip, at + 8, at + 8 + length);
    final fields = ByteData.sublistView(body);
    switch (id) {
      case 'DLOC' when length >= 4:
        width = fields.getUint16(0);
        height = fields.getUint16(2);
      case 'NIMA' when length >= 4:
        count = fields.getUint32(0);
      case 'DPEL':
        layout = body;
      case 'DBOD' || 'DBAN':
        bodies.add(body);
    }
    at += 8 + length + (length & 1);
  }
  if (!_sameBytes(layout, _bgra)) {
    throw const TvppRasterDecodeException('The tip is not 8-bit BGRA.');
  }
  if (width == 0 || height == 0 || bodies.isEmpty || bodies.length != count) {
    throw const TvppRasterDecodeException('The tip has no frames to read.');
  }
  final frames = <Uint8List>[];
  Uint32List? before;
  for (final body in bodies) {
    final words = decodeDeepFrameWords(
      body,
      width: width,
      height: height,
      before: before,
    );
    final coverage = Uint8List(words.length);
    for (var index = 0; index < words.length; index += 1) {
      coverage[index] = words[index] & 0xff;
    }
    frames.add(coverage);
    before = words;
  }
  return (key: getCrc32(dip), width: width, height: height, frames: frames);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < b.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

Future<List<BrushTipMask>> _masksOf(_Tip tip) async => [
  for (final (index, frame) in tip.frames.indexed)
    await brushTipMaskFromCoverage(
      frame,
      size: (width: tip.width, height: tip.height),
      id: 'tvpx-${tip.key.toRadixString(16)}-$index',
    ),
];

/// The settings a TVPaint value of zero leaves alone and any other changes,
/// none of which this reader carries yet — each one set is a warning.
const List<String> _notCarried = [
  'angle',
  'jitter',
  'shift',
  'rotation',
  'flipx',
  'flipy',
  'revertanim',
  'animinvert',
  'mode',
  'dry',
  'opaque',
  'projection',
  'smoothactivated',
  'stepon',
];

/// [tool]'s settings as ours.
///
/// ⏳`size` is a radius in pixels, TVPaint's page says, so the size is
/// twice it; with `stepon` 0 the step is the app's general one
/// ([BrushShape.generalSpacing], 유저 10-30 「특별한일없으면 기본값 다 5%」).
/// 🚨The anti-aliasing stays the brush default: a tip read from a picture
/// keeps its own soft edge whatever TVPaint's own setting
/// (유저 2026-11-14 「팁이 소재일때는 aa있어도되는거 … 괜히 aa없애는거 목표로
/// 하란게 아니란거임」) — at none the engine would threshold the mask.
/// `smear` is left unread: it is the Smear stamp mode's, and only Alpha
/// comes in.
BrushSettings _settingsOf(
  Map<String, String> tool, {
  required List<BrushTipMask> tips,
  required String name,
  required List<String> warnings,
}) {
  for (final key in _notCarried) {
    if ((double.tryParse(tool[key] ?? '') ?? 0) != 0) {
      warnings.add('Brush "$name": $key ${tool[key]} is not carried.');
    }
  }
  for (final entry in tool.entries) {
    if (entry.key.startsWith('c_') && !entry.value.startsWith('0;')) {
      warnings.add('Brush "$name": curve ${entry.key} is not carried.');
    }
  }
  final radius = double.tryParse(tool['size'] ?? '') ?? 0;
  final opacity = double.tryParse(tool['opacity'] ?? '') ?? 100;
  return BrushSettings(
    size: radius > 0 ? radius * 2 : tips.first.size.toDouble(),
    opacity: (opacity / 100).clamp(0.0, 1.0),
    spacing: BrushShape.generalSpacing,
    tips: tips,
    tipOrder: _tipOrderOf(
      tool['anim'],
      tips: tips,
      name: name,
      warnings: warnings,
    ),
  );
}

/// ⏳`anim` 5 is read as random (card I-86): TVPaint's page lists no order
/// for its menu, and a pencil's grain frames thrown afresh each dab is the
/// look they were cut for. Any other number is not read yet.
BrushTipOrder _tipOrderOf(
  String? anim, {
  required List<BrushTipMask> tips,
  required String name,
  required List<String> warnings,
}) {
  if (anim == '5') {
    return BrushTipOrder.random;
  }
  if (tips.length > 1) {
    warnings.add('Brush "$name": anim $anim is not read; tips take turns.');
  }
  return BrushTipOrder.repeat;
}
