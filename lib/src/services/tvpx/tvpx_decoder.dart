import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/collection_equality.dart' show listEquals;
import '../../core/path_names.dart' show fileNameOfPath;
import '../../models/brush_preset.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_settings.dart';
import '../../models/brush_shape.dart';
import '../../models/brush_texture_mode.dart';
import '../../models/brush_tip_mask.dart';
import '../../models/brush_tip_order.dart';
import '../../models/import/import_warning.dart';
import '../brush_import_result.dart';
import '../brush_preset_id_mint.dart';
import '../brush_tip_coverage.dart';
import '../brush_tip_mask_defaults.dart' show graphiteToothTextureMask;
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
          tipSide: math.max(button.tip.width, button.tip.height),
          paper: button.paper,
          name: name,
          warnings: warnings,
        ),
      ),
    );
  }
  return BrushImportResult.orRefused(
    presets,
    warnings,
    refusal: TvpxDecodeException.new,
  );
}

/// A tip as the worker read it: the frames' coverage, [width] × [height]
/// each, and [key], its file's checksum — buttons that share a tip share
/// its masks.
typedef _Tip = ({int key, int width, int height, List<Uint8List> frames});

/// A button whose custom brush came out of the file whole — and its paper
/// command's words ([_paperWordsOf]), laid as the app's paper where the
/// brush is made ([_paperOf]): the app's papers are this isolate's.
typedef _ButtonRead = ({
  String name,
  String guid,
  Map<String, String> tool,
  _Tip tip,
  Map<String, String>? paper,
});

/// A panel's button: its label (under its heading) and its commands.
typedef _PanelButton = ({String name, List<String> commands});

const _customBrush = 'CBTool:';

final RegExp _itemLine = RegExp(r'^(\d+)_(\w+)=(.*)$');

const _paperCommand = 'tv_paper ';

final RegExp _paperWord = RegExp(r'(\w+) ("[^"]*"|\S+)');

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
/// why, where it picks none or one whose tip this reader cannot carry.
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
  // The stamp menu in the order TVPaint's own page lists it (doc.tvpaint.com,
  // Custom brushes, read 2026-11-15): 0 Origin, 1 Alpha, 2 Alpha Max,
  // 3 Luma, 4 Luma Invert, 5 Hue, 6 Smear, 7 Smear Source. Alpha is the
  // tip's alpha coloured with the A colour, which is what a tip mask is
  // (card I-86). Smear is, the page says, like Alpha but smearing the tip's
  // pixels onto the picture, and Smear Source the same onto a source
  // picture: the same mask, mixing with what is under it ([_smears]) — and
  // the app has no source picture, so a brush of the second smears its cel.
  // 🗣️유저 2026-11-15: 「누리용 Azi이런거 안들어왔는데 커스텀연필외
  // 임포트는 아직인가?」 · 「브러시는 커스텀브러시만」 — the custom brushes
  // come in, all a mask can hold. ↩️Only Alpha did.
  // The others colour the tip by its own pixels, which a mask cannot hold.
  if (tool['stamp'] != '1' && !_smears(tool)) {
    warnings.add(
      'Button "$name": stamp mode ${tool['stamp']} is not Alpha; '
      'not imported.',
    );
    return null;
  }
  if (tool['stamp'] == '7') {
    warnings.add(
      'Button "$name": stamp mode 7 smears a source picture; it smears '
      'its own cel here.',
    );
  }
  final _Tip tip;
  try {
    tip = _tipOf(dip.content);
  } on TvppRasterDecodeException catch (error) {
    warnings.add('Button "$name": its tip was not read (${error.message}).');
    return null;
  }
  Map<String, String>? paper;
  for (final extra in button.commands.skip(1)) {
    if (_paperWordsOf(extra) case final words?) {
      paper = words;
    } else {
      warnings.add('Button "$name": "$extra" is not carried.');
    }
  }
  return (name: name, guid: guid, tool: tool, tip: tip, paper: paper);
}

