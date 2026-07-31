import '../core/collection_equality.dart';
import 'app_language.dart';
import 'property_track.dart';
import 'string_id.dart';
import 'transform_track.dart' show lerpDouble;

/// Stable identity of one effect INSTANCE on a layer — the lane address
/// (`fx:<id>:<parameter>`) and the undo commands both name effects by this,
/// so reordering the chain never re-points a key edit at the wrong effect.
final class EffectId extends StringId {
  const EffectId(super.value);

  factory EffectId.fromJson(Map<String, dynamic> json) =>
      EffectId(json['value'] as String);
}

/// The effects a layer can carry (R6). Deliberately a SHORT list of things
/// whose math is exact on every backend: the color kinds fold into one
/// `ui.ColorFilter.matrix` and the blur is `ui.ImageFilter.blur`, so the
/// editing canvas, playback, the camera view and the exported video all
/// produce the same pixels without a shader (which `ImageFilter.shader`
/// would have made Impeller-only).
///
/// Levels/curves and glow are the natural next entries; both need a lookup
/// table or a second pass, which is a later slice — not a different model.
enum EffectKind {
  brightnessContrast('brightnessContrast'),
  hueSaturation('hueSaturation'),
  blur('blur');

  const EffectKind(this.jsonValue);

  final String jsonValue;

  /// The English menu/lane label — the vocabulary artists already read in
  /// AE and Photoshop.
  String get label => switch (this) {
    EffectKind.brightnessContrast => 'Brightness & Contrast',
    EffectKind.hueSaturation => 'Hue/Saturation',
    EffectKind.blur => 'Blur',
  };

  /// The label in the program language. Japanese follows Clip Studio's
  /// terms (user rule 07-22: ja localized first; every other language keeps
  /// the shared English vocabulary artists already read) — the exact rule
  /// [LayerBlendMode.labelFor] states for the blend names.
  String labelFor(AppLanguage language) => switch (language) {
    AppLanguage.ja => switch (this) {
      EffectKind.brightnessContrast => '明るさ・コントラスト',
      EffectKind.hueSaturation => '色相・彩度',
      EffectKind.blur => 'ぼかし',
    },
    _ => label,
  };

  /// Whether this kind SPREADS pixels outside their own coverage — the
  /// question the composite asks before deciding a folder must buffer, and
  /// the reason a blur can never be folded into a member's own draw.
  bool get spreadsPixels => this == EffectKind.blur;

  String toJson() => jsonValue;

  static EffectKind fromJson(Object? json) {
    for (final kind in EffectKind.values) {
      if (json == kind.jsonValue) {
        return kind;
      }
    }
    throw ArgumentError.value(
      json,
      'kind',
      'Effect kind must be one of '
          '${EffectKind.values.map((kind) => '"${kind.jsonValue}"').join(', ')}.',
    );
  }
}

/// How a parameter's value reads in the lane's value column.
enum EffectParameterUnit {
  /// A bare number (Brightness, Contrast, Saturation, Lightness — the
  /// −100…100 sliders every paint tool shows unitless).
  number,

  /// Degrees (Hue).
  degrees,

  /// Canvas pixels (Blur radii). ★ Canvas pixels, NOT device pixels: the
  /// playback cache renders at a reduced raster and must scale these, or a
  /// half-size preview would show a double-strength blur.
  pixels,
}

/// One parameter of one effect kind: its id, label, default and range.
/// The specs ARE the schema — the lane UI, the value parser, the JSON
/// round-trip and the resolver all read this table instead of repeating a
/// switch per effect.
class EffectParameterSpec {
  const EffectParameterSpec({
    required this.id,
    required this.label,
    required this.defaultValue,
    required this.minimum,
    required this.maximum,
    this.unit = EffectParameterUnit.number,
  });

  final String id;
  final String label;
  final double defaultValue;
  final double minimum;
  final double maximum;
  final EffectParameterUnit unit;

  double clamp(double value) => value.clamp(minimum, maximum).toDouble();
}

/// Every effect kind's parameters, in the order the lanes show them.
const Map<EffectKind, List<EffectParameterSpec>> effectParameterSpecs = {
  EffectKind.brightnessContrast: [
    EffectParameterSpec(
      id: 'brightness',
      label: 'Brightness',
      defaultValue: 0,
      minimum: -100,
      maximum: 100,
    ),
    EffectParameterSpec(
      id: 'contrast',
      label: 'Contrast',
      defaultValue: 0,
      minimum: -100,
      maximum: 100,
    ),
  ],
  EffectKind.hueSaturation: [
    EffectParameterSpec(
      id: 'hue',
      label: 'Hue',
      defaultValue: 0,
      minimum: -180,
      maximum: 180,
      unit: EffectParameterUnit.degrees,
    ),
    EffectParameterSpec(
      id: 'saturation',
      label: 'Saturation',
      defaultValue: 0,
      minimum: -100,
      maximum: 100,
    ),
    EffectParameterSpec(
      id: 'lightness',
      label: 'Lightness',
      defaultValue: 0,
      minimum: -100,
      maximum: 100,
    ),
  ],
  EffectKind.blur: [
    EffectParameterSpec(
      id: 'blurX',
      label: 'Blur Width',
      defaultValue: 0,
      minimum: 0,
      maximum: 500,
      unit: EffectParameterUnit.pixels,
    ),
    EffectParameterSpec(
      id: 'blurY',
      label: 'Blur Height',
      defaultValue: 0,
      minimum: 0,
      maximum: 500,
      unit: EffectParameterUnit.pixels,
    ),
  ],
};

