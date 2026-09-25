import 'package:flutter/foundation.dart' show setEquals;

import 'sheet_paint_layer.dart';
import 'envelope/cut_envelope_paper.dart';
import 'export_cel_naming.dart';
import 'export_format_selection.dart';
import 'export_size_mode.dart';
import 'layer_mark.dart';
import 'layer_process.dart';

/// Per-tab export specs (출력 UI v10): everything a tab's settings column
/// holds, as one serializable value. A preset stores exactly one of these
/// (자동 규칙만 — per-cut manual exceptions live on the project as
/// `ExportProjectOverrides`); the queue job carries one; the dialog binds
/// one per tab.

enum ExportTab {
  sequence,
  image,
  cels,
  timesheet,
  conte,
  envelope;

  String get jsonValue => name;

  static ExportTab fromJson(Object? json) {
    for (final tab in ExportTab.values) {
      if (tab.jsonValue == json) {
        return tab;
      }
    }
    return ExportTab.sequence;
  }
}

/// The Scope module: the active cut, or the whole project. Sequence's
/// project scope has NO cut list (in/out alone trims it); Cels/Timesheet
/// scope excludes cuts through the project-side overrides' cut checks.
enum ExportScopeKind {
  cut,
  project;

  String get jsonValue => name;

  static ExportScopeKind fromJson(Object? json) => switch (json) {
    'project' => ExportScopeKind.project,
    _ => ExportScopeKind.cut,
  };
}

/// Numbered-sequence file naming: `<baseName>_0001.<ext>`. The digit width
/// clamps to 1..8 on write.
class ExportSequenceNaming {
  const ExportSequenceNaming({this.baseName = 'frame', this.digits = 4});

  final String baseName;
  final int digits;

  ExportSequenceNaming copyWith({String? baseName, int? digits}) =>
      ExportSequenceNaming(
        baseName: baseName ?? this.baseName,
        digits: (digits ?? this.digits).clamp(1, 8),
      );

  Map<String, dynamic> toJson() => {
    if (baseName != 'frame') 'baseName': baseName,
    if (digits != 4) 'digits': digits,
  };

  static ExportSequenceNaming fromJson(Map<String, dynamic> json) =>
      ExportSequenceNaming(
        baseName: json['baseName'] as String? ?? 'frame',
        digits: ((json['digits'] as num?)?.round() ?? 4).clamp(1, 8),
      );

  @override
  bool operator ==(Object other) =>
      other is ExportSequenceNaming &&
      other.baseName == baseName &&
      other.digits == digits;

  @override
  int get hashCode => Object.hash(baseName, digits);
}

/// What the Timesheet tab writes: rendered B4 sheet pages as images, or a
/// digital sheet file. (TDTS and the Auto Sheet JSON join this enum once
/// their sample files arrive — the seam is this enum plus the tab's format
/// module allow-list.)
enum ExportTimesheetFormat {
  sheetImage,
  xdts;

  String get jsonValue => name;

  static ExportTimesheetFormat fromJson(Object? json) => switch (json) {
    'xdts' => ExportTimesheetFormat.xdts,
    _ => ExportTimesheetFormat.sheetImage,
  };
}

/// What the Conte tab writes: one vector PDF of the whole sheet (text as
/// embedded-font runs, pictures as raster cells), or the pages as images
/// (the timesheet's sheet-image shape).
enum ExportConteFormat {
  pdf,
  pageImage;

  String get jsonValue => name;

  static ExportConteFormat fromJson(Object? json) => switch (json) {
    'pageImage' => ExportConteFormat.pageImage,
    _ => ExportConteFormat.pdf,
  };
}

sealed class ExportTabSpec {
  const ExportTabSpec();

  ExportTab get tab;

  Map<String, dynamic> toJson();
}

/// Parses a spec serialized next to its [ExportTab] discriminator.
ExportTabSpec exportTabSpecFromJson(ExportTab tab, Map<String, dynamic> json) {
  return switch (tab) {
    ExportTab.sequence => SequenceExportSpec.fromJson(json),
    ExportTab.image => ImageExportSpec.fromJson(json),
    ExportTab.cels => CelsExportSpec.fromJson(json),
    ExportTab.timesheet => TimesheetExportSpec.fromJson(json),
    ExportTab.conte => ConteExportSpec.fromJson(json),
    ExportTab.envelope => EnvelopeExportSpec.fromJson(json),
  };
}