/// A button's paper command (`tv_paper`) as its words, each name and
/// value — the quotes of `Name "/Cement Hard"` taken off — or null where
/// [command] is no paper's.
Map<String, String>? _paperWordsOf(String command) {
  final at = command.indexOf(_paperCommand);
  if (at < 0) {
    return null;
  }
  return {
    for (final word in _paperWord.allMatches(
      command.substring(at + _paperCommand.length),
    ))
      word[1]!: word[2]!.replaceAll('"', ''),
  };
}

/// The app's paper laid for a TVPaint one, and how: TVPaint's own [size],
/// and whether it is turned over ([invert]).
typedef _Paper = ({_NearestPaper nearest, double size, bool invert});

/// The paper [words] say, as the app's nearest — null where it is off, or
/// is one the app has no nearest for; a warning says what is not carried.
///
/// 🗣️유저 2026-11-15 (I-86-Q3): 「우리 질감 중 가장 가까운 것을 대서
/// 넣는다」 — TVPaint's paper is its own, not in the file, and may not ship
/// with the app (`ip-review-clean`).
///
/// Hardness is how much the paper tells on the paint, its panel says, and
/// the nearest is matched at one hardness ([_NearestPaper.hardness]): at
/// another the paper is laid as matched, and a warning says so. ↩️It was
/// read as the texture's density, 70 as 0.7 — which the user's own hand
/// set to 100% for a paper of hardness 70 (2026-11-15, the words beside
/// [_nearestPaperTo]); one matched point is no scale to read others off.
///
/// `BlendingMode` is how a second paper (`Name2`, `DualPaper`) meets the
/// first — the menu TVPaint 12's paper window has for its two papers
/// (doc.tvpaint.com, Papers) — so with `DualPaper` 0 it says nothing: the
/// user's BRUSH.tvpx writes 乗算 on some pencils and 背後に描画 on others,
/// one paper each. ↩️Any but 乗算 was warned of as the paper's own
/// blending.
_Paper? _paperOf(
  Map<String, String> words, {
  required String name,
  required List<String> warnings,
}) {
  if (words['Active'] != '1') {
    return null;
  }
  final paper = fileNameOfPath(words['Name'] ?? '');
  final nearest = _nearestPaperTo(paper);
  if (nearest == null) {
    warnings.add(
      'Button "$name": paper "$paper" is TVPaint\'s own and not in the '
      'file; imported without it.',
    );
    return null;
  }
  warnings.add(
    'Button "$name": paper "$paper" is TVPaint\'s own and not in the file; '
    'the nearest of the app\'s papers is laid instead.',
  );
  final hardness = double.tryParse(words['Hardness'] ?? '');
  if (hardness != null && hardness != nearest.hardness) {
    warnings.add(
      'Button "$name": paper Hardness ${words['Hardness']} is not carried; '
      'the paper is laid as at ${nearest.hardness.round()}.',
    );
  }
  for (final key in const [
    'Angle',
    'OffsetX',
    'OffsetY',
    'FlipX',
    'FlipY',
    'DualPaper',
  ]) {
    if ((double.tryParse(words[key] ?? '') ?? 0) != 0) {
      warnings.add('Button "$name": paper $key ${words[key]} is not carried.');
    }
  }
  return (
    nearest: nearest,
    size: double.tryParse(words['Size'] ?? '') ?? 1,
    invert: words['Invert'] == '1',
  );
}

/// One of the app's papers made to stand for a TVPaint one at one
/// [hardness] of it: its [mask], [scale] canvas pixels a texel, the levels
/// ([contrast], [brightness]) that bring its values where the TVPaint
/// paper's are, and how it meets a dab ([mode]) — at the texture's full
/// density, which a brush has unless told otherwise.
typedef _NearestPaper = ({
  BrushTipMask mask,
  double scale,
  double contrast,
  double brightness,
  BrushTextureMode mode,
  double hardness,
});