List<EffectParameterSpec> effectParametersOf(EffectKind kind) =>
    effectParameterSpecs[kind]!;

EffectParameterSpec? effectParameterSpecOf(EffectKind kind, String id) {
  for (final spec in effectParametersOf(kind)) {
    if (spec.id == id) {
      return spec;
    }
  }
  return null;
}

/// One animatable effect parameter, in the AE property shape: a VALUE plus
/// an optional key [track]. Keys win where they exist — an empty track
/// means "not animated", and then the static [value] is the whole answer.
/// Same division the layer already draws between [Layer.opacity] and the
/// Opacity lane, so the lane substrate needs no new vocabulary.
class EffectParameter {
  EffectParameter({this.value = 0, PropertyTrack<double>? track})
    : track = track ?? PropertyTrack<double>.empty();

  final double value;
  final PropertyTrack<double> track;

  bool get isAnimated => track.isNotEmpty;

  /// The value at [frameIndex] — the key track when it has keys, the
  /// static value otherwise.
  double resolveAt(int frameIndex) => track.resolveAt(
    frameIndex: frameIndex,
    orElse: () => value,
    lerp: lerpDouble,
  );

  EffectParameter copyWith({double? value, PropertyTrack<double>? track}) =>
      EffectParameter(value: value ?? this.value, track: track ?? this.track);

  Map<String, dynamic> toJson() => {
    if (value != 0) 'value': value,
    if (track.isNotEmpty) 'keys': track.toJson((value) => value),
  };

