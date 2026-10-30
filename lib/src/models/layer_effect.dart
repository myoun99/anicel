import '../core/collection_equality.dart';
import 'canvas_point.dart';
import 'canvas_size.dart';
import 'effect_parameter_spec.dart';
import 'fx_plugin_description.dart';
import 'fx_plugin_run.dart';
import 'layer_id.dart';
import 'property_track.dart';
import 'string_id.dart';
import 'transform_track.dart'
    show
        TransformNamedChanges,
        TransformPose,
        TransformTrack,
        argbKeySpace,
        doubleKeySpace,
        layerIdentityPose,
        resolveAnchorTrackAtTime,
        transformLaneOf,
        transformNamedKeyChanges,
        transformPropertyOfLaneId,
        transformTrackWithNamedKeys;

// The specs are a file of their own so a plugin's description, which an
// effect keeps ([LayerEffect.plugin]), reads them without this one — the two
// would import each other (I-132, 2026-10-30).
export 'effect_parameter_spec.dart';

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
/// produce the same pixels. The directional blur is a box a fragment shader
/// draws, a raster at a time (`ShadedEffect`), on every one of those routes.
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
///
/// 🚨THE EFFECT-KIND CAPABILITY TABLE — `LayerKind`'s law (audit round 8):
/// every question the app asks about a kind is a COLUMN, and every kind
/// answers it in its own declaration as a REQUIRED named parameter, so a new
/// kind is a compile error until it has answered them all. 유저 I-132
/// (2026-10-26): 「fx 들 전체적으로 법 통일」 — a kind used to be answered in
/// five places (a label switch, `== EffectKind.x` tests, a parameter map,
/// two composite switches). ⛔TWO COLUMNS THAT MATCH TODAY ARE STILL TWO
/// COLUMNS: [drawsItsOwnPicture], [isBasic] and [staysOnItsRow] hold the
/// same trues and name three facts.
enum EffectKind {
  brightnessContrast(
    'brightnessContrast',
    label: 'Brightness & Contrast',
    parameters: [
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
    spreadsPixels: false,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),
  // 🗣️I-132-Q4 (유저 2026-10-27): 「이름 · 범위만 AE 에 맞추고 식은 지금대로」
  // — the names and ranges are AE's Hue/Saturation (Adobe's help, read
  // 2026-10-27: Master Hue −180…180, Master Saturation and Lightness
  // −100…100), the matrix is ours. The ids stay: they address lanes and
  // strings, and no one sees them.
  hueSaturation(
    'hueSaturation',
    label: 'Hue/Saturation',
    parameters: [
      EffectParameterSpec(
        id: 'hue',
        label: 'Master Hue',
        defaultValue: 0,
        minimum: -180,
        maximum: 180,
        unit: EffectParameterUnit.degrees,
      ),
      EffectParameterSpec(
        id: 'saturation',
        label: 'Master Saturation',
        defaultValue: 0,
        minimum: -100,
        maximum: 100,
      ),
      EffectParameterSpec(
        id: 'lightness',
        label: 'Master Lightness',
        defaultValue: 0,
        minimum: -100,
        maximum: 100,
      ),
    ],
    spreadsPixels: false,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),

  /// AE's Gaussian Blur: `blurriness` each way along its `blurDimensions`.
  ///
  /// 🗣️I-132-Q3 (유저 2026-10-27): 「가우시안 · 방향 · 방사형 · 카메라 렌즈」 —
  /// this blur, Blur Width and Height, was a Gaussian already, so it takes
  /// AE's name and items: one Blurriness and the menu of the dimensions it
  /// runs along, where two radii stood. Its math stays (🗣️I-132-Q4:
  /// 「식은 지금대로」) — Blurriness is the radius the width and height were.
  /// The range is ours: no help page gives AE's.
  blur(
    'blur',
    label: 'Gaussian Blur',
    parameters: [
      EffectParameterSpec(
        id: 'blurriness',
        label: 'Blurriness',
        defaultValue: 0,
        minimum: 0,
        maximum: 500,
        unit: EffectParameterUnit.pixels,
      ),
      EffectParameterSpec.choice(
        id: 'blurDimensions',
        label: 'Blur Dimensions',
        choices: [
          EffectChoice(
            id: 'horizontalAndVertical',
            label: 'Horizontal and Vertical',
          ),
          EffectChoice(id: 'horizontal', label: 'Horizontal'),
          EffectChoice(id: 'vertical', label: 'Vertical'),
        ],
      ),
      // Past the paper's edge the blur reads the edge's own pixels, and
      // what it draws stays on the paper — 🗣️I-132-Q14 (유저 2026-10-28):
      // the edge is the paper's (canvas's), on a layer and a folder alike,
      // AE's comp-sized solid and precomp; artwork on the pasteboard stays
      // out of sight while it is on. Off, as AE's is.
      EffectParameterSpec.flag(
        id: 'repeatEdgePixels',
        label: 'Repeat Edge Pixels',
      ),
    ],
    spreadsPixels: true,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    strength: 'blurriness',
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),

  /// Every pixel the average of the line through it — AE's Directional
  /// Blur, a box [blurLength] long (`directionalBlurPasses`).
  ///
  /// 🗣️I-132-Q3 (유저 2026-10-27): 「가우시안 · 방향 · 방사형 · 카메라 렌즈」,
  /// AE's names and items. ★DIRECTION READS AS AN ANGLE DIAL: 0° up,
  /// clockwise, so 0° blurs up and down — 🗣️I-132-Q8 (유저 2026-10-27):
  /// 「0° 에서 세로로 번진다」; no help page says it. Its help does say the
  /// blur goes both ways from a pixel, so 0° and 180° are one blur. The
  /// length's range is ours: no help page gives AE's.
  directionalBlur(
    'directionalBlur',
    label: 'Directional Blur',
    parameters: [
      EffectParameterSpec(
        id: 'direction',
        label: 'Direction',
        defaultValue: 0,
        minimum: -180,
        maximum: 180,
        unit: EffectParameterUnit.degrees,
      ),
      EffectParameterSpec(
        id: 'blurLength',
        label: 'Blur Length',
        defaultValue: 0,
        minimum: 0,
        maximum: 500,
        unit: EffectParameterUnit.pixels,
      ),
    ],
    spreadsPixels: true,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    strength: 'blurLength',
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),

  /// Every pixel the average of the arc through it about its `center`
  /// (Spin) or of the ray through it from there (Zoom) — AE's Radial Blur
  /// (`radialBlurPasses`).
  ///
  /// 🗣️I-132-Q3 (유저 2026-10-27): 「가우시안 · 방향 · 방사형 · 카메라 렌즈」,
  /// AE's items: Amount, Center, Type, and the antialiasing menu
  /// (🗣️I-132-Q13 a: 「메뉴를 둔다 — 드래프트는 표본을 줄여 빠르게」). The
  /// centre is a point of its own (🗣️I-132-Q12 b: 「효과 매개변수에 「점」
  /// 종류를 새로」). Adobe's help says Spin's Amount is degrees and Zoom's a
  /// length; the length's form is ours (🗣️I-132-Q4 「식은 지금대로」) — the
  /// streak a percent of the pixel's way from the centre — and so is the
  /// range: no help page gives AE's. The menu's words are ours
  /// (🗣️I-132-Q11 a), as the card asked them.
  radialBlur(
    'radialBlur',
    label: 'Radial Blur',
    parameters: [
      EffectParameterSpec(
        id: 'amount',
        label: 'Amount',
        defaultValue: 0,
        minimum: 0,
        maximum: 100,
      ),
      EffectParameterSpec.point(id: 'center', label: 'Center'),
      EffectParameterSpec.choice(
        id: 'type',
        label: 'Type',
        choices: [
          EffectChoice(id: 'spin', label: 'Spin'),
          EffectChoice(id: 'zoom', label: 'Zoom'),
        ],
      ),
      EffectParameterSpec.choice(
        id: 'antialiasing',
        label: 'Antialiasing',
        choices: [
          EffectChoice(id: 'best', label: 'Best'),
          EffectChoice(id: 'draft', label: 'Draft'),
        ],
      ),
    ],
    spreadsPixels: true,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    strength: 'amount',
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),

  /// Every pixel the mean of the pixels about it its iris covers — AE's
  /// Camera Lens Blur (`cameraLensBlurPasses`): a polygon of its Shape,
  /// Blur Radius out, rounded, squeezed and turned by the iris's
  /// properties, its light pushed out to its edge by the Diffraction
  /// Fringe.
  ///
  /// 🗣️I-132-Q3 (유저 2026-10-27): 「가우시안 · 방향 · 방사형 · 카메라 렌즈」,
  /// AE's names and items — Adobe's help (read 2026-10-28): a blur radius
  /// up to 500; Iris Properties Shape, Roundness, Aspect Ratio, Rotation
  /// and Diffraction Fringe, whose 100 is a natural halo and 500 all the
  /// blur's energy on the ring; Repeat Edge Pixels. 🗣️I-132-Q15 a: 「모든
  /// 모양을 정확히 — 행 누적합」. The iris's forms are ours (🗣️I-132-Q4 b),
  /// and so are the ranges the help does not give, and the shape's words
  /// (🗣️I-132-Q11 a). The Square begins it (🗣️I-132-Q19 a): AE's first
  /// word is a Fast Rectangle, which drawn exact is the Square.
  ///
  /// Its Highlight and Use Linear Working Space, as the help has them: the
  /// gain boosts what lies past the threshold, the saturation keeps the
  /// boost's colour, and the light is read linear (`lens_light.glsl`, the
  /// forms ours). ⚠️The help gives no range or first value for the three:
  /// a threshold of 0…255 that begins at 255 and a gain and saturation of
  /// 0…100 that begin at 0 are the ones an Adobe community post's SDK code
  /// reads them with (2026-10-28) — the help's own threshold of 1, which
  /// leaves no highlight, is the 255 of an 8-bit picture.
  ///
  /// Its Blur Map, as the help has it: a Layer whose Channel sets each
  /// pixel's radius, in focus at its Blur Focal Distance, inverted by
  /// Invert Blur Map. 🗣️I-132-Q16 a: the layer is a row of the cut
  /// ([EffectParameterUnit.layer]). 🗣️I-132-Q21 a: it is read where the
  /// row shows — so no Placement, the help's way to set it over the
  /// picture. 🗣️I-132-Q22 a: one level — a map's own blur map is not read.
  /// 🗣️I-132-Q23 a: 「꺼도 맵으로 읽는다」 — its row's eye does not hide it.
  /// 🗣️I-132-Q24 b: 「넣는다 — 화면에 보이는 그대로」 — its opacity is in
  /// what is read.
  cameraLensBlur(
    'cameraLensBlur',
    label: 'Camera Lens Blur',
    parameters: [
      EffectParameterSpec(
        id: 'blurRadius',
        label: 'Blur Radius',
        defaultValue: 0,
        minimum: 0,
        maximum: 500,
        unit: EffectParameterUnit.pixels,
      ),
      EffectParameterSpec.choice(
        id: 'irisShape',
        label: 'Shape',
        choices: [
          EffectChoice(id: 'triangle', label: 'Triangle'),
          EffectChoice(id: 'square', label: 'Square'),
          EffectChoice(id: 'pentagon', label: 'Pentagon'),
          EffectChoice(id: 'hexagon', label: 'Hexagon'),
          EffectChoice(id: 'heptagon', label: 'Heptagon'),
          EffectChoice(id: 'octagon', label: 'Octagon'),
          EffectChoice(id: 'nonagon', label: 'Nonagon'),
          EffectChoice(id: 'decagon', label: 'Decagon'),
        ],
        defaultValue: 1,
      ),
      EffectParameterSpec(
        id: 'irisRoundness',
        label: 'Roundness',
        defaultValue: 0,
        minimum: 0,
        maximum: 100,
      ),
      EffectParameterSpec(
        id: 'irisAspectRatio',
        label: 'Aspect Ratio',
        defaultValue: 1,
        minimum: 0.1,
        maximum: 10,
      ),
      EffectParameterSpec(
        id: 'irisRotation',
        label: 'Rotation',
        defaultValue: 0,
        minimum: -180,
        maximum: 180,
        unit: EffectParameterUnit.degrees,
      ),
      EffectParameterSpec(
        id: 'irisDiffractionFringe',
        label: 'Diffraction Fringe',
        defaultValue: 0,
        minimum: 0,
        maximum: 500,
      ),
      EffectParameterSpec.layer(id: 'blurMapLayer', label: 'Blur Map Layer'),
      EffectParameterSpec.choice(
        id: 'blurMapChannel',
        label: 'Blur Map Channel',
        choices: [
          EffectChoice(id: 'luminance', label: 'Luminance'),
          EffectChoice(id: 'red', label: 'Red'),
          EffectChoice(id: 'green', label: 'Green'),
          EffectChoice(id: 'blue', label: 'Blue'),
          EffectChoice(id: 'alpha', label: 'Alpha'),
        ],
      ),
      EffectParameterSpec(
        id: 'blurFocalDistance',
        label: 'Blur Focal Distance',
        defaultValue: 0,
        minimum: 0,
        maximum: 255,
      ),
      EffectParameterSpec.flag(id: 'invertBlurMap', label: 'Invert Blur Map'),
      EffectParameterSpec(
        id: 'highlightGain',
        label: 'Highlight Gain',
        defaultValue: 0,
        minimum: 0,
        maximum: 100,
      ),
      EffectParameterSpec(
        id: 'highlightThreshold',
        label: 'Highlight Threshold',
        defaultValue: 255,
        minimum: 0,
        maximum: 255,
      ),
      EffectParameterSpec(
        id: 'highlightSaturation',
        label: 'Highlight Saturation',
        defaultValue: 0,
        minimum: 0,
        maximum: 100,
      ),
      // The Gaussian's own (🗣️I-132-Q14 a): past the paper's edge the iris
      // reads the edge's pixels, and what it draws stays on the paper.
      EffectParameterSpec.flag(
        id: 'repeatEdgePixels',
        label: 'Repeat Edge Pixels',
      ),
      EffectParameterSpec.flag(
        id: 'useLinearWorkingSpace',
        label: 'Use Linear Working Space',
      ),
    ],
    spreadsPixels: true,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    strength: 'blurRadius',
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),

  /// THE colour key: its Key Operation erases every pixel within the
  /// tolerance of the key colour (Key Colors), or gives back what the keys
  /// before it erased of those (Keep Colors) — AE's Linear Color Key
  /// (`CelColorKey`).
  ///
  /// 🗣️I-132-Q2 (유저 2026-10-27): 「하나로 + AE 뜻」. ↩️Two kinds, Delete
  /// Color and Keep Color, the second erasing every pixel the key did NOT
  /// name — AE keeps a colour by keying it twice, all out and then the
  /// colour back.
  colorKey(
    'colorKey',
    label: 'Color Key',
    parameters: colorKeyParameterSpecs,
    spreadsPixels: false,
    runsOnSourcePixels: true,
    drawsItsOwnPicture: false,
    strength: 'amount',
    isBasic: false,
    staysOnItsRow: false,
    addedByItsKind: true,
    changesNothingAtItsDefaults: true,
  ),

  /// The CEL NUMBER (I-65): the row's name and its drawing's, in letters
  /// laid over the row's picture — 「A1」 — where [LayerEffect.stand] puts
  /// them ([drawsItsOwnPicture]).
  ///
  /// 🗣️유저 08-07: 「종이에 매번 셀번호 적는 게 귀찮아서 … 납품 셀에도 셀번호
  /// 적는 거야. 그래서 fx 로 하는 거고」 · 「체인 위치 고정 반대 — 블러 걸고
  /// 싶은 상황을 막는 제한」: a link of the chain like any other, so what
  /// follows it reads the letters too. 10-24 (I-65-Q1 a): 「레이어 이름 + 셀
  /// 번호(A1) — 이름 없는 그림은 A●」 — the mark the unnamed head wears,
  /// picked in Preferences ▸ Display since F-489 (● to begin with).
  /// ↩️「A○」 from F-469 (기본마크 = 마크1) to F-489.
  celNumber(
    'celNumber',
    label: 'Cel Number',
    // Where the letters stand and how big is the effect's
    // [LayerEffect.stand], not parameters.
    parameters: [
      // 🗣️F-477 (유저 2026-10-26): 「se행의 이름표fx의 이름 잉크같은것처럼
      // 색 컬러팝오버로 고르는거 그대로 사용하라고. 쓸데없이 빨강파랑초록
      // 나누지말고」 — ONE colour lane, unkeyed the text tool's own black
      // (`TextLetterStyle.color`). ↩️Three number lanes, Red · Green · Blue
      // — the colour keys' shape, which I-65-Q1's 「색 키 고르는것」 was read
      // as; nobody asked for it. ↩️Then `LayerEffect.ink`, a lane beside
      // the parameters, until the colour key's colour was one too
      // (I-132-Q10): one kind of lane now, keyed in [LayerEffect.colors].
      EffectParameterSpec.color(
        id: 'ink',
        label: 'Ink',
        defaultValue: 0xFF000000,
      ),
    ],
    spreadsPixels: false,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: true,
    isBasic: true,
    staysOnItsRow: true,
    addedByItsKind: true,
    changesNothingAtItsDefaults: false,
  ),

  /// A plugin's effect: its parameters, the words they go by and what it
  /// does to the pixels are the plugin's ([LayerEffect.plugin],
  /// anicel_fx_plugin.h) — ONE kind for every plugin, told apart by the
  /// description it keeps, so a plugin's lanes, keys and values are the
  /// app's own code (🗣️I-132-Q29).
  ///
  /// 🗣️I-132 (유저 2026-10-26): 「fx는 ae처럼 플러그인화. 즉 유저가
  /// 커스텀해서 fx추가할수있게」.
  plugin(
    'plugin',
    label: 'Plugin',
    parameters: [],
    // How far past its input it reads and draws is the plugin's to say
    // (`anicel_fx_reach`): a chain makes room for it as for a blur.
    spreadsPixels: true,
    runsOnSourcePixels: false,
    drawsItsOwnPicture: false,
    isBasic: false,
    staysOnItsRow: false,
    // Added as one of the plugins this device has, never as the kind alone.
    addedByItsKind: false,
    // Its defaults are the plugin's to mean — an inversion changes every
    // pixel at its first value.
    changesNothingAtItsDefaults: false,
  );

  const EffectKind(
    this.jsonValue, {
    required this.label,
    required this.parameters,
    required this.spreadsPixels,
    required this.runsOnSourcePixels,
    required this.drawsItsOwnPicture,
    required this.isBasic,
    required this.staysOnItsRow,
    required this.addedByItsKind,
    required this.changesNothingAtItsDefaults,
    this.strength,
  });

  final String jsonValue;

  /// The parameter at whose zero this kind changes no pixel, whatever its
  /// others say — a blur of no length, whichever way it points; a key of no
  /// amount — null for a kind that has none. A sample there is a no-op
  /// ([ResolvedLayerEffect.isNoOp]), dropped by the resolver, so nothing
  /// downstream pays for it: no step, no buffer grown past its input, no
  /// row read.
  final String? strength;

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
  final String label;

  /// The kind's parameters, in the order the lanes show them. The specs ARE
  /// the schema — the lane UI, the value parser, the JSON round-trip and the
  /// resolver all read this list instead of repeating a switch per effect.
  final List<EffectParameterSpec> parameters;

  /// Whether this kind SPREADS pixels outside their own coverage — the
  /// question the composite asks before deciding a folder must buffer, and
  /// the reason a blur can never be folded into a member's own draw.
  final bool spreadsPixels;

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
  final bool runsOnSourcePixels;

  /// Whether this kind DRAWS a picture of its own over the row's — the cel
  /// number's letters — rather than filtering the picture it is handed. Such
  /// a link is never a no-op ([ResolvedLayerEffect.isNoOp]: the letters are
  /// what it does), splits the chain where it stands (`celNumberedRow`) and
  /// stands where its [LayerEffect.stand] puts it.
  ///
  /// ⚠️Only a row whose drawings carry cel numbers takes one — the letters
  /// print that number (`LayerKind.numbersItsDrawings`: the same fact the
  /// auto naming reads, the kinds whose drawings are named by number).
  final bool drawsItsOwnPicture;

  /// Whether an output that keeps only the BASIC fx keeps this kind
  /// (`ExportLayerFx.basic`, `layerAsOutput`).
  ///
  /// 🗣️I-65-Q3 (유저 2026-10-25): 「기본만 켬은 지금까지 말햇던 셀번호나
  /// 참조fx같은것만 키고 트랜스폼 포함해서 나머지 끄는것」. The reference fx is
  /// the row's, not a link of this chain ([Layer.mediaReference]).
  final bool isBasic;

  /// Whether only the row that carries this link wears it — an attach row
  /// wears its base's chain short of it (`chainWornBy`).
  ///
  /// 🗣️I-65-Q4 (유저 2026-10-25): 「fx 를 단 행만 적는다 — 어태치는 번호 없이
  /// 나머지 fx 만 입는다」.
  final bool staysOnItsRow;

  /// Whether the kind ALONE is added — an entry of the Fx list and an action
  /// of its own. A plugin's effect is added as one of the plugins this
  /// device has (I-132), its description with it.
  final bool addedByItsKind;

  /// Whether a sample at its parameters' defaults changes no pixel — every
  /// kind of the app's own is built so («an effect you just added must
  /// change nothing until you touch a value», [LayerEffect.defaults]) but
  /// the cel number, whose letters are what it does, and a plugin's, whose
  /// defaults are the plugin's to mean ([ResolvedLayerEffect.isNoOp]).
  final bool changesNothingAtItsDefaults;

  /// The parameter [id] of this kind — null for an id it does not declare.
  EffectParameterSpec? parameterSpec(String id) => _specOf(parameters, id);

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

/// The kinds added as themselves ([EffectKind.addedByItsKind]), in their
/// order — the Fx list's own rows and the actions that press them.
final List<EffectKind> effectKindsAddedAlone = List.unmodifiable([
  for (final kind in EffectKind.values)
    if (kind.addedByItsKind) kind,
]);

/// The spec of [specs] whose id is [id] — null for none.
EffectParameterSpec? _specOf(List<EffectParameterSpec> specs, String id) {
  for (final spec in specs) {
    if (spec.id == id) {
      return spec;
    }
  }
  return null;
}

/// The colour key's parameters ([EffectKind.colorKey]).
///
/// 🗣️I-132-Q10 (유저 2026-10-27): its colour is ONE colour lane
/// ([EffectParameterUnit.color]) — 「ae 기준으로 맞춤. 대체 어느 기준으로
/// 빨강파랑초록 나눳는지 의문일정도」. ↩️Three number lanes, Key Red · Key
/// Green · Key Blue, from 유저 2026-08-27's *「블러 3개 있는것처럼 새로운 fx를
/// 만들잔거야」* read as 「a colour is three of the `double` parameters the
/// lane substrate already animates, not a new parameter TYPE」.
const List<EffectParameterSpec> colorKeyParameterSpecs = [
  // AE's Key Operation — a menu lane (I-132-Q6 a): what the key does to the
  // pixels it names. First, as AE's help sets it first (keying-effects,
  // read 2026-10-27: Key Operation, then Match Colors, then the colour);
  // the panel's own order the help does not give.
  EffectParameterSpec.choice(
    id: 'keyOperation',
    label: 'Key Operation',
    choices: [
      EffectChoice(id: 'keyColors', label: 'Key Colors'),
      EffectChoice(id: 'keepColors', label: 'Keep Colors'),
    ],
  ),
  // The bytes the eyedropper and the surface both speak, so a key colour
  // picked off a pixel round-trips exactly. Its alpha names nothing: a key
  // compares red, green and blue (`CelColorKey.matches`).
  EffectParameterSpec.color(
    id: 'keyColor',
    label: 'Key Color',
    defaultValue: 0xFF000000,
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
  /// static value otherwise, walking between keys as [space] does — a
  /// spec's own ([EffectParameterSpec.keySpace]): a menu steps.
  double resolveAt(
    int frameIndex, {
    KeyValueSpace<double> space = doubleKeySpace,
  }) => resolveAtTime(frameIndex.toDouble(), space: space);

  /// [resolveAt] at a [time] between frames as well — a header graph's
  /// curve (I-89 ③).
  double resolveAtTime(
    double time, {
    KeyValueSpace<double> space = doubleKeySpace,
  }) => track.resolveAtTime(
    time: time,
    orElse: () => value,
    space: space,
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
  /// [colors], [points], [layers] and [stand] are normalized the same way:
  /// a colour, a point or a row the kind declares is materialized (unkeyed,
  /// or none, where it was missing), and a kind that draws no picture of
  /// its own stands none, whatever it was handed.
  ///
  /// The specs are the [plugin]'s for a plugin's effect, which keeps one
  /// ([EffectKind.plugin]) — and the kind's own for every other, which keeps
  /// none, whatever it was handed.
  LayerEffect({
    required this.id,
    required this.kind,
    FxPluginDescription? plugin,
    this.enabled = true,
    Map<String, EffectParameter>? parameters,
    Map<String, PropertyTrack<int>>? colors,
    Map<String, TransformTrack>? points,
    Map<String, LayerId?>? layers,
    TransformTrack? stand,
  }) : plugin = kind == EffectKind.plugin
           ? ArgumentError.checkNotNull(plugin, 'plugin')
           : null,
       parameters = Map.unmodifiable({
         for (final spec in _specsOf(kind, plugin))
           if (spec.unit != EffectParameterUnit.color &&
               spec.unit != EffectParameterUnit.point &&
               spec.unit != EffectParameterUnit.layer)
             spec.id:
                 parameters?[spec.id] ??
                 EffectParameter(value: spec.defaultValue),
       }),
       colors = Map.unmodifiable({
         for (final spec in _specsOf(kind, plugin))
           if (spec.unit == EffectParameterUnit.color)
             spec.id: colors?[spec.id] ?? PropertyTrack<int>.empty(),
       }),
       points = Map.unmodifiable({
         for (final spec in _specsOf(kind, plugin))
           if (spec.unit == EffectParameterUnit.point)
             spec.id: points?[spec.id] ?? TransformTrack.empty(),
       }),
       layers = Map.unmodifiable({
         for (final spec in _specsOf(kind, plugin))
           if (spec.unit == EffectParameterUnit.layer)
             spec.id: layers?[spec.id],
       }),
       stand = kind.drawsItsOwnPicture && stand != null
           ? stand
           : TransformTrack.empty();

  /// A fresh effect of [kind] — of [plugin], for a plugin's — every
  /// parameter at its spec default: what "Add effect" creates. The plain
  /// constructor normalizes to exactly this; the name is here because the
  /// call sites read better.
  factory LayerEffect.defaults({
    required EffectId id,
    required EffectKind kind,
    FxPluginDescription? plugin,
  }) => LayerEffect(id: id, kind: kind, plugin: plugin);

  final EffectId id;
  final EffectKind kind;

  /// The plugin a plugin's effect ([EffectKind.plugin]) is of — its
  /// description as the plugin gave it, kept by the project so a machine
  /// without the plugin still shows its lanes, values and keys
  /// (🗣️I-132-Q28 「fx 줄은 남기고, 걸리지 않은 채 「플러그인 없음」으로
  /// 둔다」). Null for every other kind.
  final FxPluginDescription? plugin;

  /// Every parameter of this effect, in its order — the [plugin]'s, or the
  /// kind's own. ⛔Ask here, never [EffectKind.parameters]: a plugin's kind
  /// declares none.
  List<EffectParameterSpec> get specs => _specsOf(kind, plugin);

  /// The parameter [id] of this effect ([specs]) — null for an id it does
  /// not declare.
  EffectParameterSpec? specOf(String id) => _specOf(specs, id);

  /// Its English name ([labelOf]); the program's language reads
  /// `LayerEffectWords`.
  String get label => labelOf(kind, plugin);

  /// The English name of an effect of [kind] — of [plugin], for a plugin's:
  /// the plugin's own ([FxPluginDescription.name]).
  static String labelOf(EffectKind kind, FxPluginDescription? plugin) =>
      plugin?.name ?? kind.label;

  static List<EffectParameterSpec> _specsOf(
    EffectKind kind,
    FxPluginDescription? plugin,
  ) => kind == EffectKind.plugin ? plugin!.parameters : kind.parameters;

  /// The effect's own switch (AE's per-effect fx eyeball). A disabled
  /// effect resolves to nothing at all — it keeps its keys for later.
  final bool enabled;

  /// Parameter id → parameter, always the kind's FULL spec set of numbers
  /// (see the constructor) — its colours are [colors]. A parameter added to
  /// a spec later therefore appears at its default on old data, with no
  /// migration.
  final Map<String, EffectParameter> parameters;

  /// Colour id → the KEYS of that colour's ONE lane ([EffectParameterUnit
  /// .color]), every colour the kind declares: as an SE row's name tag keys
  /// its name's ink (`SeNameTagTrack.nameInk`), in the same key space
  /// ([argbKeySpace]) and type. Unkeyed, the spec's default ([effectColorAt]).
  final Map<String, PropertyTrack<int>> colors;

  /// Point id → the KEYS of that point's ONE lane ([EffectParameterUnit
  /// .point]), every point the kind declares: a transform's track whose
  /// Position alone is keyed — so the transform's own verbs key it, walk
  /// it and name it, as they do [stand]'s ([transformLaneAt]). Unkeyed,
  /// the paper's middle ([effectPointOnPaper]).
  final Map<String, TransformTrack> points;

  /// Row id → the row of the effect's cut that row parameter
  /// ([EffectParameterUnit.layer]) names, every row parameter the kind
  /// declares — null for none. No keys: one row at every frame.
  final Map<String, LayerId?> layers;

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

  /// The named parameter. Non-null for every id the kind declares (the
  /// constructor materializes them); an id from another kind answers a
  /// zero-valued placeholder rather than throwing, so a stale lane address
  /// cannot crash a paint.
  EffectParameter parameterOf(String id) =>
      parameters[id] ??
      EffectParameter(
        value: specOf(id)?.defaultValue ?? 0,
      );

  /// [id] is for a copy that stands beside its source — a paste, a
  /// duplicate — which has to be an effect of its own (F-476).
  LayerEffect copyWith({
    EffectId? id,
    EffectKind? kind,
    bool? enabled,
    Map<String, EffectParameter>? parameters,
    Map<String, PropertyTrack<int>>? colors,
    Map<String, TransformTrack>? points,
    Map<String, LayerId?>? layers,
    TransformTrack? stand,
  }) {
    return LayerEffect(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      plugin: plugin,
      enabled: enabled ?? this.enabled,
      parameters: parameters ?? this.parameters,
      colors: colors ?? this.colors,
      points: points ?? this.points,
      layers: layers ?? this.layers,
      stand: stand ?? this.stand,
    );
  }

  /// [parameters] with one entry replaced — the shape every key/value edit
  /// commits.
  LayerEffect withParameter(String parameterId, EffectParameter parameter) {
    return copyWith(parameters: {...parameters, parameterId: parameter});
  }

  /// [colors] with colour [colorId]'s keys replaced, [withParameter]'s twin.
  LayerEffect withColor(String colorId, PropertyTrack<int> keys) {
    return copyWith(colors: {...colors, colorId: keys});
  }

  /// [layers] with row parameter [layerId] naming [row] — none for null.
  LayerEffect withLayer(String layerId, LayerId? row) {
    return copyWith(layers: {...layers, layerId: row});
  }


  /// The keys lane [lane] keeps as a transform's lane, and which lane of
  /// theirs it is, by the transform lane's id: where a kind that draws its
  /// own picture stands it — a stand lane, by that id ([effectStandLanes])
  /// — or one of its [points], their Position; null for every other lane:
  /// a parameter's or a colour's.
  ///
  /// ⛔ONE QUESTION for both: every verb that keys, values, resets, walks
  /// or names such a lane asks it here and hands the answer to the
  /// transform's own verbs — 🗣️I-65-Q2 「공용화된거 사용하면서」.
  ({TransformTrack keys, String lane})? transformLaneAt(String lane) {
    if (points[lane] case final keys?) {
      return (keys: keys, lane: 'position');
    }
    if (kind.drawsItsOwnPicture && effectStandLanes.contains(lane)) {
      return (keys: stand, lane: lane);
    }
    return null;
  }

  /// [keys] put back where lane [lane] keeps them ([transformLaneAt]) —
  /// [stand] or the point's; this effect as it is for any other lane.
  LayerEffect withTransformKeysAt(String lane, TransformTrack keys) =>
      points.containsKey(lane)
      ? copyWith(points: {...points, lane: keys})
      : transformLaneAt(lane) == null
      ? this
      : copyWith(stand: keys);

  /// The keys lane [lane] of this effect holds — a parameter's or a
  /// colour's by its id, a transform's lane ([transformLaneAt]) — read
  /// without knowing their value type; null for a lane the effect has not.
  PropertyTrack<Object?>? laneTrack(String lane) =>
      switch (transformLaneAt(lane)) {
        (:final keys, lane: final kept) => transformLaneOf(
          keys,
          transformPropertyOfLaneId(kept)!,
        ),
        // A row keeps no keys: its lane's track is an empty one.
        null when layers.containsKey(lane) => PropertyTrack<Object?>.empty(),
        null => colors[lane] ?? parameters[lane]?.track,
      };

  /// Every lane of this effect, in the order its rows show them: where it
  /// stands first ([effectStandLanes]), as a transform's lanes lead, then
  /// its parameters.
  List<String> get lanes => [
    if (kind.drawsItsOwnPicture) ...effectStandLanes,
    for (final spec in specs) spec.id,
  ];

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'kind': kind.toJson(),
    if (plugin case final plugin?) 'plugin': plugin.toJson(),
    if (!enabled) 'enabled': false,
    'parameters': {
      for (final entry in parameters.entries)
        // A parameter sitting at its default with no keys says nothing.
        if (entry.value.value != (specOf(entry.key)?.defaultValue ?? 0) ||
            entry.value.track.isNotEmpty)
          entry.key: entry.value.toJson(),
    },
    if (colors.values.any((keys) => keys.isNotEmpty))
      'colors': {
        for (final entry in colors.entries)
          if (entry.value.isNotEmpty)
            entry.key: entry.value.toJson((value) => value),
      },
    if (points.values.any((keys) => keys.isNotEmpty))
      'points': {
        for (final entry in points.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.toJson(),
      },
    if (layers.values.any((row) => row != null))
      'layers': {
        for (final MapEntry(key: id, value: row) in layers.entries)
          if (row != null) id: row.toJson(),
      },
    if (stand.isNotEmpty) 'stand': stand.toJson(),
  };

  factory LayerEffect.fromJson(Map<String, dynamic> json) {
    final kind = EffectKind.fromJson(json['kind']);
    final rawParameters = json['parameters'] as Map<String, dynamic>? ?? {};
    final rawColors = json['colors'] as Map<String, dynamic>? ?? {};
    final rawPoints = json['points'] as Map<String, dynamic>? ?? {};
    final rawLayers = json['layers'] as Map<String, dynamic>? ?? {};
    final stand = json['stand'] as Map<String, dynamic>?;
    // The constructor fills whatever the file left out.
    return LayerEffect(
      id: EffectId.fromJson(json['id'] as Map<String, dynamic>),
      kind: kind,
      // A plugin's effect whose description is not a whole one is refused
      // there, as one with none is — as an effect of a kind this app has
      // not is ([EffectKind.fromJson]).
      plugin: FxPluginDescription.fromJson(json['plugin']),
      enabled: json['enabled'] as bool? ?? true,
      parameters: {
        for (final entry in rawParameters.entries)
          entry.key: EffectParameter.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
      colors: {
        for (final entry in rawColors.entries)
          entry.key: PropertyTrack.fromJson(
            entry.value as List?,
            (value) => (value! as num).toInt(),
          ),
      },
      points: {
        for (final entry in rawPoints.entries)
          entry.key: TransformTrack.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
      layers: {
        for (final entry in rawLayers.entries)
          entry.key: LayerId.fromJson(entry.value as Map<String, dynamic>),
      },
      stand: stand == null ? null : TransformTrack.fromJson(stand),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerEffect &&
          other.id == id &&
          other.kind == kind &&
          other.plugin == plugin &&
          other.enabled == enabled &&
          mapEquals(other.parameters, parameters) &&
          mapEquals(other.colors, colors) &&
          mapEquals(other.points, points) &&
          mapEquals(other.layers, layers) &&
          other.stand == stand;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    plugin,
    enabled,
    Object.hashAll([
      for (final entry in parameters.entries)
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAll([
      for (final entry in colors.entries) Object.hash(entry.key, entry.value),
    ]),
    Object.hashAll([
      for (final entry in points.entries) Object.hash(entry.key, entry.value),
    ]),
    Object.hashAll([
      for (final entry in layers.entries) Object.hash(entry.key, entry.value),
    ]),
    stand,
  );

  @override
  String toString() =>
      'LayerEffect($kind, enabled: $enabled, parameters: $parameters)';
}

/// An effect with its parameters SAMPLED at one frame — what the composite
/// carries and what the caches compare. Values are in [specs]' order, which
/// is the only order anything builds them in.
class ResolvedLayerEffect {
  ResolvedLayerEffect({
    required this.kind,
    this.plugin,
    required List<double> values,
    this.stand,
    Map<String, CanvasPoint?> points = const {},
    Map<String, LayerId?> layers = const {},
    this.frame,
    this.run,
  }) : values = List.unmodifiable(values),
       points = Map.unmodifiable(points),
       layers = Map.unmodifiable(layers);

  final EffectKind kind;

  /// The plugin a plugin's effect is of ([LayerEffect.plugin]).
  final FxPluginDescription? plugin;

  /// Every parameter of the effect, in [values]' order ([LayerEffect.specs]).
  List<EffectParameterSpec> get specs => LayerEffect._specsOf(kind, plugin);

  /// A point's or a row's is its spec's 0: neither is a number ([points],
  /// [layers]).
  final List<double> values;

  /// Where a kind that draws its own picture stands it at this frame
  /// ([LayerEffect.stand] sampled); null for every other kind.
  final EffectStand? stand;

  /// Where each of the kind's points stands at this frame
  /// ([LayerEffect.points] sampled, [effectPointAt]) — null for one at
  /// rest, the paper's middle, which the paper says ([effectPointOnPaper]).
  final Map<String, CanvasPoint?> points;

  /// The row each of the kind's row parameters names ([LayerEffect.layers])
  /// — null for none. Its id alone: what that row draws at this frame is
  /// the cut's to say, and its signature's.
  final Map<String, LayerId?> layers;

  /// The frame a PLUGIN's sample is of — null for every other kind's.
  ///
  /// ★A plugin is told the frame it runs at (anicel_fx_frame), so its
  /// picture may move from frame to frame where its values stand still —
  /// the one kind whose sample is not its values alone. Every reader that
  /// asks whether two frames show the same picture (the signature a run of
  /// frames shares, `computeCutFrameCompositeSignature`) compares samples,
  /// so a plugin's frames are never taken for one another, bound to a run
  /// or not.
  final int? frame;

  /// What a plugin's effect is run with at this frame ([FxPluginRun]) —
  /// null for every other kind, and for a plugin's where it does not run:
  /// 🗣️I-132-Q32 b, on a cel row with nothing before it but colour keys,
  /// on a device that has the plugin (`bindFxPluginRun`). A plugin's
  /// effect without one changes no pixel.
  final FxPluginRun? run;

  /// This sample run with [run].
  ResolvedLayerEffect withRun(FxPluginRun run) => ResolvedLayerEffect(
    kind: kind,
    plugin: plugin,
    values: values,
    stand: stand,
    points: points,
    layers: layers,
    frame: frame,
    run: run,
  );

  double parameter(String id) {
    final index = specs.indexWhere((spec) => spec.id == id);
    if (index < 0) {
      return 0;
    }
    return index < values.length ? values[index] : specs[index].defaultValue;
  }

  /// The ARGB colour parameter [id] holds ([EffectParameterUnit.color]).
  int color(String id) => parameter(id).toInt();

  /// Whether the flag parameter [id] is on ([EffectParameterUnit.flag]).
  bool flag(String id) => effectFlagIsOn(parameter(id));

  /// This sample naming no row ([layers]) — as a row a chain reads wears
  /// its own: 🗣️I-132-Q22 a, a blur map's own blur map is not read.
  ResolvedLayerEffect get namingNoRow =>
      layers.values.every((row) => row == null)
      ? this
      : ResolvedLayerEffect(
          kind: kind,
          plugin: plugin,
          values: values,
          stand: stand,
          points: points,
          layers: {for (final parameter in layers.keys) parameter: null},
          frame: frame,
          run: run,
        );

  /// Whether this sample changes no pixel: at its defaults, or at its kind's
  /// [EffectKind.strength] of nothing. Such an effect is dropped by the
  /// resolver, so nothing downstream ever pays for a filter that does
  /// nothing.
  ///
  /// A kind whose defaults change pixels never is
  /// ([EffectKind.changesNothingAtItsDefaults]): a cel number's letters are
  /// what it does, and what a plugin does at its defaults is the plugin's.
  bool get isNoOp {
    if (!kind.changesNothingAtItsDefaults) {
      return false;
    }
    if (kind.strength case final strength? when parameter(strength) <= 0) {
      return true;
    }
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
          other.plugin == plugin &&
          listEquals(other.values, values) &&
          other.stand == stand &&
          mapEquals(other.points, points) &&
          mapEquals(other.layers, layers) &&
          other.frame == frame &&
          other.run == run;

  @override
  int get hashCode => Object.hash(
    kind,
    plugin,
    Object.hashAll(values),
    stand,
    Object.hashAll([
      for (final entry in points.entries) Object.hash(entry.key, entry.value),
    ]),
    Object.hashAll([
      for (final entry in layers.entries) Object.hash(entry.key, entry.value),
    ]),
    frame,
    run,
  );

  @override
  String toString() =>
      'ResolvedLayerEffect($kind, $values, $stand, $points, $layers)';
}

/// Where point [keys] ([LayerEffect.points]) stand at [time], a frame or
/// between two — their Position walked as a transform's is — null while
/// unkeyed: then the point rests where a row does, which only the paper
/// says ([effectPointOnPaper]).
CanvasPoint? effectPointAt(TransformTrack keys, double time) =>
    resolveAnchorTrackAtTime(keys.position, time);

/// Where [point] — one sampled ([effectPointAt]) — stands on [paper]: where
/// its keys put it, or at rest where a row does ([layerIdentityPose]), the
/// paper's middle.
///
/// 🗣️08-07: 「위치는 기본값으로 — 기본 트랜스폼 fx 의 위치 기준, 늘 하던 대로
/// 공통된 거 사용」.
CanvasPoint effectPointOnPaper(CanvasPoint? point, CanvasSize paper) =>
    point ?? layerIdentityPose(paper).center;

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

/// Colour [keys] at [time], a frame or between two, walking channel by
/// channel ([argbKeySpace]) — unkeyed, [rest].
int effectColorAt(PropertyTrack<int> keys, double time, {required int rest}) =>
    keys.resolveAtTime(time: time, orElse: () => rest, space: argbKeySpace);

/// What lane [spec] of [effect] holds at [time], a frame or between two, as
/// the number [ResolvedLayerEffect.values] carries: a colour its ARGB
/// ([effectColorAt]), a point or a row its spec's 0 — neither is a number
/// ([ResolvedLayerEffect.points], [ResolvedLayerEffect.layers]) — any
/// other its parameter's walk.
double effectValueAt(
  LayerEffect effect,
  EffectParameterSpec spec,
  double time,
) => switch (effect.colors[spec.id]) {
  final keys? => effectColorAt(
    keys,
    time,
    rest: spec.defaultValue.toInt(),
  ).toDouble(),
  null
      when spec.unit == EffectParameterUnit.point ||
          spec.unit == EffectParameterUnit.layer =>
    spec.defaultValue,
  null => effect
      .parameterOf(spec.id)
      .resolveAtTime(time, space: spec.keySpace),
};

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
    final sample = sampleLayerEffectAt(effect, frameIndex);
    if (sample.isNoOp) {
      continue;
    }
    resolved.add(sample);
  }
  return resolved.isEmpty ? const [] : List.unmodifiable(resolved);
}

/// [effect] sampled at [frameIndex] — every lane, whether or not the
/// sample changes a pixel ([resolveLayerEffectsAt] drops the ones that do
/// not, and the switched-off ones).
ResolvedLayerEffect sampleLayerEffectAt(LayerEffect effect, int frameIndex) =>
    ResolvedLayerEffect(
      kind: effect.kind,
      plugin: effect.plugin,
      values: [
        for (final spec in effect.specs)
          spec.clamp(effectValueAt(effect, spec, frameIndex.toDouble())),
      ],
      stand: effect.kind.drawsItsOwnPicture
          ? effectStandAt(effect.stand, frameIndex.toDouble())
          : null,
      points: {
        for (final MapEntry(key: id, value: keys) in effect.points.entries)
          id: effectPointAt(keys, frameIndex.toDouble()),
      },
      layers: effect.layers,
      frame: effect.plugin == null ? null : frameIndex,
    );

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
    for (final MapEntry(key: lane, value: keys) in effect.colors.entries) {
      if (old.colors[lane] case final oldKeys?) {
        moved(lane, movedNamedKeys(oldKeys, keys));
      }
    }
    // Where it stands and its points are read as a transform's keys are,
    // by the transform's own reading of them.
    final stand = transformNamedKeyChanges(old.stand, effect.stand);
    moved('position', stand.position);
    moved('scale', stand.scale);
    for (final MapEntry(key: lane, value: keys) in effect.points.entries) {
      if (old.points[lane] case final oldKeys?) {
        moved(lane, transformNamedKeyChanges(oldKeys, keys).position);
      }
    }
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
      return switch (effect.specOf(parameterId)) {
        final spec? => effectValueAt(effect, spec, time),
        null => effect.parameterOf(parameterId).resolveAtTime(time),
      };
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
  switch (effect.transformLaneAt(change.lane)) {
    case (:final keys, lane: 'position'):
      return effect.withTransformKeysAt(
        change.lane,
        transformTrackWithNamedKeys(
          keys,
          TransformNamedChanges(position: named.cast()),
        ),
      );
    case (:final keys, lane: 'scale'):
      return effect.withTransformKeysAt(
        change.lane,
        transformTrackWithNamedKeys(
          keys,
          TransformNamedChanges(scale: named.cast()),
        ),
      );
    case _:
      if (effect.colors[change.lane] case final keys?) {
        return effect.withColor(
          change.lane,
          keys.withNamedKeys(named.cast()),
        );
      }
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

/// [effects] with every row they name ([LayerEffect.layers]) put through
/// [rowOf] — a copy's, whose rows are the copies of its source's (a
/// duplicated cut's, a linked cut's): what [rowOf] answers null for, they
/// name none. [effects] themselves where they name none.
///
/// ⛔ONE WAY a copy re-names its effects' rows, beside the attach pointer
/// (`attachedToLayerId`) it re-names at every site that copies rows.
List<LayerEffect> effectsWithRowsRenamed(
  List<LayerEffect> effects,
  LayerId? Function(LayerId row) rowOf,
) => effects.every((effect) => effect.layers.values.every((row) => row == null))
    ? effects
    : [
        for (final effect in effects)
          effect.copyWith(
            layers: {
              for (final MapEntry(key: id, value: row)
                  in effect.layers.entries)
                id: row == null ? null : rowOf(row),
            },
          ),
      ];

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