/// The app's paper nearest TVPaint's [paper] — null for one not matched.
///
/// 🗣️유저 2026-11-15 (I-86, 실기 — カスタム鉛筆 HB, Cement Hard at
/// hardness 70): 「구조 자체는 우리구조 유지하되 예를들어 커스텀연필 HB로
/// 치면 질감쪽에서 배율 100%, 농도 100%, 텍스처 합성 높이로 하는게 제일
/// 근접했어」 · 「흑연결 그대로 두고 대비 밝기도 그대로였어」 — the tooth a
/// texel a pixel, at full density, met by height
/// ([BrushTextureMode.height]), its levels as they were.
/// ↩️The tooth was laid 3.5 pixels a texel and multiplied, the hardness
/// its density — the scale that followed the fall of Cement Hard's grain
/// closest (🔬the Surface's TVPaint 12, 2026-11-15, numbers only: half
/// its likeness at 2.3 pixels across and 1.6 down, no repeat; of the
/// app's four papers the tooth 0.034 apart over twelve pixels, cold press
/// 0.098, paper grain 0.168, canvas weave 0.183) — and the user's hand
/// found it short (「재현도가 부족해」): the stroke is what is matched, not
/// the paper's own statistics.
///
/// 🔬Beside the user's TVPaint pictures (2026-11-15; the ink a row of the
/// stroke holds — theirs · this · the multiplied one before): HB 20 2.86 ·
/// 2.75 · 3.60, and how the rows differ (cv) 0.38 · 0.19 · 0.03; at the
/// tip's own size the share of pixels neither bare nor full 0.06 · 0.09 ·
/// 0.26. ⚠️HB 8, a tip under two pixels across: 0.78 · 0.15 · 1.54 — the
/// height takes nearly all of so thin a dab (card I-86); from HB 10 up it
/// holds (0.96, 1.57, 1.88, 2.70, 3.73 at 10, 12.5, 15, 20, 25).
///
/// 🔬The levels are the paper measure's still: the paper's values average 0.57
/// and spread 0.11, the tooth's own spread 0.30, so they are drawn in to
/// 0.11 about 0.43.
/// ⏳Which way round a TVPaint paper lays ink is not on its page: read
/// as the paint it resists, its rare darkest texels are pits a lead
/// skips, as the tooth's bare share is — so the tooth stands unturned.
_NearestPaper? _nearestPaperTo(String paper) => switch (paper) {
  'Cement Hard' => (
    mask: graphiteToothTextureMask,
    scale: 1,
    contrast: -0.54,
    brightness: 0.2,
    mode: BrushTextureMode.height,
    hardness: 70,
  ),
  _ => null,
};

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
/// `DBAN` over the one before, as many as `NIMA` says — one where the file
/// has no `NIMA`: a still writes none, its `DBOD` its one frame (the user's
/// BRUSH.tvpx, 2026-11-15: 塗り用 粗 and 柔らか, with no `FRAT` or `BK64`
/// either).
_Tip _tipOf(Uint8List dip) {
  final data = ByteData.sublistView(dip);
  if (dip.length < 12 ||
      String.fromCharCodes(dip, 0, 4) != 'FORM' ||
      String.fromCharCodes(dip, 8, 12) != 'DEEP') {
    throw const TvppRasterDecodeException('The tip is not a DEEP picture.');
  }
  var width = 0;
  var height = 0;
  int? count;
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
  if (!listEquals(layout, _bgra)) {
    throw const TvppRasterDecodeException('The tip is not 8-bit BGRA.');
  }
  if (width == 0 ||
      height == 0 ||
      bodies.isEmpty ||
      bodies.length != (count ?? 1)) {
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

Future<List<BrushTipMask>> _masksOf(_Tip tip) async => [
  for (final (index, frame) in tip.frames.indexed)
    await brushTipMaskFromCoverage(
      frame,
      size: (width: tip.width, height: tip.height),
      id: 'tvpx-${tip.key.toRadixString(16)}-$index',
    ),
];

/// Whether [tool]'s stamp mode smears — 6 Smear, 7 Smear Source
/// ([_readButton]) — which here is the app's mixing with the picture under
/// the brush (下地混色): its `smear`, a percent, is how far a colour picked
/// up is drawn out ([BrushShape.colorStretch]), and the paint the brush is
/// loaded with stays a brush's own, full, so it lays its colour whatever
/// the smear.
///
/// 🗣️유저 2026-11-15 (I-86-Q6): 「그냥 우리식대로? 클튜기준대로? 적절히
/// 구현. 이런 커스텀브러시의 속성 하나하나 클튜때처럼 맞추는거 힘들고
/// tvp브러시는 그정도로 브러시 기능 뛰어난게아니라 가치가 낮음」 — laid by
/// the app's own mixing, and not measured against TVPaint's: what a smear
/// of 0, 20 or 100 does there is on no page of its manual.
bool _smears(Map<String, String> tool) =>
    tool['stamp'] == '6' || tool['stamp'] == '7';

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
/// `size` is the share, in percent, of the tip's own side the brush is
/// drawn at — so the size is that share of [tipSide], the longer side of
/// the tip as TVPaint drew it, which is what a mask's square spans
/// ([BrushTipMask.square]). 🗣️유저 2026-11-14 (I-86-Q1): 「tvp는 커스텀
/// 브러쉬의 경우 사이즈가 기본이 되는 소재 팁을 몇%로 줄였나라서, HB_100%는
/// 소재 크기 100%인 브러시」. 🔬Their HB_100% · HB20 · HB8 pictures
/// (2026-11-15) draw strokes 20–21, 3 and 1 pixels wide where the 23-pixel
/// tip's ink spans 17 — 23, 4.6 and 1.8 at this share. ↩️It was read as a
/// radius in pixels, TVPaint's page for its round brushes, and drew HB 8
/// 16 wide (유저 11-15 「tvp에서랑 임포트한거랑 전혀다름」).
/// With `stepon` 0 the step is the app's general one
/// ([BrushShape.generalSpacing], 유저 10-30 「특별한일없으면 기본값 다 5%」).
/// 🚨The anti-aliasing stays the brush default: a tip read from a picture
/// keeps its own soft edge whatever TVPaint's own setting
/// (유저 2026-11-14 「팁이 소재일때는 aa있어도되는거 … 괜히 aa없애는거 목표로
/// 하란게 아니란거임」) — at none the engine would threshold the mask.
/// `smear` is a smearing stamp mode's alone ([_smears]); an Alpha brush's
/// is left unread. The pen's pressure on its size and on its opacity comes
/// in as their curves ([_pressureCurveOf]); what drives any other setting
/// is a warning.
BrushSettings _settingsOf(
  Map<String, String> tool, {
  required List<BrushTipMask> tips,
  required int tipSide,
  required Map<String, String>? paper,
  required String name,
  required List<String> warnings,
}) {
  final laid = paper == null
      ? null
      : _paperOf(paper, name: name, warnings: warnings);
  for (final key in _notCarried) {
    if ((double.tryParse(tool[key] ?? '') ?? 0) != 0) {
      warnings.add('Brush "$name": $key ${tool[key]} is not carried.');
    }
  }
  for (final entry in tool.entries) {
    if (entry.key.startsWith('c_') &&
        !entry.value.startsWith('0;') &&
        !_isPressureCarried(entry.key, entry.value)) {
      warnings.add('Brush "$name": curve ${entry.key} is not carried.');
    }
  }
  final percent = double.tryParse(tool['size'] ?? '') ?? 0;
  final opacity = double.tryParse(tool['opacity'] ?? '') ?? 100;
  final drawn = _tipsDrawn(tool, tips);
  final settings = BrushSettings(
    size: tipSide * (percent > 0 ? percent : 100) / 100,
    opacity: (opacity / 100).clamp(0.0, 1.0),
    spacing: BrushShape.generalSpacing,
    tips: drawn,
    sizePressureCurve: _pressureCurveOf(
      tool,
      _sizeCurve,
      name: name,
      warnings: warnings,
    ),
    opacityPressureCurve: _pressureCurveOf(
      tool,
      _opacityCurve,
      name: name,
      warnings: warnings,
    ),
    mixesGroundColor: _smears(tool),
    colorStretch: _smears(tool)
        ? ((double.tryParse(tool['smear'] ?? '') ?? 0) / 100).clamp(0.0, 1.0)
        : 0,
    tipOrder: _tipOrderOf(
      tool['anim'],
      tips: drawn,
      name: name,
      warnings: warnings,
    ),
  );
  if (laid == null) {
    return settings;
  }
  final nearest = laid.nearest;
  return settings.copyWith(
    textureMaskSource: nearest.mask,
    textureInvert: laid.invert,
    textureContrast: nearest.contrast,
    textureBrightness: nearest.brightness,
    textureScale: nearest.scale * laid.size,
    textureMode: nearest.mode,
  );
}

/// The curves this reader carries: what drives the size, and the opacity.
const _sizeCurve = 'c_size2';
const _opacityCurve = 'c_opacity2';

/// The number a curve's connection is where the pen's pressure — 筆圧 —
/// drives it.
///
/// 🗣️유저 2026-11-15 (I-86-Q7): 「3번 왕복반복 말고 그냥 반복. 그 외는
/// 가설대로」 — the table put to them, the names read off TVPaint's own
/// panel where its file holds numbers only: connection 10 筆圧, and `anim`
/// 0 なし · 3 くり返し · 5 ランダム · 7 スピード ([_tipOrderOf]).
const _pressure = '10';

/// Whether [curve], the setting [key]'s, is one this reader brings in: the
/// pen's pressure on the size or on the opacity.
bool _isPressureCarried(String key, String curve) =>
    (key == _sizeCurve || key == _opacityCurve) &&
    curve.startsWith('$_pressure;');

/// [tool]'s curve [key] as the curve of ours the pen's pressure draws, or
/// null where the pressure does not drive it — or drives it flat at the
/// whole of it, which is no curve.
///
/// A curve is `<connection>;<points> <current> <kind> x0 y0 x1 y1 …`: the
/// profile's points in the unit square — the connection's input across, the
/// setting's share up — the first at x 0 and the last at x 1 (the user's
/// BRUSH.tvpx, 2026-11-15: 2 to 6 points). `<current>` is the point picked
/// in TVPaint's editor. `<kind>` is 1 on every two-point line there, 0 on
/// 25 of the 26 longer and 2 on the other; no page says what it draws, and
/// it is not read.
///
/// 🚨TVPaint's profile runs THROUGH its points and the app's curve is
/// PULLED by its own ([BrushPressureCurve]), so the points are not copied:
/// each between the ends becomes a pair about it ([_pulledThrough]). The
/// profile's lowest share is the curve's floor
/// ([BrushPressureCurve.minimum]) and its shape is laid from there up — as
/// a Photoshop brush's minimum diameter comes in (`abr_decoder`).
/// ⏳Between its points TVPaint's own bend is not measured — no picture of
/// a profile of theirs has been matched; at the points the two agree.
BrushPressureCurve? _pressureCurveOf(
  Map<String, String> tool,
  String key, {
  required String name,
  required List<String> warnings,
}) {
  final curve = tool[key];
  if (curve == null || !_isPressureCarried(key, curve)) {
    return null;
  }
  final through = _profilePointsOf(curve.substring(_pressure.length + 1));
  if (through == null) {
    warnings.add('Brush "$name": curve $key is not read.');
    return null;
  }
  final floor = through.map((point) => point.y).reduce(math.min);
  if (floor == 1) {
    return null;
  }
  return BrushPressureCurve(
    _pulledThrough([
      for (final point in through)
        BrushCurvePoint(point.x, (point.y - floor) / (1 - floor)),
    ]),
    minimum: floor,
  );
}

/// The points of [profile] — a curve after its connection — or null where
/// it is not `<points> <current> <kind>` and that many pairs a curve of
/// ours could stand on: in the unit square, from x 0 to x 1, each further
/// across than the one before ([BrushPressureCurve]'s own checks).
List<BrushCurvePoint>? _profilePointsOf(String profile) {
  final numbers = [
    for (final word in profile.trim().split(_spaces)) double.tryParse(word),
  ];
  final count = numbers.first?.toInt() ?? 0;
  if (numbers.length != 3 + count * 2 || numbers.contains(null)) {
    return null;
  }
  final points = [
    for (var at = 3; at < numbers.length; at += 2)
      BrushCurvePoint(numbers[at]!, numbers[at + 1]!),
  ];
  try {
    BrushPressureCurve(points);
  } on ArgumentError {
    return null;
  }
  return points;
}

/// The control points whose curve of ours ([BrushPressureCurve]) runs
/// through [through]: its ends, and for each point between them the pair
/// about it ([_pairAbout]) — the curve touches the middle of the edge
/// between two of its control points, and the pair's middle is the point.
List<BrushCurvePoint> _pulledThrough(List<BrushCurvePoint> through) => [
  through.first,
  for (var at = 1; at + 1 < through.length; at += 1)
    ..._pairAbout(
      through[at],
      before: through[at - 1],
      after: through[at + 1],
    ),
  through.last,
];

/// Two control points with [point] in their middle: a third of the way to
/// the nearer of its neighbours to either side — so the pairs of two
/// neighbours never meet — along the line from [before] to [after], the
/// curve's lean as it passes, flattened where it would leave the unit
/// square.
List<BrushCurvePoint> _pairAbout(
  BrushCurvePoint point, {
  required BrushCurvePoint before,
  required BrushCurvePoint after,
}) {
  final reach = math.min(point.x - before.x, after.x - point.x) / 3;
  final room = math.min(point.y, 1 - point.y);
  final rise = ((after.y - before.y) / (after.x - before.x) * reach).clamp(
    -room,
    room,
  );
  return [
    BrushCurvePoint(point.x - reach, point.y - rise),
    BrushCurvePoint(point.x + reach, point.y + rise),
  ];
}

/// The tips a dab takes: every frame — or, with `anim` 0, TVPaint's なし,
/// the one frame that is the brush's current image (`currentimage`), the
/// first where that names none of them.
///
/// ⏳That なし draws the current image is read off the key's name and
/// TVPaint's page for anim brushes, which shows «the number of the image
/// currently used by your Anim Brush» (doc.tvpaint.com, read 2026-11-15) —
/// no page says what なし draws, and it is not held to a stamp of theirs.
List<BrushTipMask> _tipsDrawn(
  Map<String, String> tool,
  List<BrushTipMask> tips,
) {
  if (tool['anim'] != '0') {
    return tips;
  }
  final current = int.tryParse(tool['currentimage'] ?? '') ?? 0;
  return [tips[current >= 0 && current < tips.length ? current : 0]];
}

/// The order `anim` names, by the table the user read off TVPaint
/// ([_pressure]): 5 ランダム, any tip afresh each dab; 3 くり返し, each in
/// turn — as the one tip of 0 なし is ([_tipsDrawn]). 7 スピード picks a tip
/// by how fast the stroke runs, which nothing of the app's does: it is said,
/// as a number the table does not hold is, and the tips take turns.
/// ↩️Only 5 was read (2026-11-14), every other number a warning.
BrushTipOrder _tipOrderOf(
  String? anim, {
  required List<BrushTipMask> tips,
  required String name,
  required List<String> warnings,
}) {
  if (anim == '5') {
    return BrushTipOrder.random;
  }
  if (anim == '7' && tips.length > 1) {
    warnings.add(
      'Brush "$name": anim 7 picks a tip by the stroke\'s speed, which is '
      'not carried; tips take turns.',
    );
  } else if (anim != '3' && tips.length > 1) {
    warnings.add('Brush "$name": anim $anim is not read; tips take turns.');
  }
  return BrushTipOrder.repeat;
}
