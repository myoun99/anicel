import 'property_track.dart' show KeyExit, KeyValueSpace;
import 'transform_track.dart'
    show argbKeySpace, doubleKeySpace, menuKeySpace;

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

  /// One of the parameter's [EffectParameterSpec.choices] — the value is
  /// the number of the word, the lane a menu, its keys steps
  /// ([menuKeySpace]). 🗣️I-132-Q6 (유저 2026-10-27): 「레인 하나 — 값이
  /// 메뉴, 키프레임은 계단」 — AE's pop-up properties, a colour key's Key
  /// Operation the first.
  choice,

  /// An ARGB colour — keyed as an SE name tag's inks are, in their key space
  /// ([argbKeySpace]) and their type: its keys are [LayerEffect.colors]',
  /// not numbers in [LayerEffect.parameters], so a paste pairs them with a
  /// colour's alone (`laneKeysSpliced` asks the keys' type). The lane is
  /// the shared colour swatch, and unkeyed the spec's default — a colour
  /// has no static value, as the ink never had.
  ///
  /// 🗣️I-132-Q10 (유저 2026-10-27): 「합친다 — 키 색상 = 색 레인 하나(셀
  /// 번호 · 이름표 잉크와 같은 컬러 팝오버)」 · 「ae 기준으로 맞춤」 — and
  /// F-477 (10-26) before it, for the cel number's: 「쓸데없이 빨강파랑초록
  /// 나누지말고」.
  color,

  /// On or off — AE's checkbox, whose value is 1 or 0 to a script (Adobe's
  /// community, read 2026-10-28) as a menu's is the number of its word. So
  /// it is a number here too: its keys step ([menuKeySpace]) and pair with
  /// a number's when pasted, as a menu's do. The lane is a flag's ring —
  /// the value cell IS the control, a tap flips it (F-22).
  flag,

  /// A point on the row's paper — keyed as a transform's Position is, in
  /// its lane's own words: its keys are [LayerEffect.points]', a track
  /// whose Position alone is keyed, so it keys, walks a path, takes a
  /// value, resets and names as Position does, and the canvas places it
  /// with a cross. Unkeyed it rests where a row does: the paper's middle.
  ///
  /// 🗣️I-132-Q12 b (유저 2026-10-28): 「효과 매개변수에 「점」 종류를 새로」 —
  /// a point of each effect's own (a radial blur's centre, a lens flare's
  /// later), where a cel number's stand is the picture it draws.
  point,

  /// Another row of the effect's cut, or none — no number and NO KEYS: its
  /// row is [LayerEffect.layers]', the one value at every frame. The lane
  /// is a menu, as a [choice]'s, of none and the cut's rows by name.
  ///
  /// 🗣️I-132-Q16 a (유저 2026-10-28): 「「레이어」는 같은 컷의 행을 고르는
  /// 메뉴(없음 + 행 이름들, 키 없음)」 — a camera lens blur's blur map the
  /// first. A row that is not the cut's — deleted, or an effect pasted
  /// into another cut — reads as none, as a dangling attach does
  /// (`attachedBaseOf`).
  layer,
}

/// One word of a menu parameter ([EffectParameterUnit.choice]).
class EffectChoice {
  const EffectChoice({
    required this.id,
    required this.label,
    this.ownWords = false,
  });

  /// What the word's strings are keyed by (`effectChoice.<id>`).
  final String id;

  /// The English word, the one a table without it reads.
  final String label;