/// Sequence tab: video or a numbered image sequence over the cut/project.
///
/// [inFrame]/[outFrame] are 0-based inclusive on the scope's own axis
/// (cut-local for [ExportScopeKind.cut], the whole-track play axis for
/// [ExportScopeKind.project]); null = unclipped.
class SequenceExportSpec extends ExportTabSpec {
  const SequenceExportSpec({
    this.format = const ExportFormatSelection(),
    this.scope = ExportScopeKind.cut,
    this.sizeMode = ExportSizeMode.camera,
    this.inFrame,
    this.outFrame,
    this.naming = const ExportSequenceNaming(),
    this.applyLayerFx = true,
    this.includeAudio = true,
  });

  final ExportFormatSelection format;
  final ExportScopeKind scope;
  final ExportSizeMode sizeMode;
  final int? inFrame;
  final int? outFrame;
  final ExportSequenceNaming naming;
  final bool applyLayerFx;
  final bool includeAudio;

  @override
  ExportTab get tab => ExportTab.sequence;

  static const Object _unset = Object();

  SequenceExportSpec copyWith({
    ExportFormatSelection? format,
    ExportScopeKind? scope,
    ExportSizeMode? sizeMode,
    Object? inFrame = _unset,
    Object? outFrame = _unset,
    ExportSequenceNaming? naming,
    bool? applyLayerFx,
    bool? includeAudio,
  }) => SequenceExportSpec(
    format: format ?? this.format,
    scope: scope ?? this.scope,
    sizeMode: sizeMode ?? this.sizeMode,
    inFrame: identical(inFrame, _unset) ? this.inFrame : inFrame as int?,
    outFrame: identical(outFrame, _unset) ? this.outFrame : outFrame as int?,
    naming: naming ?? this.naming,
    applyLayerFx: applyLayerFx ?? this.applyLayerFx,
    includeAudio: includeAudio ?? this.includeAudio,
  );

  @override
  Map<String, dynamic> toJson() => {
    'format': format.toJson(),
    if (scope != ExportScopeKind.cut) 'scope': scope.jsonValue,
    if (sizeMode != ExportSizeMode.camera) 'sizeMode': sizeMode.jsonValue,
    if (inFrame != null) 'inFrame': inFrame,
    if (outFrame != null) 'outFrame': outFrame,
    'naming': naming.toJson(),
    if (!applyLayerFx) 'applyLayerFx': false,
    if (!includeAudio) 'includeAudio': false,
  };

