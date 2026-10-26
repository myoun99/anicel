import '../core/collection_equality.dart';
import 'canvas_size.dart';
import 'property_track.dart';
import 'string_id.dart';
import 'transform_track.dart'
    show
        TransformNamedChanges,
        TransformPose,
        TransformPropertyId,
        TransformTrack,
        argbKeySpace,
        doubleKeySpace,
        layerIdentityPose,
        transformLaneOf,
        transformNamedKeyChanges,
        transformPropertyOfLaneId,
        transformTrackWithNamedKeys;

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
/// The COLOR KEYS (I-8) keep that premise by running on the CPU over the
/// cel's own tile bytes instead — see [runsOnSourcePixels]. A threshold
/// comparison is not linear, so no color matrix can express it; the two
/// ways out were a fragment shader or a CPU pass, and 유저 2026-08-27 chose
/// the CPU: *「거기가 아프면 셰이더가 답이 아니고 cpu에서 더 개선하는 방향을
/// 찾아야지. 정답은 cpu로 보이니까」*. ⛔A later round finding the CPU pass
/// slow must make the CPU pass faster — reaching for a GPU path would put a
/// SECOND answer under one effect (AE ships both and documents that their
/// results differ, which is the thing this list exists to avoid).
///
/// Levels/curves and glow are the natural next entries; both need a lookup
/// table or a second pass, which is a later slice — not a different model.
enum EffectKind {
  brightnessContrast('brightnessContrast'),
  hueSaturation('hueSaturation'),
  blur('blur'),

  /// Erase every pixel whose color is within [tolerance] of the key color.
  deleteColor('deleteColor'),

  /// Erase every pixel whose color is NOT within [tolerance] of the key
  /// color — the same comparison with the answer inverted, which is why
  /// the two share [colorKeyParameterSpecs] rather than repeating it.
  keepColor('keepColor'),

  /// The CEL NUMBER (I-65): the row's name and its drawing's, in letters
  /// laid over the row's picture — 「A1」 — where [LayerEffect.stand] puts
  /// them ([drawsItsOwnPicture]).
  ///
  /// 🗣️유저 08-07: 「종이에 매번 셀번호 적는 게 귀찮아서 … 납품 셀에도 셀번호
  /// 적는 거야. 그래서 fx 로 하는 거고」 · 「체인 위치 고정 반대 — 블러 걸고
  /// 싶은 상황을 막는 제한」: a link of the chain like any other, so what
  /// follows it reads the letters too. 10-24 (I-65-Q1 a): 「레이어 이름 + 셀
  /// 번호(A1) — 이름 없는 그림은 A●」 — ↩️「A○」 since F-469 (기본마크 = 마크1).
  celNumber('celNumber');

  const EffectKind(this.jsonValue);

  final String jsonValue;

  /// The English menu/lane label — the vocabulary artists already read in
  /// AE and Photoshop.
  ///
  /// Japanese followed Clip Studio's terms (user rule 07-22: ja localized
  /// first; every other language keeps the shared English vocabulary artists
  /// already read — the exact rule the blend names followed). ↩️Every
  /// language has its own words now (유저 2026-09-15,
  /// blend-mode-names-language-Q1: 「블렌드 모드도 모든 언어로 번역」, which
  /// reversed that rule for every name a model carries), keyed by
  /// [jsonValue] in the string tables — `EffectKindWords` in
  /// `ui/text/model_vocabulary.dart`, which a model cannot import.
  String get label => switch (this) {
    EffectKind.brightnessContrast => 'Brightness & Contrast',
    EffectKind.hueSaturation => 'Hue/Saturation',
    EffectKind.blur => 'Blur',
    EffectKind.deleteColor => 'Delete Color',
    EffectKind.keepColor => 'Keep Color',
    EffectKind.celNumber => 'Cel Number',
  };

  /// Whether this kind SPREADS pixels outside their own coverage — the
  /// question the composite asks before deciding a folder must buffer, and
  /// the reason a blur can never be folded into a member's own draw.
  bool get spreadsPixels => this == EffectKind.blur;