  factory EffectParameter.fromJson(Map<String, dynamic> json) {
    return EffectParameter(
      value: (json['value'] as num?)?.toDouble() ?? 0,
      track: PropertyTrack.fromJson(
        json['keys'] as List?,
        (value) => (value as num).toDouble(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectParameter && other.value == value && other.track == track;

  @override
  int get hashCode => Object.hash(value, track);

  @override
  String toString() => 'EffectParameter($value, animated: $isAnimated)';
}

/// One effect on a layer: a kind, an enable switch and its parameters.
///
/// Effects apply over the layer's own picture in list order (AE's Effects
/// panel read top to bottom), BEFORE the transform and before the layer's
/// opacity/blend meet the stack.
///
/// R9 #24 corrected this: it used to say "after the transform", which is
/// backwards and contradicts the code it describes — the pose wraps the
/// draw (`canvas.save()` + `applyLayerPoseTransform`) while the effect
/// filters ride the paint INSIDE it, so the transform is last, exactly as
/// in AE. Anyone who implemented from the old sentence got the pipeline
/// reversed.
class LayerEffect {
  /// [parameters] is NORMALIZED to the kind's spec: every parameter the kind
  /// declares is materialized (missing ones at their default) and anything
  /// else is dropped.
  ///
  /// That canonical form is what makes `==` mean what it says. Without it,
  /// a chain built with a partial map and the same chain reloaded from JSON
  /// (which omits parameters at their default) would compare UNEQUAL while
  /// resolving to identical pixels — and this class's equality feeds the
  /// composite cache key, the autosave dirty check and the thumbnail
  /// signature.
  LayerEffect({
    required this.id,
    required this.kind,
    this.enabled = true,
    Map<String, EffectParameter>? parameters,
  }) : parameters = Map.unmodifiable({
         for (final spec in effectParametersOf(kind))
           spec.id:
               parameters?[spec.id] ??
               EffectParameter(value: spec.defaultValue),
       });

  /// A fresh effect of [kind], every parameter at its spec default — what
  /// "Add effect" creates (an effect you just added must change nothing
  /// until you touch a value). The plain constructor normalizes to exactly
  /// this; the name is here because the call sites read better.
  factory LayerEffect.defaults({
    required EffectId id,
    required EffectKind kind,
  }) => LayerEffect(id: id, kind: kind);

  final EffectId id;
  final EffectKind kind;

  /// The effect's own switch (AE's per-effect fx eyeball). A disabled
  /// effect resolves to nothing at all — it keeps its keys for later.
  final bool enabled;

  /// Parameter id → parameter, always the kind's FULL spec set (see the
  /// constructor). A parameter added to a spec later therefore appears at
  /// its default on old data, with no migration.
  final Map<String, EffectParameter> parameters;

  /// The named parameter. Non-null for every id the kind declares (the
  /// constructor materializes them); an id from another kind answers a
  /// zero-valued placeholder rather than throwing, so a stale lane address
  /// cannot crash a paint.
  EffectParameter parameterOf(String id) =>
      parameters[id] ??
      EffectParameter(
        value: effectParameterSpecOf(kind, id)?.defaultValue ?? 0,
      );

  LayerEffect copyWith({
    EffectKind? kind,
    bool? enabled,
    Map<String, EffectParameter>? parameters,
  }) {
    return LayerEffect(
      id: id,
      kind: kind ?? this.kind,
      enabled: enabled ?? this.enabled,
      parameters: parameters ?? this.parameters,
    );
  }

  /// [parameters] with one entry replaced — the shape every key/value edit
  /// commits.
  LayerEffect withParameter(String parameterId, EffectParameter parameter) {
    return copyWith(parameters: {...parameters, parameterId: parameter});
  }

  /// Whether this effect carries any animation at all (the lane group
  /// header's key union asks).
  bool get isAnimated => parameters.values.any((value) => value.isAnimated);

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'kind': kind.toJson(),
    if (!enabled) 'enabled': false,
    'parameters': {
      for (final entry in parameters.entries)
        // A parameter sitting at its default with no keys says nothing.
        if (entry.value.value != _specDefault(kind, entry.key) ||
            entry.value.track.isNotEmpty)
          entry.key: entry.value.toJson(),
    },
  };

  factory LayerEffect.fromJson(Map<String, dynamic> json) {
    final kind = EffectKind.fromJson(json['kind']);
    final rawParameters = json['parameters'] as Map<String, dynamic>? ?? {};
    // The constructor fills whatever the file left out.
    return LayerEffect(
      id: EffectId.fromJson(json['id'] as Map<String, dynamic>),
      kind: kind,
      enabled: json['enabled'] as bool? ?? true,
      parameters: {
        for (final entry in rawParameters.entries)
          entry.key: EffectParameter.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerEffect &&
          other.id == id &&
          other.kind == kind &&
          other.enabled == enabled &&
          mapEquals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    enabled,
    Object.hashAll([
      for (final entry in parameters.entries)
        Object.hash(entry.key, entry.value),
    ]),
  );

  @override
  String toString() =>
      'LayerEffect($kind, enabled: $enabled, parameters: $parameters)';
}

double _specDefault(EffectKind kind, String parameterId) =>
    effectParameterSpecOf(kind, parameterId)?.defaultValue ?? 0;

/// An effect with its parameters SAMPLED at one frame — what the composite
/// carries and what the caches compare. Values are in
/// [effectParametersOf]'s order, which is the only order anything builds
/// them in.
class ResolvedLayerEffect {
  ResolvedLayerEffect({required this.kind, required List<double> values})
    : values = List.unmodifiable(values);

  final EffectKind kind;
  final List<double> values;

  double parameter(String id) {
    final specs = effectParametersOf(kind);
    for (var index = 0; index < specs.length; index += 1) {
      if (specs[index].id == id) {
        return index < values.length
            ? values[index]
            : specs[index].defaultValue;
      }
    }
    return 0;
  }

  /// Whether this sample changes any pixel. An effect resolved to its
  /// defaults is dropped by the resolver, so nothing downstream ever pays
  /// for a filter that does nothing.
  bool get isNoOp {
    final specs = effectParametersOf(kind);
    for (
      var index = 0;
      index < specs.length && index < values.length;
      index++
    ) {
      if (values[index] != specs[index].defaultValue) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedLayerEffect &&
          other.kind == kind &&
          listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(values));

  @override
  String toString() => 'ResolvedLayerEffect($kind, $values)';
}

/// Samples [effects] at [frameIndex], dropping the disabled ones and the
/// ones that resolve to a no-op. An empty result is the overwhelmingly
/// common case and every consumer treats it as "no filter work at all".
List<ResolvedLayerEffect> resolveLayerEffectsAt({
  required List<LayerEffect> effects,
  required int frameIndex,
}) {
  if (effects.isEmpty) {
    return const [];
  }
  final resolved = <ResolvedLayerEffect>[];
  for (final effect in effects) {
    if (!effect.enabled) {
      continue;
    }
    final specs = effectParametersOf(effect.kind);
    final sample = ResolvedLayerEffect(
      kind: effect.kind,
      values: [
        for (final spec in specs)
          spec.clamp(effect.parameterOf(spec.id).resolveAt(frameIndex)),
      ],
    );
    if (sample.isNoOp) {
      continue;
    }
    resolved.add(sample);
  }
  return resolved.isEmpty ? const [] : List.unmodifiable(resolved);
}

/// Whether any of [effects] spreads pixels beyond their own coverage — the
/// blur question the folder-buffer decision and the dirty-bounds math ask.
bool resolvedEffectsSpreadPixels(List<ResolvedLayerEffect> effects) =>
    effects.any((effect) => effect.kind.spreadsPixels);