  static SequenceExportSpec fromJson(Map<String, dynamic> json) =>
      SequenceExportSpec(
        format: json['format'] == null
            ? const ExportFormatSelection()
            : ExportFormatSelection.fromJson(
                json['format'] as Map<String, dynamic>,
              ),
        scope: ExportScopeKind.fromJson(json['scope']),
        sizeMode: ExportSizeMode.fromJson(json['sizeMode']),
        inFrame: (json['inFrame'] as num?)?.round(),
        outFrame: (json['outFrame'] as num?)?.round(),
        naming: json['naming'] == null
            ? const ExportSequenceNaming()
            : ExportSequenceNaming.fromJson(
                json['naming'] as Map<String, dynamic>,
              ),
        applyLayerFx: json['applyLayerFx'] as bool? ?? true,
        includeAudio: json['includeAudio'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SequenceExportSpec &&
          other.format == format &&
          other.scope == scope &&
          other.sizeMode == sizeMode &&
          other.inFrame == inFrame &&
          other.outFrame == outFrame &&
          other.naming == naming &&
          other.applyLayerFx == applyLayerFx &&
          other.includeAudio == includeAudio;

  @override
  int get hashCode => Object.hash(
    format,
    scope,
    sizeMode,
    inFrame,
    outFrame,
    naming,
    applyLayerFx,
    includeAudio,
  );
}

/// Image tab: the current frame as one still. Always cut-scoped (the frame
/// under the playhead), so Camera and Canvas are both legal sizes.
class ImageExportSpec extends ExportTabSpec {
  const ImageExportSpec({
    this.format = const ExportFormatSelection(kind: ExportMediaKind.still),
    this.sizeMode = ExportSizeMode.camera,
    this.applyLayerFx = true,
  });

  final ExportFormatSelection format;
  final ExportSizeMode sizeMode;
  final bool applyLayerFx;

  @override
  ExportTab get tab => ExportTab.image;

  ImageExportSpec copyWith({
    ExportFormatSelection? format,
    ExportSizeMode? sizeMode,
    bool? applyLayerFx,
  }) => ImageExportSpec(
    format: format ?? this.format,
    sizeMode: sizeMode ?? this.sizeMode,
    applyLayerFx: applyLayerFx ?? this.applyLayerFx,
  );

  @override
  Map<String, dynamic> toJson() => {
    'format': format.toJson(),
    if (sizeMode != ExportSizeMode.camera) 'sizeMode': sizeMode.jsonValue,
    if (!applyLayerFx) 'applyLayerFx': false,
  };

  static ImageExportSpec fromJson(Map<String, dynamic> json) => ImageExportSpec(
    format: json['format'] == null
        ? const ExportFormatSelection(kind: ExportMediaKind.still)
        : ExportFormatSelection.fromJson(
            json['format'] as Map<String, dynamic>,
          ),
    sizeMode: ExportSizeMode.fromJson(json['sizeMode']),
    applyLayerFx: json['applyLayerFx'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageExportSpec &&
          other.format == format &&
          other.sizeMode == sizeMode &&
          other.applyLayerFx == applyLayerFx;

  @override
  int get hashCode => Object.hash(format, sizeMode, applyLayerFx);
}

/// Cels tab: the AUTO RULES (프리셋 저장분). What they resolve to for a
/// given cut — and how the per-cut manual delta overrides that — lives in
/// `resolveExportCelsSelection`; the delta itself is project data.
///
/// v3 (유저 2026-09-09): one colour LABEL, one TAKE, one selection PRESET,
/// paper APPLIED, art ADDED. The attach/instruction/sheet/folder toggles
/// and the two dead mark slots this used to carry are gone — the label
/// picker is what the slots reserved a seat for, and the presets answer
/// the row questions in one place.
class CelsExportSpec extends ExportTabSpec {
  const CelsExportSpec({
    this.format = const ExportFormatSelection(kind: ExportMediaKind.still),
    this.sizeMode = ExportSizeMode.canvas,
    this.applyLayerFx = true,
    this.naming = const ExportCelNaming(),
    this.label = defaultLabel,
    this.take,
    this.applyPaper = true,
    this.addArt = false,
    this.addDirection = false,
    this.base = true,
    this.attach = true,
    this.sheetOnly = false,
    this.scope = ExportScopeKind.cut,
  });

  /// 원화(上がり). A fresh preset exports the key cels; 「라벨 없음」 as the
  /// default would export nothing from a labelled cut.
  static const LayerMark defaultLabel = LayerMark(process: LayerProcess.key);

  final ExportFormatSelection format;
  final ExportSizeMode sizeMode;

  /// The ONE colour label an export is about — process × revise picked as a
  /// single item (「원화 작감」, 「LO 上がり」…; 유저: 「색라벨은 하나야. 공정이랑
  /// 수정 나누지않고」). A row exports only when its own mark wears this
  /// label; the take component of this value is not consulted — [take] is.
  final LayerMark label;

  /// The take a row must wear, or null for 「최신」: among rows sharing a
  /// name and the label, the highest take present (A T1 + A T2 → T2 only;
  /// A T1 + B T2 → both). The one item the export added to the timeline's
  /// take flyout.
  final int? take;

  /// 용지 적용: the paper-labelled rows' drawing is composited into EVERY
  /// output cel. Paper is never a cel of its own (유저: 「모든 출력 셀에 용지
  /// 라벨의 그림을 적용시키는거지」).
  final bool applyPaper;

  /// 미술 추가: rows whose process is 미술 export as cels of their own,
  /// whatever the label (유저: 「같은 공정의 미술레이어를 추가할지」).
  final bool addArt;

  /// 디렉션 추가: the instruction rows export as image cels, one per event.
  /// An ADDITION beside 미술, not a way of selecting (유저 2026-09-09:
  /// 「디렉션은 선택항목말고 추가항목에 묶는게 나을듯」).
  final bool addDirection;

  /// 선택 = FILTERS THAT STACK, not presets (유저 2026-09-09: 「단일선택이
  /// 아니라 중첩가능이야 … 진짜 여러 항목이 필터로 작동하는거지」):
  /// [base] keeps the base rows, [attach] keeps the attach rows — both on
  /// is the whole stack, attach alone is the parts without their base
  /// (the base still numbers the cels) — and [sheetOnly] keeps, of those,
  /// only the rows on the timesheet (an attach row is on it when its base
  /// is). The label and the take are the filters after these.
  final bool base;
  final bool attach;
  final bool sheetOnly;

  /// Whether the delivery cel is rendered THROUGH the rows' effect chains.
  ///
  /// 🚨THIS WAS A HARDCODED false, and that was the asymmetry. The other
  /// tabs have carried this switch since R4-new1; the cel tab alone forced
  /// it off, under a rule I wrote in R6a (#794) whose stated reason was
  /// BLUR — 「a blur can never be baked into line art the compositing
  /// department has to work with」.
  ///
  /// ✅유저 2026-08-27 made it a switch: 「셀 출력 강제도 래스터라이즈시키고
  /// 출력하면 되는거니까 멋대로 판단하지말고」. Default ON, because a color
  /// key exists to clean the artwork BEING delivered; an artist who wants the
  /// raw line back turns it off here, which is what every other tab already
  /// let them do.
  final bool applyLayerFx;

  final ExportCelNaming naming;

  final ExportScopeKind scope;

  @override
  ExportTab get tab => ExportTab.cels;

  static const Object _unset = Object();

  CelsExportSpec copyWith({
    ExportFormatSelection? format,
    ExportSizeMode? sizeMode,
    bool? applyLayerFx,
    ExportCelNaming? naming,
    LayerMark? label,
    Object? take = _unset,
    bool? applyPaper,
    bool? addArt,
    bool? addDirection,
    bool? base,
    bool? attach,
    bool? sheetOnly,
    ExportScopeKind? scope,
  }) => CelsExportSpec(
    format: format ?? this.format,
    sizeMode: sizeMode ?? this.sizeMode,
    applyLayerFx: applyLayerFx ?? this.applyLayerFx,
    naming: naming ?? this.naming,
    label: label ?? this.label,
    take: identical(take, _unset) ? this.take : take as int?,
    applyPaper: applyPaper ?? this.applyPaper,
    addArt: addArt ?? this.addArt,
    addDirection: addDirection ?? this.addDirection,
    base: base ?? this.base,
    attach: attach ?? this.attach,
    sheetOnly: sheetOnly ?? this.sheetOnly,
    scope: scope ?? this.scope,
  );

  @override
  Map<String, dynamic> toJson() => {
    'format': format.toJson(),
    if (sizeMode != ExportSizeMode.canvas) 'sizeMode': sizeMode.jsonValue,
    if (!applyLayerFx) 'applyLayerFx': false,
    'naming': naming.toJson(),
    if (label != defaultLabel) 'label': label.toJson(),
    if (take != null) 'take': take,
    if (!applyPaper) 'applyPaper': false,
    if (addArt) 'addArt': true,
    if (addDirection) 'addDirection': true,
    if (!base) 'base': false,
    if (!attach) 'attach': false,
    if (sheetOnly) 'sheetOnly': true,
    if (scope != ExportScopeKind.cut) 'scope': scope.jsonValue,
  };

  static CelsExportSpec fromJson(Map<String, dynamic> json) => CelsExportSpec(
    format: json['format'] == null
        ? const ExportFormatSelection(kind: ExportMediaKind.still)
        : ExportFormatSelection.fromJson(
            json['format'] as Map<String, dynamic>,
          ),
    sizeMode: json['sizeMode'] == null
        ? ExportSizeMode.canvas
        : ExportSizeMode.fromJson(json['sizeMode']),
    applyLayerFx: json['applyLayerFx'] as bool? ?? true,
    naming: json['naming'] == null
        ? const ExportCelNaming()
        : ExportCelNaming.fromJson(json['naming'] as Map<String, dynamic>),
    label: json.containsKey('label')
        ? LayerMark.fromJson(json['label']).withTake(LayerMark.firstTake)
        : defaultLabel,
    take: json['take'] is int ? json['take'] as int : null,
    applyPaper: json['applyPaper'] as bool? ?? true,
    addArt: json['addArt'] as bool? ?? false,
    // 'selection' is the one-day-old preset spelling (base / attach /
    // sheet / direction); read it as the filters it meant.
    addDirection:
        json['addDirection'] as bool? ?? json['selection'] == 'direction',
    base: json['base'] as bool? ?? !_presetJsonWas(json, {'attach', 'direction'}),
    attach: json['attach'] as bool? ?? json['selection'] != 'direction',
    sheetOnly: json['sheetOnly'] as bool? ?? json['selection'] == 'sheet',
    scope: ExportScopeKind.fromJson(json['scope']),
  );

  static bool _presetJsonWas(Map<String, dynamic> json, Set<String> names) =>
      names.contains(json['selection']);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelsExportSpec &&
          other.format == format &&
          other.sizeMode == sizeMode &&
          other.applyLayerFx == applyLayerFx &&
          other.naming == naming &&
          other.label == label &&
          other.take == take &&
          other.applyPaper == applyPaper &&
          other.addArt == addArt &&
          other.addDirection == addDirection &&
          other.base == base &&
          other.attach == attach &&
          other.sheetOnly == sheetOnly &&
          other.scope == scope;

  @override
  int get hashCode => Object.hash(
    format,
    sizeMode,
    applyLayerFx,
    naming,
    label,
    take,
    applyPaper,
    addArt,
    addDirection,
    base,
    attach,
    sheetOnly,
    scope,
  );
}

class TimesheetExportSpec extends ExportTabSpec {
  const TimesheetExportSpec({
    this.format = ExportTimesheetFormat.sheetImage,
    this.scope = ExportScopeKind.cut,
    this.sheetScale = 2,
  });

  final ExportTimesheetFormat format;
  final ExportScopeKind scope;

  /// Sheet-image raster scale over the document's logical size (1..4).
  final int sheetScale;

  @override
  ExportTab get tab => ExportTab.timesheet;

  TimesheetExportSpec copyWith({
    ExportTimesheetFormat? format,
    ExportScopeKind? scope,
    int? sheetScale,
  }) => TimesheetExportSpec(
    format: format ?? this.format,
    scope: scope ?? this.scope,
    sheetScale: (sheetScale ?? this.sheetScale).clamp(1, 4),
  );

  @override
  Map<String, dynamic> toJson() => {
    if (format != ExportTimesheetFormat.sheetImage) 'format': format.jsonValue,
    if (scope != ExportScopeKind.cut) 'scope': scope.jsonValue,
    if (sheetScale != 2) 'sheetScale': sheetScale,
  };

  static TimesheetExportSpec fromJson(Map<String, dynamic> json) =>
      TimesheetExportSpec(
        format: ExportTimesheetFormat.fromJson(json['format']),
        scope: ExportScopeKind.fromJson(json['scope']),
        sheetScale: ((json['sheetScale'] as num?)?.round() ?? 2).clamp(1, 4),
      );

  @override
  bool operator ==(Object other) =>
      other is TimesheetExportSpec &&
      other.format == format &&
      other.scope == scope &&
      other.sheetScale == sheetScale;

  @override
  int get hashCode => Object.hash(format, scope, sheetScale);
}

/// The Conte tab: the storyboard sheet as one vector PDF (or page images).
class ConteExportSpec extends ExportTabSpec {
  const ConteExportSpec({
    this.format = ExportConteFormat.pdf,
    this.sheetScale = 2,
  });

  final ExportConteFormat format;

  /// Page-image raster scale over the page's logical size (1..4);
  /// PDF output is vector and ignores it.
  final int sheetScale;

  @override
  ExportTab get tab => ExportTab.conte;

  ConteExportSpec copyWith({ExportConteFormat? format, int? sheetScale}) =>
      ConteExportSpec(
        format: format ?? this.format,
        sheetScale: (sheetScale ?? this.sheetScale).clamp(1, 4),
      );

  @override
  Map<String, dynamic> toJson() => {
    if (format != ExportConteFormat.pdf) 'format': format.jsonValue,
    if (sheetScale != 2) 'sheetScale': sheetScale,
  };

  static ConteExportSpec fromJson(Map<String, dynamic> json) => ConteExportSpec(
    format: ExportConteFormat.fromJson(json['format']),
    sheetScale: ((json['sheetScale'] as num?)?.round() ?? 2).clamp(1, 4),
  );

  @override
  bool operator ==(Object other) =>
      other is ConteExportSpec &&
      other.format == format &&
      other.sheetScale == sheetScale;

  @override
  int get hashCode => Object.hash(format, sheetScale);
}

/// The Envelope tab: the 컷봉투 as an image — one sheet per cut, and one
/// sheet for a 겸용 cut and all its siblings together.
///
/// The default is the CUT's own pixel size, because the point of the
/// digital envelope is to drop into the working file as a layer and line
/// up with the artwork. The real-envelope size is there for printing.
///
/// Which FORM prints is not here: it is the work's
/// (`TimesheetInfo.envelopeFormId`), chosen in the envelope panel — 유저 답
/// envelope-form-in-export (2026-09-25): 「출력은 작품의 서식을 따른다
/// (출력 창의 고르기는 뺀다)」. ↩️The spec used to carry its own `formId`
/// so a studio could read one form on screen and hand over another.
class EnvelopeExportSpec extends ExportTabSpec {
  const EnvelopeExportSpec({
    this.paperMode = CutEnvelopePaperMode.cut,
    this.scope = ExportScopeKind.cut,
    this.sheetWidth = 2480,
    this.layers = defaultLayers,
    this.separateLayerFiles = false,
  });

  /// Every stratum, which is what a flat PNG of the sheet means.
  static const Set<SheetPaintLayer> defaultLayers = {
    SheetPaintLayer.paper,
    SheetPaintLayer.form,
    SheetPaintLayer.content,
    SheetPaintLayer.ink,
  };

  final CutEnvelopePaperMode paperMode;
  final ExportScopeKind scope;

  /// The real-envelope mode's pixel width (A4 at 300dpi by default); the
  /// cut mode takes the canvas verbatim and ignores this.
  final int sheetWidth;

  /// Which strata print. Turning one off is how a printed sheet ships
  /// without its handwriting, or how the form alone becomes a template.
  final Set<SheetPaintLayer> layers;

  /// One file per enabled layer instead of one flat image — the PSD
  /// layering, shipping as PNGs until the PSD writer lands. Each file
  /// carries exactly one stratum, so only the paper file is opaque and the
  /// rest stack over it in whatever the recipient opens them in.
  final bool separateLayerFiles;

  /// The strata actually drawn, in painting order.
  List<SheetPaintLayer> get orderedLayers => [
    for (final layer in SheetPaintLayer.values)
      if (layers.contains(layer)) layer,
  ];

  @override
  ExportTab get tab => ExportTab.envelope;

  EnvelopeExportSpec copyWith({
    CutEnvelopePaperMode? paperMode,
    ExportScopeKind? scope,
    int? sheetWidth,
    Set<SheetPaintLayer>? layers,
    bool? separateLayerFiles,
  }) => EnvelopeExportSpec(
    paperMode: paperMode ?? this.paperMode,
    scope: scope ?? this.scope,
    sheetWidth: (sheetWidth ?? this.sheetWidth).clamp(64, 20000),
    layers: layers ?? this.layers,
    separateLayerFiles: separateLayerFiles ?? this.separateLayerFiles,
  );

  /// Toggles one stratum, refusing to leave nothing to draw.
  EnvelopeExportSpec withLayer(SheetPaintLayer layer, bool enabled) {
    final next = {...layers};
    if (enabled) {
      next.add(layer);
    } else {
      next.remove(layer);
    }
    return next.isEmpty ? this : copyWith(layers: next);
  }

  @override
  Map<String, dynamic> toJson() => {
    if (paperMode != CutEnvelopePaperMode.cut) 'paperMode': paperMode.toJson(),
    if (scope != ExportScopeKind.cut) 'scope': scope.jsonValue,
    if (sheetWidth != 2480) 'sheetWidth': sheetWidth,
    if (!setEquals(layers, defaultLayers))
      'layers': [for (final layer in orderedLayers) layer.jsonValue],
    if (separateLayerFiles) 'separateLayerFiles': true,
  };

  static EnvelopeExportSpec fromJson(Map<String, dynamic> json) {
    final rawLayers = json['layers'];
    final layers = rawLayers is List
        ? {for (final entry in rawLayers) ?SheetPaintLayer.fromJson(entry)}
        : defaultLayers;
    return EnvelopeExportSpec(
      // Absent means the DEFAULT (cut-fitted), not the enum's own fallback.
      paperMode: json['paperMode'] == null
          ? CutEnvelopePaperMode.cut
          : CutEnvelopePaperMode.fromJson(json['paperMode']),
      scope: ExportScopeKind.fromJson(json['scope']),
      sheetWidth: ((json['sheetWidth'] as num?)?.round() ?? 2480).clamp(
        64,
        20000,
      ),
      // An empty list would leave nothing to draw; a file that says so is
      // saying "default", not "blank page".
      layers: layers.isEmpty ? defaultLayers : layers,
      separateLayerFiles: json['separateLayerFiles'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EnvelopeExportSpec &&
      other.paperMode == paperMode &&
      other.scope == scope &&
      other.sheetWidth == sheetWidth &&
      setEquals(other.layers, layers) &&
      other.separateLayerFiles == separateLayerFiles;

  @override
  int get hashCode => Object.hash(
    paperMode,
    scope,
    sheetWidth,
    Object.hashAllUnordered(layers),
    separateLayerFiles,
  );
}

/// The dialog's last-used spec per tab (app state, persisted with the
/// presets in the export settings file).
class ExportTabSpecs {
  const ExportTabSpecs({
    this.sequence = const SequenceExportSpec(),
    this.image = const ImageExportSpec(),
    this.cels = const CelsExportSpec(),
    this.timesheet = const TimesheetExportSpec(),
    this.conte = const ConteExportSpec(),
    this.envelope = const EnvelopeExportSpec(),
  });

  final SequenceExportSpec sequence;
  final ImageExportSpec image;
  final CelsExportSpec cels;
  final TimesheetExportSpec timesheet;
  final ConteExportSpec conte;
  final EnvelopeExportSpec envelope;

  ExportTabSpec specFor(ExportTab tab) => switch (tab) {
    ExportTab.sequence => sequence,
    ExportTab.image => image,
    ExportTab.cels => cels,
    ExportTab.timesheet => timesheet,
    ExportTab.conte => conte,
    ExportTab.envelope => envelope,
  };

  ExportTabSpecs withSpec(ExportTabSpec spec) => switch (spec) {
    SequenceExportSpec() => copyWith(sequence: spec),
    ImageExportSpec() => copyWith(image: spec),
    CelsExportSpec() => copyWith(cels: spec),
    TimesheetExportSpec() => copyWith(timesheet: spec),
    ConteExportSpec() => copyWith(conte: spec),
    EnvelopeExportSpec() => copyWith(envelope: spec),
  };

  ExportTabSpecs copyWith({
    SequenceExportSpec? sequence,
    ImageExportSpec? image,
    CelsExportSpec? cels,
    TimesheetExportSpec? timesheet,
    ConteExportSpec? conte,
    EnvelopeExportSpec? envelope,
  }) => ExportTabSpecs(
    sequence: sequence ?? this.sequence,
    image: image ?? this.image,
    cels: cels ?? this.cels,
    timesheet: timesheet ?? this.timesheet,
    conte: conte ?? this.conte,
    envelope: envelope ?? this.envelope,
  );

  Map<String, dynamic> toJson() => {
    'sequence': sequence.toJson(),
    'image': image.toJson(),
    'cels': cels.toJson(),
    'timesheet': timesheet.toJson(),
    'conte': conte.toJson(),
    'envelope': envelope.toJson(),
  };

  static ExportTabSpecs fromJson(Map<String, dynamic> json) => ExportTabSpecs(
    sequence: json['sequence'] == null
        ? const SequenceExportSpec()
        : SequenceExportSpec.fromJson(json['sequence'] as Map<String, dynamic>),
    image: json['image'] == null
        ? const ImageExportSpec()
        : ImageExportSpec.fromJson(json['image'] as Map<String, dynamic>),
    cels: json['cels'] == null
        ? const CelsExportSpec()
        : CelsExportSpec.fromJson(json['cels'] as Map<String, dynamic>),
    timesheet: json['timesheet'] == null
        ? const TimesheetExportSpec()
        : TimesheetExportSpec.fromJson(
            json['timesheet'] as Map<String, dynamic>,
          ),
    conte: json['conte'] == null
        ? const ConteExportSpec()
        : ConteExportSpec.fromJson(json['conte'] as Map<String, dynamic>),
    envelope: json['envelope'] == null
        ? const EnvelopeExportSpec()
        : EnvelopeExportSpec.fromJson(json['envelope'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportTabSpecs &&
          other.sequence == sequence &&
          other.image == image &&
          other.cels == cels &&
          other.timesheet == timesheet &&
          other.conte == conte &&
          other.envelope == envelope;

  @override
  int get hashCode =>
      Object.hash(sequence, image, cels, timesheet, conte, envelope);
}