  /// Whether this kind is computed over the SOURCE pixels — the cel's own
  /// tile bytes, before anything is drawn — rather than over what the
  /// composite has already painted.
  ///
  /// 🚨THIS IS A SPLIT POINT, NOT A GATE. A threshold comparison has no
  /// colour-matrix form, so a colour key at the HEAD of a chain runs as a
  /// CPU pass over the cel surface (`celSurfaceWithSourceEffects`) — that is
  /// what keeps the fx and the destructive button in exact agreement, since
  /// only the CPU sees the cel's own straight bytes.
  ///
  /// ⛔IT NO LONGER DECIDES WHERE A KIND MAY BE OFFERED. A gate called
  /// `effectKindsFor` used to hide these kinds wherever the input was not
  /// cel bytes; a folder keys the picture it composed now, through a
  /// fragment shader proven identical to this pass. `splitSourceEffects`
  /// reads this to find the leading run and nothing else does.
  bool get runsOnSourcePixels =>
      this == EffectKind.deleteColor || this == EffectKind.keepColor;

  /// Whether this kind DRAWS a picture of its own over the row's — the cel
  /// number's letters — rather than filtering the picture it is handed. Such
  /// a link is never a no-op ([ResolvedLayerEffect.isNoOp]: the letters are
  /// what it does), splits the chain where it stands (`celNumberedRow`) and
  /// stands where its [LayerEffect.stand] puts it.
  ///
  /// ⚠️Only a row whose drawings carry cel numbers takes one — the letters
  /// print that number (`LayerKind.numbersItsDrawings`: the same fact the
  /// auto naming reads, the kinds whose drawings are named by number).
  bool get drawsItsOwnPicture => this == EffectKind.celNumber;

  /// Whether an output that keeps only the BASIC fx keeps this kind
  /// (`ExportLayerFx.basic`, `layerAsOutput`).
  ///
  /// 🗣️I-65-Q3 (유저 2026-10-25): 「기본만 켬은 지금까지 말햇던 셀번호나
  /// 참조fx같은것만 키고 트랜스폼 포함해서 나머지 끄는것」. The reference fx is
  /// the row's, not a link of this chain ([Layer.mediaReference]).
  bool get isBasic => this == EffectKind.celNumber;

  /// Whether only the row that carries this link wears it — an attach row
  /// wears its base's chain short of it (`chainWornBy`).
  ///
  /// 🗣️I-65-Q4 (유저 2026-10-25): 「fx 를 단 행만 적는다 — 어태치는 번호 없이
  /// 나머지 fx 만 입는다」.
  bool get staysOnItsRow => this == EffectKind.celNumber;

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
  EffectKind.deleteColor: colorKeyParameterSpecs,
  EffectKind.keepColor: colorKeyParameterSpecs,
  // Where the letters stand, how big and in what colour are the effect's
  // [LayerEffect.stand] and [LayerEffect.ink], not parameters.
  EffectKind.celNumber: [],
};

