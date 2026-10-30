import '../../models/layer_blend_mode.dart';
import '../../models/project_frame_rate.dart';

/// After Effects as the AE Script tab hands it over (ae-script-export): a
/// project of comps, each a stack of layers, written as ONE ExtendScript
/// the user runs in After Effects (File › Scripts › Run Script File…)
/// beside the cels it names.
///
/// 🗣️ae-script-export-Q1 (유저 2026-10-15): 「카메라같은건 애초에 업계에서
/// 카메라용 컴포지션(카메라 해상도 크기의 컴포지션,그안에 소재 컴포지션있음),
/// 그리고 소재 컴포지션(캔버스 사이즈의 컴포지션. 여기에 원본 그림이 들어감)」
/// — what goes in which comp is the plan's (`aeCompsOf`); this is how a
/// comp is SAID to After Effects.
///
/// ⛔Nothing here reads the app's model beyond the blend a layer wears: the
/// values are already AE's — percents, degrees, pixels of the comp.
class AeScript {
  const AeScript({required this.name, required this.rate, required this.comps});

  /// The project bin everything the script makes goes into.
  final String name;

  final ProjectFrameRate rate;

  /// Every comp, in the order the script makes them: a comp a layer shows
  /// comes before the comp that layer stands in.
  final List<AeComp> comps;
}

/// One comp: a stack of layers, BOTTOM-UP, over [frames] frames.
class AeComp {
  const AeComp({
    required this.name,
    required this.width,
    required this.height,
    required this.frames,
    required this.layers,
    this.tucked = false,
  });

  final String name;
  final int width;
  final int height;
  final int frames;

  /// Bottom-up, as the app stacks its rows — the script adds each on top of
  /// the ones before it.
  final List<AeLayer> layers;

  /// Whether the comp goes into the bin's sub-bin of parts — a row's cels,
  /// a folder's picture — rather than beside the cut comps.
  final bool tucked;
}

/// What a layer shows: a picture file, another comp, a sound — or nothing, a
/// null layer that only carries the layers parented to it.
sealed class AeLayerSource {
  const AeLayerSource();
}

/// A picture beside the script, at [path] relative to it, shown from
/// [frame] for [length] frames — a cel of a row's cel comp, one frame; a
/// guide drawn once for the cut, all of it.
final class AeStill extends AeLayerSource {
  const AeStill({required this.path, required this.frame, this.length = 1});

  final String path;
  final int frame;
  final int length;
}

/// Another comp of the script, shown whole over this one — or, with
/// [AeLayer.timeRemap], a frame of it at a time.
final class AeCompSource extends AeLayerSource {
  const AeCompSource(this.comp);

  final AeComp comp;
}

/// A null layer: no picture — the transform it lends the layers parented
/// to it (a folder that composites nothing of its own).
final class AeNullSource extends AeLayerSource {
  const AeNullSource();
}

/// A sound beside the script, at [path] relative to it, heard from the
/// comp's start — the cut's own, as the app plays it.
///
/// 🗣️ae-script-export-Q4 (유저 2026-10-16): 「넣는다 — 앱이 놓은 그대로
/// WAV 로」.
final class AeSound extends AeLayerSource {
  const AeSound(this.path);

  final String path;
}

/// One layer of a comp.
class AeLayer {
  const AeLayer({
    required this.name,
    required this.source,
    this.transform,
    this.blend = LayerBlendMode.normal,
    this.enabled = true,
    this.parent,
    this.timeRemap = const [],
    this.guide = false,
  });

  final String name;
  final AeLayerSource source;

  /// Whether it is After Effects' guide layer: seen in the comp's window,
  /// never in a render — 🗣️ae-script-export-Q3 (유저 2026-10-16) 「AE 가이드
  /// 레이어로 따로」, for the camera's path and the directions.
  final bool guide;

  /// Null leaves After Effects' own: the picture centred in the comp.
  final AeTransform? transform;

  final LayerBlendMode blend;
  final bool enabled;

  /// The layer of the same comp whose transform this one's is under — a
  /// folder's null. Its values are in that layer's space.
  final AeLayer? parent;

  /// Which frame of an [AeCompSource] shows from each frame on, a HOLD key
  /// each — the frames where it changes. Empty plays the comp as it runs.
  final List<({int frame, int source})> timeRemap;
}

/// A layer's transform, After Effects' five, each over the comp's frames.
/// [scale] and [opacity] are percents, [rotation] degrees clockwise.
class AeTransform {
  const AeTransform({
    required this.anchor,
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });

  final AeChannel anchor;
  final AeChannel position;
  final AeChannel scale;
  final AeChannel rotation;
  final AeChannel opacity;
}