  /// Whether [label] is its maker's own word, which no table translates —
  /// a plugin's (`FxPluginDescription`): its ids are the plugin's to pick,
  /// and one that is also an id of the app's would read the app's word.
  final bool ownWords;
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
    required double maximum,
    this.unit = EffectParameterUnit.number,
    this.ownWords = false,
  }) : assert(
         unit != EffectParameterUnit.choice &&
             unit != EffectParameterUnit.color &&
             unit != EffectParameterUnit.flag &&
             unit != EffectParameterUnit.point &&
             unit != EffectParameterUnit.layer,
         'A menu is EffectParameterSpec.choice, a colour '
         'EffectParameterSpec.color, a flag EffectParameterSpec.flag, a '
         'point EffectParameterSpec.point and a row EffectParameterSpec.layer '
         '— none has a range of its own.',
       ),
       _maximum = maximum,
       choices = const [];

  /// A menu of [choices], the word [defaultValue] counts to — the first
  /// unless it says — chosen until a key or a value says otherwise.
  const EffectParameterSpec.choice({
    required this.id,
    required this.label,
    required this.choices,
    int defaultValue = 0,
    this.ownWords = false,
  }) : defaultValue = defaultValue + 0.0,
       minimum = 0,
       _maximum = null,
       unit = EffectParameterUnit.choice;

  /// A colour ([EffectParameterUnit.color]), [defaultValue] until a key or a
  /// value says otherwise — any ARGB there is.
  const EffectParameterSpec.color({
    required this.id,
    required this.label,
    required int defaultValue,
    this.ownWords = false,
  }) : defaultValue = defaultValue + 0.0,
       minimum = 0,
       _maximum = 0xFFFFFFFF + 0.0,
       unit = EffectParameterUnit.color,
       choices = const [];

  /// A flag ([EffectParameterUnit.flag]), off until a key or a value says
  /// otherwise — or on, where a plugin's checkbox starts on
  /// (`FxPluginDescription`): its default is the plugin's to say.
  const EffectParameterSpec.flag({
    required this.id,
    required this.label,
    bool on = false,
    this.ownWords = false,
  }) : defaultValue = on ? 1 : 0,
       minimum = 0,
       _maximum = 1,
       unit = EffectParameterUnit.flag,
       choices = const [];

  /// A point ([EffectParameterUnit.point]): no number at all — its keys
  /// are [LayerEffect.points]'.
  const EffectParameterSpec.point({
    required this.id,
    required this.label,
    this.ownWords = false,
  }) : defaultValue = 0,
       minimum = 0,
       _maximum = 0,
       unit = EffectParameterUnit.point,
       choices = const [];

  /// A row of the effect's cut ([EffectParameterUnit.layer]): no number and
  /// no keys — its row is [LayerEffect.layers]', none until one is picked.
  const EffectParameterSpec.layer({
    required this.id,
    required this.label,
    this.ownWords = false,
  }) : defaultValue = 0,
       minimum = 0,
       _maximum = 0,
       unit = EffectParameterUnit.layer,
       choices = const [];

  final String id;
  final String label;
  final double defaultValue;
  final double minimum;
  final double? _maximum;
  final EffectParameterUnit unit;

  /// Whether [label] is its maker's own word, which no table translates
  /// ([EffectChoice.ownWords]) — a plugin's parameter.
  final bool ownWords;

  /// The words a menu parameter holds one of; empty for a number.
  final List<EffectChoice> choices;

  /// The largest value — a menu's last word.
  double get maximum => _maximum ?? (choices.length - 1).toDouble();

  /// Whether the value steps from key to key: nothing lies between two of a
  /// menu's words, nor between on and off.
  bool get _steps =>
      unit == EffectParameterUnit.choice || unit == EffectParameterUnit.flag;

  /// How the value walks between two keys: a menu and a flag step, a number
  /// lerps. A colour's keys are not numbers, and walk in [argbKeySpace].
  KeyValueSpace<double> get keySpace {
    assert(
      unit != EffectParameterUnit.color &&
          unit != EffectParameterUnit.point &&
          unit != EffectParameterUnit.layer,
      'A colour keys in argbKeySpace, over LayerEffect.colors, a point as a '
      'Position does, over LayerEffect.points, and a row not at all.',
    );
    return _steps ? menuKeySpace : doubleKeySpace;
  }

  /// How a key made on this lane leaves — a step's holds, so its mark says
  /// the step [keySpace] takes; null where a key leaves as it always has.
  KeyExit? get keyExit => _steps ? KeyExit.hold : null;

  double clamp(double value) => value.clamp(minimum, maximum).toDouble();
}

/// Whether a flag's [value] is on ([EffectParameterUnit.flag]): the nearer
/// of 0 and 1, as a menu reads the nearer of its words — a number pasted on
/// is either.
bool effectFlagIsOn(double value) => value >= 0.5;