/// The color keys' parameters — ONE list for both kinds, because erase and
/// keep are the same comparison with the answer inverted. Two copies would
/// be two places to add the next knob to.
///
/// 유저 2026-08-27 named the shape: *「블러 3개 있는것처럼 새로운 fx를
/// 만들잔거야」* — a color is three of the `double` parameters the lane
/// substrate already animates, not a new parameter TYPE. Keying the color
/// itself therefore comes out keyframable for free.
const List<EffectParameterSpec> colorKeyParameterSpecs = [
  // 0…255, the byte range the eyedropper and the surface both speak. ⛔NOT
  // 0…100: a key color typed from a picked pixel has to round-trip exactly,
  // and a percentage cannot say 137.
  EffectParameterSpec(
    id: 'keyRed',
    label: 'Key Red',
    defaultValue: 0,
    minimum: 0,
    maximum: 255,
  ),
  EffectParameterSpec(
    id: 'keyGreen',
    label: 'Key Green',
    defaultValue: 0,
    minimum: 0,
    maximum: 255,
  ),
  EffectParameterSpec(
    id: 'keyBlue',
    label: 'Key Blue',
    defaultValue: 0,
    minimum: 0,
    maximum: 255,
  ),
  // How far a pixel may sit from the key color and still count as it —
  // the largest single-channel difference, in bytes. 0 means exact.
  EffectParameterSpec(
    id: 'tolerance',
    label: 'Tolerance',
    defaultValue: 0,
    minimum: 0,
    maximum: 255,
  ),

  // 🚨AMOUNT EXISTS SO THAT "ADD EFFECT" CHANGES NOTHING, and it defaults
  // to 0 for that reason alone.
  //
  // [LayerEffect.defaults] promises an effect you just added does nothing
  // until you touch a value, and [ResolvedLayerEffect.isNoOp] keeps that
  // promise by dropping a chain entry whose every value is its default.
  // Every OTHER kind gets this free — brightness 0 and blur 0 are already
  // identities. A color key has no such value: some color is always the
  // key, so at Amount 100 a freshly added "erase" would delete every black
  // pixel (i.e. the line art) the moment it appeared.
  //
  // It is also the honest mix control. ⛔It must fold into the ONE pixel
  // pass, never be drawn as a second layer over the first
  // ([[derived-cel-projection-pattern]] rule 6: a two-pass mix accumulates
  // alpha, so 128 comes back as 160).
  EffectParameterSpec(
    id: 'amount',
    label: 'Amount',
    defaultValue: 0,
    minimum: 0,
    maximum: 100,
  ),
];

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
  double resolveAt(int frameIndex) => resolveAtTime(frameIndex.toDouble());

  /// [resolveAt] at a [time] between frames as well — a header graph's
  /// curve (I-89 ③).
  double resolveAtTime(double time) => track.resolveAtTime(
    time: time,
    orElse: () => value,
    space: doubleKeySpace,
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
        (value) => (value! as num).toDouble(),
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
/// draw (`canvas.save()` + `applyLayerPlacement`) while the effect
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
  ///
  /// [stand] and [ink] are normalized the same way: a kind that draws no
  /// picture of its own holds neither, whatever it was handed.
  LayerEffect({
    required this.id,
    required this.kind,
    this.enabled = true,
    Map<String, EffectParameter>? parameters,
    TransformTrack? stand,
    PropertyTrack<int>? ink,
  }) : parameters = Map.unmodifiable({
         for (final spec in effectParametersOf(kind))
           spec.id:
               parameters?[spec.id] ??
               EffectParameter(value: spec.defaultValue),
       }),
       stand = kind.drawsItsOwnPicture && stand != null
           ? stand
           : TransformTrack.empty(),
       ink = kind.drawsItsOwnPicture && ink != null
           ? ink
           : PropertyTrack<int>.empty();

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

  /// Where the picture a kind that draws its own ([EffectKind
  /// .drawsItsOwnPicture]) stands on the row's paper, and how big — the KEYS
  /// of its Position and Scale, in the transform lanes' own words, as the
  /// reference fx keeps its file's (`MediaReference.fx`). Unkeyed, it stands
  /// where a row does at rest: the paper's middle, at its size
  /// ([effectStandPose]). Empty for every other kind.
  ///
  /// 🗣️I-65-Q2 메모 (유저 2026-10-24): 「셀번호 fx 자체적으로 위치/크기값
  /// 구현. 트랜스폼에 있는거처럼 위치/비율 두개 키. 공용화된거 사용하면서」 ·
  /// 08-07: 「위치는 기본값으로 — 기본 트랜스폼 fx 의 위치 기준, 늘 하던 대로
  /// 공통된 거 사용」.
  final TransformTrack stand;

  /// The colour a kind that draws its own picture draws it in — the KEYS of
  /// ONE colour lane, as an SE row's name tag keys its name's ink
  /// (`SeNameTagTrack.nameInk`), read in the same key space
  /// ([argbKeySpace]). Unkeyed, the text tool's own black
  /// ([effectInkAtRest]). Empty for every other kind.
  ///
  /// 🗣️F-477 (유저 2026-10-26): 「se행의 이름표fx의 이름 잉크같은것처럼 색
  /// 컬러팝오버로 고르는거 그대로 사용하라고. 쓸데없이 빨강파랑초록
  /// 나누지말고」. ↩️It was three number lanes, Red · Green · Blue — the
  /// colour keys' shape ([colorKeyParameterSpecs]), which I-65-Q1's 「색 키
  /// 고르는것」 was read as; nobody asked for it.
  final PropertyTrack<int> ink;

  /// Whether lane [lane] is this effect's [ink].
  bool inksOn(String lane) => kind.drawsItsOwnPicture && lane == effectInkLane;

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
    TransformTrack? stand,
    PropertyTrack<int>? ink,
  }) {
    return LayerEffect(
      id: id,
      kind: kind ?? this.kind,
      enabled: enabled ?? this.enabled,
      parameters: parameters ?? this.parameters,
      stand: stand ?? this.stand,
      ink: ink ?? this.ink,
    );
  }

  /// [parameters] with one entry replaced — the shape every key/value edit
  /// commits.
  LayerEffect withParameter(String parameterId, EffectParameter parameter) {
    return copyWith(parameters: {...parameters, parameterId: parameter});
  }

  /// The property of [stand] lane [lane] is — a stand lane, by the transform
  /// lane's id ([effectStandLanes]) — on a kind that draws its own picture;
  /// null for every other lane: a parameter's.
  TransformPropertyId? standLaneOf(String lane) =>
      kind.drawsItsOwnPicture && effectStandLanes.contains(lane)
      ? transformPropertyOfLaneId(lane)
      : null;

  /// The keys lane [lane] of this effect holds — a parameter's by its id,
  /// a stand lane's ([standLaneOf]), the [ink]'s — read without knowing
  /// their value type; null for a lane the effect has not.
  PropertyTrack<Object?>? laneTrack(String lane) => switch (standLaneOf(lane)) {
    final property? => transformLaneOf(stand, property),
    null when inksOn(lane) => ink,
    null => parameters[lane]?.track,
  };

  /// Every lane of this effect, in the order its rows show them: where it
  /// stands first ([effectStandLanes]), as a transform's lanes lead, and
  /// its [ink], then its parameters.
  List<String> get lanes => [
    if (kind.drawsItsOwnPicture) ...[...effectStandLanes, effectInkLane],
    for (final spec in effectParametersOf(kind)) spec.id,
  ];

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
    if (stand.isNotEmpty) 'stand': stand.toJson(),
    if (ink.isNotEmpty) 'ink': ink.toJson((value) => value),
  };

  factory LayerEffect.fromJson(Map<String, dynamic> json) {
    final kind = EffectKind.fromJson(json['kind']);
    final rawParameters = json['parameters'] as Map<String, dynamic>? ?? {};
    final stand = json['stand'] as Map<String, dynamic>?;
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
      stand: stand == null ? null : TransformTrack.fromJson(stand),
      ink: PropertyTrack.fromJson(
        json['ink'] as List?,
        (value) => (value! as num).toInt(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerEffect &&
          other.id == id &&
          other.kind == kind &&
          other.enabled == enabled &&
          mapEquals(other.parameters, parameters) &&
          other.stand == stand &&
          other.ink == ink;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    enabled,
    Object.hashAll([
      for (final entry in parameters.entries)
        Object.hash(entry.key, entry.value),
    ]),
    stand,
    ink,
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
  ResolvedLayerEffect({
    required this.kind,
    required List<double> values,
    this.stand,
    this.ink,
  }) : values = List.unmodifiable(values);

  final EffectKind kind;
  final List<double> values;

  /// Where a kind that draws its own picture stands it at this frame
  /// ([LayerEffect.stand] sampled); null for every other kind.
  final EffectStand? stand;

  /// The ARGB colour a kind that draws its own picture draws it in at this
  /// frame ([LayerEffect.ink] sampled); null for every other kind.
  final int? ink;

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
  ///
  /// A kind that draws its own picture never is: drawing it is what it does.
  bool get isNoOp {
    if (kind.drawsItsOwnPicture) {
      return false;
    }
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
          listEquals(other.values, values) &&
          other.stand == stand &&
          other.ink == ink;

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(values), stand, ink);

  @override
  String toString() => 'ResolvedLayerEffect($kind, $values, $stand, $ink)';
}

/// Where the picture of an effect that draws its own stands at one time:
/// [LayerEffect.stand]'s keys and the time to read them at — a frame, or
/// between two. The pose they make is the transform's own resolve of them
/// on the row's paper ([effectStandPose]); the paper is not the effect's to
/// know. Unkeyed, every time is 0: one stand, whatever the frame.
typedef EffectStand = ({TransformTrack keys, double time});

/// The lanes of [LayerEffect.stand] an effect keys, by the ids the
/// transform's lanes go by: Position and Scale, in that order.
///
/// 🗣️I-65-Q2 메모: 「위치/비율 두개 키」 — no Rotation.
const List<String> effectStandLanes = ['position', 'scale'];

/// [stand] at [time] ([EffectStand]).
EffectStand effectStandAt(TransformTrack stand, double time) =>
    (keys: stand, time: stand.isEmpty ? 0 : time);

/// Where [stand] puts the picture on [paper]: its keys resolved as a
/// transform's are ([TransformTrack.resolveAtTime]) — unkeyed, where a row
/// stands at rest ([layerIdentityPose]): the paper's middle, at its size.
///
/// 🗣️08-07: 「위치는 기본값으로 — 기본 트랜스폼 fx 의 위치 기준, 늘 하던 대로
/// 공통된 거 사용」.
TransformPose effectStandPose(EffectStand stand, CanvasSize paper) =>
    stand.keys.resolveAtTime(
      time: stand.time,
      orElse: () => layerIdentityPose(paper),
    );

/// The lane of [LayerEffect.ink] — after where the effect stands, as an SE
/// name tag's inks follow its letters' size.
const String effectInkLane = 'ink';

/// What an unkeyed [LayerEffect.ink] draws in: opaque black, the text
/// tool's own ink (`TextLetterStyle.color`).
const int effectInkAtRest = 0xFF000000;

/// [ink] at [time], a frame or between two — unkeyed, [effectInkAtRest].
int effectInkAt(PropertyTrack<int> ink, double time) => ink.resolveAtTime(
  time: time,
  orElse: () => effectInkAtRest,
  space: argbKeySpace,
);

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
      stand: effect.kind.drawsItsOwnPicture
          ? effectStandAt(effect.stand, frameIndex.toDouble())
          : null,
      ink: effect.kind.drawsItsOwnPicture
          ? effectInkAt(effect.ink, frameIndex.toDouble())
          : null,
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

/// A NAMED key whose value moved in a chain edit — what the "same name,
/// same value" link has to carry to every other use of that name.
///
/// The naming space is one LANE of one effect: Blur A's radius and Blur
/// B's radius are different properties, so a name means nothing across
/// them. Linked rows share effect ids by construction, which is what lets
/// the same space span 겸용 cuts.
class NamedEffectKeyChange {
  const NamedEffectKeyChange({
    required this.effectId,
    required this.lane,
    required this.name,
    required this.held,
  });

  final EffectId effectId;

  /// The lane: a parameter's id, or one where the effect stands
  /// ([LayerEffect.standLaneOf]).
  final String lane;
  final String name;

  /// The value and both sides, carried together (F-84 실기, 유저
  /// 2026-09-12: 「싹다링크해야하는데」) — a number on a parameter, a point
  /// where the effect stands.
  final NamedKeyValue<Object?> held;
}

/// The named keys whose VALUE differs between [before] and [after] — the
/// propagation a chain write starts.
List<NamedEffectKeyChange> namedEffectKeyChanges(
  List<LayerEffect> before,
  List<LayerEffect> after,
) {
  if (before.isEmpty || after.isEmpty) {
    return const [];
  }
  final previous = {for (final effect in before) effect.id: effect};
  final changes = <NamedEffectKeyChange>[];
  for (final effect in after) {
    final old = previous[effect.id];
    if (old == null) {
      continue;
    }
    void moved(String lane, Map<String, NamedKeyValue<Object?>> keys) {
      for (final MapEntry(key: name, value: held) in keys.entries) {
        changes.add(
          NamedEffectKeyChange(
            effectId: effect.id,
            lane: lane,
            name: name,
            held: held,
          ),
        );
      }
    }

    for (final entry in effect.parameters.entries) {
      final oldTrack = old.parameters[entry.key]?.track;
      if (oldTrack == null) {
        continue;
      }
      // What counts as "moved" is the LANE's predicate ([movedNamedKeys]),
      // not this loop's: an effect parameter and a transform lane are the
      // same kind of thing to the link, and deciding it twice is how the
      // two would drift.
      moved(entry.key, movedNamedKeys(oldTrack, entry.value.track));
    }
    // Where it stands is read as a transform's keys are, by the
    // transform's own reading of them.
    final stand = transformNamedKeyChanges(old.stand, effect.stand);
    moved('position', stand.position);
    moved('scale', stand.scale);
    moved(effectInkLane, movedNamedKeys(old.ink, effect.ink));
  }
  return changes;
}

/// The key [name] ALREADY holds in [effects], on one effect's one lane —
/// null when the name is free there.
///
/// This is the rename's pull: a key joining an existing name takes that
/// name's value rather than imposing its own. Callers ask it across the
/// whole naming space (this row AND its 겸용 siblings, which share effect
/// ids), so a free name here can still be taken next door.
PropertyKey<Object?>? namedEffectKey(
  List<LayerEffect> effects, {
  required EffectId effectId,
  required String lane,
  required String name,
  Set<int> excludeFrames = const {},
}) {
  for (final effect in effects) {
    if (effect.id == effectId) {
      return effect
          .laneTrack(lane)
          ?.keyForName(name, excludeFrames: excludeFrames);
    }
  }
  return null;
}

/// [effectId]'s [parameterId] in [effects], resolved at [frameIndex] — 0 when
/// the chain holds no such effect. The value a parameter lane shows and a key
/// freezes, whichever row's chain it is: a layer's or a track's, on either
/// panel (F-101 found the loop written three times).
double effectParameterValueAt(
  List<LayerEffect> effects,
  EffectId effectId,
  String parameterId,
  int frameIndex,
) => effectParameterValueAtTime(
  effects,
  effectId,
  parameterId,
  frameIndex.toDouble(),
);

/// [effectParameterValueAt] at a [time] between frames as well (I-89 ③).
double effectParameterValueAtTime(
  List<LayerEffect> effects,
  EffectId effectId,
  String parameterId,
  double time,
) {
  for (final effect in effects) {
    if (effect.id == effectId) {
      return effect.parameterOf(parameterId).resolveAtTime(time);
    }
  }
  return 0;
}

/// [effects] with every key carrying a change's name — on that change's own
/// lane — set to its value AND type. The other half of the link.
List<LayerEffect> effectsWithNamedValues(
  List<LayerEffect> effects,
  List<NamedEffectKeyChange> changes,
) {
  if (changes.isEmpty || effects.isEmpty) {
    return effects;
  }
  var result = effects;
  for (final change in changes) {
    final index = result.indexWhere((effect) => effect.id == change.effectId);
    if (index == -1) {
      continue;
    }
    final effect = result[index];
    final next = _withNamedValue(effect, change);
    if (next == null || next == effect) {
      continue;
    }
    result = [...result]..[index] = next;
  }
  return result;
}

/// [effect] with [change]'s name set on its lane — null where the effect
/// has no such lane. Where it stands takes the name as a transform's keys
/// do ([transformTrackWithNamedKeys]).
LayerEffect? _withNamedValue(
  LayerEffect effect,
  NamedEffectKeyChange change,
) {
  final named = {change.name: change.held};
  if (effect.inksOn(change.lane)) {
    return effect.copyWith(ink: effect.ink.withNamedKeys(named.cast()));
  }
  switch (effect.standLaneOf(change.lane)) {
    case TransformPropertyId.position:
      return effect.copyWith(
        stand: transformTrackWithNamedKeys(
          effect.stand,
          TransformNamedChanges(position: named.cast()),
        ),
      );
    case TransformPropertyId.scale:
      return effect.copyWith(
        stand: transformTrackWithNamedKeys(
          effect.stand,
          TransformNamedChanges(scale: named.cast()),
        ),
      );
    case _:
      final parameter = effect.parameters[change.lane];
      if (parameter == null) {
        return null;
      }
      return effect.withParameter(
        change.lane,
        EffectParameter(
          value: parameter.value,
          track: parameter.track.withNamedKeys(named.cast()),
        ),
      );
  }
}

/// [shape]'s chain STRUCTURE — which effects, in what order, each on or
/// off — laid over [onto]'s own parameter values and keyframe tracks.
///
/// This is what a 겸용 mirror writes into a sibling: which effects a row
/// carries is shared structure, but their numbers are lane content and
/// stay per-use ("존재는 공유, 내용은 각자"). Copying the chain verbatim
/// instead would wipe the sibling's keyframes, which is the whole reason
/// this merge exists.
///
/// Effects are matched by [LayerEffect.id] — linked rows are created by
/// copying, so a shared effect carries the same id in every use site. An
/// id present only in [shape] is genuinely new and arrives with its
/// defaults; one only in [onto] was removed and drops out.
List<LayerEffect> effectChainWithSharedShape(
  List<LayerEffect> shape, {
  required List<LayerEffect> onto,
}) {
  if (onto.isEmpty) {
    return shape;
  }
  final kept = {for (final effect in onto) effect.id: effect};
  return [
    for (final effect in shape)
      switch (kept[effect.id]) {
        // New here, or the id was reused for a different effect kind:
        // take the incoming one whole.
        null => effect,
        final existing when existing.kind != effect.kind => effect,
        // Same effect: keep this cut's numbers, take the shared switch.
        final existing => existing.copyWith(enabled: effect.enabled),
      },
  ];
}

/// Whether [a] and [b] are chains of one SHAPE ([effectChainWithSharedShape]
/// lays [b]'s over [a] as [a]): the same effects in the same order, each
/// switched the same way — whatever their numbers.
bool sameEffectChainShape(List<LayerEffect> a, List<LayerEffect> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    final (left, right) = (a[index], b[index]);
    if (left.id != right.id ||
        left.kind != right.kind ||
        left.enabled != right.enabled) {
      return false;
    }
  }
  return true;
}