/// One property's value over a comp: the one value it holds, or its value
/// at every frame.
///
/// ⛔A value a frame, not keys: how a value becomes keys is After Effects'
/// question ([writeAeScript]) — which property can be thinned, which must
/// be keyed at every frame.
class AeChannel {
  const AeChannel.still(List<double> this.value) : frames = null;

  /// [at] at each of [count] frames — one value when it never changes.
  factory AeChannel.sampled(int count, List<double> Function(int frame) at) {
    final frames = [for (var frame = 0; frame < count; frame += 1) at(frame)];
    final first = frames.first;
    return frames.every((value) => _sameValue(value, first))
        ? AeChannel.still(first)
        : AeChannel._frames(frames);
  }

  const AeChannel._frames(List<List<double>> this.frames) : value = null;

  final List<double>? value;
  final List<List<double>>? frames;
}

bool _sameValue(List<double> a, List<double> b) {
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// AE-friendly number text: integers bare, fractions trimmed to at most
/// four decimals without trailing zeros.
String formatAeNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// After Effects' name for [blend] (`BlendingMode.…`). A folder's 통과 has
/// none: a folder that passes its rows through is no layer of its own.
String aeBlendingModeOf(LayerBlendMode blend) => switch (blend) {
  LayerBlendMode.passThrough || LayerBlendMode.normal => 'NORMAL',
  LayerBlendMode.darken => 'DARKEN',
  LayerBlendMode.multiply => 'MULTIPLY',
  LayerBlendMode.colorBurn => 'COLOR_BURN',
  LayerBlendMode.linearBurn => 'LINEAR_BURN',
  LayerBlendMode.subtract => 'SUBTRACT',
  LayerBlendMode.lighten => 'LIGHTEN',
  LayerBlendMode.screen => 'SCREEN',
  LayerBlendMode.colorDodge => 'COLOR_DODGE',
  LayerBlendMode.add => 'ADD',
  LayerBlendMode.overlay => 'OVERLAY',
  LayerBlendMode.softLight => 'SOFT_LIGHT',
  LayerBlendMode.hardLight => 'HARD_LIGHT',
  LayerBlendMode.difference => 'DIFFERENCE',
  LayerBlendMode.vividLight => 'VIVID_LIGHT',
  LayerBlendMode.linearLight => 'LINEAR_LIGHT',
  LayerBlendMode.pinLight => 'PIN_LIGHT',
  LayerBlendMode.hardMix => 'HARD_MIX',
  LayerBlendMode.exclusion => 'EXCLUSION',
  LayerBlendMode.darkerColor => 'DARKER_COLOR',
  LayerBlendMode.lighterColor => 'LIGHTER_COLOR',
  LayerBlendMode.divide => 'DIVIDE',
  LayerBlendMode.hue => 'HUE',
  LayerBlendMode.saturation => 'SATURATION',
  LayerBlendMode.chroma => 'COLOR',
  LayerBlendMode.luminosity => 'LUMINOSITY',
};

/// [script] as ExtendScript.
///
/// 🔬What After Effects 2025 does with a script, measured on it (`-noui -r`,
/// 2026-10-30) — each a rule below:
/// - a property object is fetched again for every call ([_helpers]' `tf`):
///   one held across a change of its layer's properties crashed AE;
/// - Time Remap's two keys are overwritten and the rest removed, never all
///   removed first: keying a Time Remap left with no key crashed AE;
/// - a comp shown through Time Remap keeps its own frame rate when nested:
///   left to follow its holder, AE drew the cel comps' frames wrong — held
///   ones mixed, the same keys giving the same wrong frames every render —
///   where image-sequence footage under the same keys was right; with the
///   rate kept, every frame was the one keyed. AE then reads a value as the
///   frame at or just under it (0.9999 → 1, 1.6 → 1), so a value is the
///   cel's own frame;
/// - no spatial tangent is set (a two-value tangent crashed AE): a spatial
///   value is keyed at EVERY frame instead, so the path between keys is
///   only ever the path between two frames, and Position is keyed as its
///   two dimensions apart, which are not spatial and so thin as the others.
///
/// ASCII alone: a script without a byte-order mark is read in the system's
/// code page, so every other character is written escaped.
String writeAeScript(AeScript script) =>
    _AeScriptWriter(script).write();

class _AeScriptWriter {
  _AeScriptWriter(this.script);

  final AeScript script;
  final StringBuffer _out = StringBuffer();
  final Map<String, String> _footage = {};
  final Map<AeComp, String> _comps = Map.identity();

  String write() {
    final rate = script.rate;
    _out
      ..writeln('// Anicel -> After Effects. Run it in After Effects')
      ..writeln('// (File > Scripts > Run Script File...) with the cels it')
      ..writeln('// names beside it.')
      ..writeln('(function () {')
      ..writeln('  var RATE_N = ${rate.numerator};')
      ..writeln('  var RATE_D = ${rate.denominator};')
      ..writeln(_helpers)
      ..writeln('  app.beginUndoGroup(${_string(script.name)});')
      ..writeln(
        '  var bin = app.project.items.addFolder(${_string(script.name)});',
      )
      ..writeln('  var parts = app.project.items.addFolder("parts");')
      ..writeln('  parts.parentFolder = bin;')
      ..writeln('  var S = [];')
      ..writeln('  var C = [];')
      ..writeln('  var L = [];');
    for (final comp in script.comps) {
      _writeComp(comp);
    }
    _out
      ..writeln('  app.endUndoGroup();')
      ..writeln('}());');
    return _out.toString();
  }

  void _writeComp(AeComp comp) {
    final id = 'C[${_comps.length}]';
    _comps[comp] = id;
    _out.writeln(
      '  $id = comp(${_string(comp.name)}, ${comp.width}, ${comp.height}, '
      '${comp.frames}, ${comp.tucked ? 'parts' : 'bin'});',
    );
    final layers = <AeLayer, String>{};
    for (final layer in comp.layers) {
      final layerId = 'L[${layers.length}]';
      layers[layer] = layerId;
      _writeLayer(id, layer, layers);
    }
    // The nulls on top, in the order they stand, as AE hands them over.
    final nulls = [
      for (final layer in comp.layers)
        if (layer.source is AeNullSource) layer,
    ];
    for (final layer in nulls.reversed) {
      _out.writeln('  ${layers[layer]}.moveToBeginning();');
    }
    _out.writeln('  L = [];');
  }

  /// [layer], made in the comp [compId] names under the name [layers]
  /// gave it.
  void _writeLayer(String compId, AeLayer layer, Map<AeLayer, String> layers) {
    final id = layers[layer]!;
    switch (layer.source) {
      case AeStill(:final path, :final frame, :final length):
        _out.writeln(
          '  $id = still($compId, ${_footageOf(path)}, $frame, $length);',
        );
      case AeCompSource(comp: final source):
        _out.writeln('  $id = $compId.layers.add(${_comps[source]});');
      case AeNullSource():
        _out.writeln('  $id = $compId.layers.addNull($compId.duration);');
      case AeSound(:final path):
        _out.writeln('  $id = $compId.layers.add(${_footageOf(path)});');
    }
    _out.writeln('  $id.name = ${_string(layer.name)};');
    if (layer.timeRemap.isNotEmpty) {
      final frames = [for (final hold in layer.timeRemap) hold.frame];
      final sources = [for (final hold in layer.timeRemap) hold.source];
      _out.writeln('  remap($id, [${frames.join(', ')}], '
          '[${sources.join(', ')}]);');
    }
    final parent = layer.parent;
    if (parent != null) {
      _out.writeln('  parent($id, ${layers[parent]});');
    }
    final transform = layer.transform;
    if (transform != null) {
      _writeTransform(id, transform);
    }
    if (layer.blend != LayerBlendMode.normal &&
        layer.blend != LayerBlendMode.passThrough) {
      _out.writeln(
        '  $id.blendingMode = BlendingMode.${aeBlendingModeOf(layer.blend)};',
      );
    }
    if (!layer.enabled) {
      _out.writeln('  $id.enabled = false;');
    }
    if (layer.guide) {
      _out.writeln('  $id.guideLayer = true;');
    }
  }

  String _footageOf(String path) => _footage.putIfAbsent(path, () {
    final id = 'S[${_footage.length}]';
    _out.writeln('  $id = footage(${_string(path)});');
    return id;
  });

  void _writeTransform(String id, AeTransform transform) {
    // Every one is written, its default too: a value is in its parent's
    // space, and AE moved it when the parent was set.
    _channel(id, 'ADBE Anchor Point', transform.anchor, everyFrame: true);
    final position = transform.position;
    if (position.frames case final frames?) {
      _out.writeln('  split($id);');
      _channel(
        id,
        'ADBE Position_0',
        AeChannel._frames([for (final value in frames) [value[0]]]),
      );
      _channel(
        id,
        'ADBE Position_1',
        AeChannel._frames([for (final value in frames) [value[1]]]),
      );
    } else {
      _channel(id, 'ADBE Position', position);
    }
    _channel(id, 'ADBE Scale', transform.scale);
    _channel(id, 'ADBE Rotate Z', transform.rotation);
    _channel(id, 'ADBE Opacity', transform.opacity);
  }

  /// [channel] onto [property] of layer [id]: its one value, or keys —
  /// at every frame for a spatial property ([everyFrame]), else only where
  /// a line through the frames around bends, so the linear keys still give
  /// every frame its own value.
  void _channel(
    String id,
    String property,
    AeChannel channel, {
    bool everyFrame = false,
  }) {
    if (channel.value case final value?) {
      _out.writeln('  hold($id, "$property", ${_value(value)});');
      return;
    }
    final frames = channel.frames!;
    final kept = [
      for (var frame = 0; frame < frames.length; frame += 1)
        if (everyFrame || _bends(frames, frame)) frame,
    ];
    _out.writeln(
      '  keys($id, "$property", [${kept.join(', ')}], '
      '[${[for (final frame in kept) _value(frames[frame])].join(', ')}]);',
    );
  }

  static String _value(List<double> value) => value.length == 1
      ? formatAeNumber(value.single)
      : '[${value.map(formatAeNumber).join(', ')}]';
}

/// Whether [frames] needs a key at [frame] for linear keys to give every
/// frame its value: the ends, and every frame its neighbours do not lie in
/// a line with.
bool _bends(List<List<double>> frames, int frame) {
  if (frame == 0 || frame == frames.length - 1) {
    return true;
  }
  final before = frames[frame - 1];
  final at = frames[frame];
  final after = frames[frame + 1];
  for (var i = 0; i < at.length; i += 1) {
    if (((at[i] - before[i]) - (after[i] - at[i])).abs() > 1e-9) {
      return true;
    }
  }
  return false;
}

/// [text] as a script string literal, ASCII alone ([writeAeScript]).
String _string(String text) {
  final out = StringBuffer('"');
  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (unit < 0x20 || unit > 0x7e) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// The functions every script calls — the rules [writeAeScript] names.
const String _helpers = r'''
  function t(frame) { return frame * RATE_D / RATE_N; }
  var here = new File($.fileName).parent;
  function comp(name, width, height, frames, into) {
    var made = app.project.items.addComp(name, width, height, 1, t(frames),
      RATE_N / RATE_D);
    made.parentFolder = into;
    return made;
  }
  function footage(path) {
    var options = new ImportOptions(new File(here.fsName + "/" + path));
    options.sequence = false;
    var item = app.project.importFile(options);
    item.parentFolder = parts;
    return item;
  }
  function still(into, item, frame, length) {
    var layer = into.layers.add(item);
    layer.inPoint = t(frame);
    layer.outPoint = t(frame + length);
    return layer;
  }
  function tf(layer, name) {
    return layer.property("ADBE Transform Group").property(name);
  }
  function hold(layer, name, value) { tf(layer, name).setValue(value); }
  function keys(layer, name, frames, values) {
    var times = [];
    var i;
    for (i = 0; i < frames.length; i += 1) { times.push(t(frames[i])); }
    tf(layer, name).setValuesAtTimes(times, values);
    for (i = 1; i <= tf(layer, name).numKeys; i += 1) {
      tf(layer, name).setInterpolationTypeAtKey(i,
        KeyframeInterpolationType.LINEAR, KeyframeInterpolationType.LINEAR);
    }
  }
  function split(layer) { tf(layer, "ADBE Position").dimensionsSeparated = true; }
  function parent(layer, to) {
    if (layer.setParentWithJump) { layer.setParentWithJump(to); }
    else { layer.parent = to; }
  }
  function remap(layer, frames, sources) {
    var times = [];
    var values = [];
    var i;
    var k;
    var ours;
    layer.source.preserveNestedFrameRate = true;
    layer.timeRemapEnabled = true;
    for (i = 0; i < frames.length; i += 1) {
      times.push(t(frames[i]));
      values.push(t(sources[i]));
    }
    layer.property("ADBE Time Remapping").setValuesAtTimes(times, values);
    for (k = layer.property("ADBE Time Remapping").numKeys; k >= 1; k -= 1) {
      ours = false;
      for (i = 0; i < times.length; i += 1) {
        if (Math.abs(layer.property("ADBE Time Remapping").keyTime(k) -
            times[i]) < 1e-6) { ours = true; }
      }
      if (!ours) { layer.property("ADBE Time Remapping").removeKey(k); }
    }
    for (k = 1; k <= layer.property("ADBE Time Remapping").numKeys; k += 1) {
      layer.property("ADBE Time Remapping").setInterpolationTypeAtKey(k,
        KeyframeInterpolationType.HOLD, KeyframeInterpolationType.HOLD);
    }
    layer.outPoint = layer.containingComp.duration;
  }''';
