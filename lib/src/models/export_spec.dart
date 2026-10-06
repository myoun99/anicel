import 'package:flutter/foundation.dart' show setEquals;

import 'envelope/cut_envelope_paper.dart';
import 'export_cel_kind.dart';
import 'export_cel_naming.dart';
import 'export_format_selection.dart';
import 'export_size_mode.dart';
import 'layer_mark.dart';
import 'layer_process.dart';

export 'export_cel_kind.dart';

/// Per-tab export specs (출력 UI v10): everything a tab's settings column
/// holds, as one serializable value. A preset stores exactly one of these
/// (자동 규칙만 — per-cut manual exceptions live on the project as
/// `ExportProjectOverrides`); the queue job carries one; the dialog binds
/// one per tab.

/// 🗣️F-289 (유저 2026-10-05): 「타임시트 탭을 그냥 셀 탭의 내부로 편입.
/// 컷봉투탭도 셀 내부로 편입」 — the timesheet and the cut envelope are KINDS
/// the Cels tab writes ([ExportCelKind]), where they were tabs of their own.
enum ExportTab {
  sequence,
  image,
  cels,
  conte;

  String get jsonValue => name;

  /// The tab [json] names, or null for a name no tab has — a preset saved
  /// for a tab that is one no longer is no preset of any tab.
  static ExportTab? fromJsonOrNull(Object? json) {
    for (final tab in ExportTab.values) {
      if (tab.jsonValue == json) {
        return tab;
      }
    }
    return null;
  }
}

/// The Scope module: the active cut, or the whole project. Sequence's
/// project scope has NO cut list (in/out alone trims it); the Cels tab's
/// PROJECT scope excludes cuts through the project-side overrides' cut
/// checks — for its cels, its timesheets and its cut envelopes alike — and
/// the cut scope never asks them (`exportCutsInScope`).
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

/// What a cut's timesheet is written as: the sheet's pages rendered on the
/// panel's paper as images, or a digital sheet file. (TDTS and the Auto
/// Sheet JSON join this enum once their sample files arrive — the seam is
/// this enum plus the format module's allow-list.)
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
    ExportTab.conte => ConteExportSpec.fromJson(json),
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
/// paper APPLIED. The attach/instruction/sheet/folder toggles and the two
/// dead mark slots this used to carry are gone — the label picker is what
/// the slots reserved a seat for, and the presets answer the row questions
/// in one place. v4 (F-289, 2026-10-06): the KINDS come first
/// ([ExportCelKind]), the filters after them.
class CelsExportSpec extends ExportTabSpec {
  const CelsExportSpec({
    this.format = const ExportFormatSelection(kind: ExportMediaKind.still),
    this.sizeMode = ExportSizeMode.canvas,
    this.applyLayerFx = true,
    this.naming = const ExportCelNaming(),
    this.kinds = defaultKinds,
    this.label = defaultLabel,
    this.take,
    this.applyPaper = true,
    this.base = true,
    this.attach = true,
    this.sheetOnly = false,
    this.scope = ExportScopeKind.cut,
    this.sheetFormat = ExportTimesheetFormat.sheetImage,
    this.sheetImage = paperDocumentFormat,
    this.envelopePaper = CutEnvelopePaperMode.cut,
    this.envelopeImage = paperDocumentFormat,
  });

  /// 유저 2026-10-06: 「기본값은 셀/미술/시트 체크 나머진 해제」.
  static const Set<ExportCelKind> defaultKinds = {
    ExportCelKind.cel,
    ExportCelKind.art,
    ExportCelKind.timesheet,
  };

  /// 원화(上がり). A fresh preset exports the key cels; 「라벨 없음」 as the
  /// default would export nothing from a labelled cut.
  static const LayerMark defaultLabel = LayerMark(process: LayerProcess.key);

  final ExportFormatSelection format;
  final ExportSizeMode sizeMode;

  /// The kinds this export writes ([ExportCelKind]) — a row of a kind that
  /// is not here is neither written nor listed.
  final Set<ExportCelKind> kinds;

  /// The ONE colour label an export is about — process × revise picked as a
  /// single item (「원화 작감」, 「LO 上がり」…; 유저: 「색라벨은 하나야. 공정이랑
  /// 수정 나누지않고」). A CEL row exports only when its own mark wears this
  /// label; the take component of this value is not consulted — [take] is.
  ///
  /// The other kinds do not answer to it: an art row is art whatever the
  /// label, and a conte or a direction row is its kind by being that row.
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

  /// 타임시트 형식: what a cut's timesheet is written as — its pages as
  /// pictures ([sheetImage]), or the digital sheet file. 유저 2026-10-05:
  /// 「기존의 범위는 셀의 범위 규칙 따라가고, 형식만 타임시트 형식이라는 항목
  /// 만들어서 법 통일해서 고를수있게」 — so its scope is the cels' ([scope]).
  final ExportTimesheetFormat sheetFormat;

  /// The picture a timesheet page is written as ([paperDocumentFormat]).
  final ExportFormatSelection sheetImage;

  /// 컷봉투 형식: the paper a cut envelope is written on (유저 2026-10-05:
  /// 「기존의 컷봉투탭에 있던 용지는 컷크기/실측용지 이거는 컷봉투 형식안에
  /// 넣고」). The CUT's own pixel size from the start, because the point of
  /// the digital envelope is to drop into the working file as a layer and
  /// line up with the artwork; the real envelope's paper is there for
  /// printing.
  ///
  /// Which FORM prints is not here: it is the work's
  /// (`TimesheetInfo.envelopeFormId`), chosen in the envelope panel — 유저 답
  /// envelope-form-in-export (2026-09-25): 「출력은 작품의 서식을 따른다
  /// (출력 창의 고르기는 뺀다)」.
  ///
  /// 🪦The tab it had could leave strata out and write one file a stratum.
  /// 유저 2026-10-05: 「레이어 항목 버튼? 용지 서식 내용 선화 고르는거 싹 다
  /// 필요없어보이니 삭제」 — an envelope is written whole.
  final CutEnvelopePaperMode envelopePaper;

  /// The picture a cut envelope is written as ([paperDocumentFormat]).
  final ExportFormatSelection envelopeImage;

  @override
  ExportTab get tab => ExportTab.cels;

  static const Object _unset = Object();

  CelsExportSpec copyWith({
    ExportFormatSelection? format,
    ExportSizeMode? sizeMode,
    bool? applyLayerFx,
    ExportCelNaming? naming,
    Set<ExportCelKind>? kinds,
    LayerMark? label,
    Object? take = _unset,
    bool? applyPaper,
    bool? base,
    bool? attach,
    bool? sheetOnly,
    ExportScopeKind? scope,
    ExportTimesheetFormat? sheetFormat,
    ExportFormatSelection? sheetImage,
    CutEnvelopePaperMode? envelopePaper,
    ExportFormatSelection? envelopeImage,
  }) => CelsExportSpec(
    format: format ?? this.format,
    sizeMode: sizeMode ?? this.sizeMode,
    applyLayerFx: applyLayerFx ?? this.applyLayerFx,
    naming: naming ?? this.naming,
    kinds: kinds ?? this.kinds,
    label: label ?? this.label,
    take: identical(take, _unset) ? this.take : take as int?,
    applyPaper: applyPaper ?? this.applyPaper,
    base: base ?? this.base,
    attach: attach ?? this.attach,
    sheetOnly: sheetOnly ?? this.sheetOnly,
    scope: scope ?? this.scope,
    sheetFormat: sheetFormat ?? this.sheetFormat,
    sheetImage: sheetImage ?? this.sheetImage,
    envelopePaper: envelopePaper ?? this.envelopePaper,
    envelopeImage: envelopeImage ?? this.envelopeImage,
  );

  /// This spec with [kind] written or not.
  CelsExportSpec withKind(ExportCelKind kind, bool written) => copyWith(
    kinds: {
      for (final each in ExportCelKind.values)
        if (each == kind ? written : kinds.contains(each)) each,
    },
  );

  @override
  Map<String, dynamic> toJson() => {
    'format': format.toJson(),
    if (sizeMode != ExportSizeMode.canvas) 'sizeMode': sizeMode.jsonValue,
    if (!applyLayerFx) 'applyLayerFx': false,
    'naming': naming.toJson(),
    if (!setEquals(kinds, defaultKinds))
      'kinds': [
        for (final kind in ExportCelKind.values)
          if (kinds.contains(kind)) kind.jsonValue,
      ],
    if (label != defaultLabel) 'label': label.toJson(),
    if (take != null) 'take': take,
    if (!applyPaper) 'applyPaper': false,
    if (!base) 'base': false,
    if (!attach) 'attach': false,
    if (sheetOnly) 'sheetOnly': true,
    if (scope != ExportScopeKind.cut) 'scope': scope.jsonValue,
    if (sheetFormat != ExportTimesheetFormat.sheetImage)
      'sheetFormat': sheetFormat.jsonValue,
    if (sheetImage != paperDocumentFormat) 'sheetImage': sheetImage.toJson(),
    if (envelopePaper != CutEnvelopePaperMode.cut)
      'envelopePaper': envelopePaper.toJson(),
    if (envelopeImage != paperDocumentFormat)
      'envelopeImage': envelopeImage.toJson(),
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
    kinds: switch (json['kinds']) {
      final List<dynamic> named => {
        for (final name in named) ?ExportCelKind.fromJson(name),
      },
      _ => defaultKinds,
    },
    label: json.containsKey('label')
        ? LayerMark.fromJson(json['label']).withTake(LayerMark.firstTake)
        : defaultLabel,
    take: json['take'] is int ? json['take'] as int : null,
    applyPaper: json['applyPaper'] as bool? ?? true,
    // 'selection' is the one-day-old preset spelling (base / attach /
    // sheet / direction); read it as the filters it meant.
    base: json['base'] as bool? ?? !_presetJsonWas(json, {'attach', 'direction'}),
    attach: json['attach'] as bool? ?? json['selection'] != 'direction',
    sheetOnly: json['sheetOnly'] as bool? ?? json['selection'] == 'sheet',
    scope: ExportScopeKind.fromJson(json['scope']),
    sheetFormat: ExportTimesheetFormat.fromJson(json['sheetFormat']),
    sheetImage: paperDocumentFormatFromJson(json['sheetImage']),
    // Absent means the DEFAULT (cut-fitted), not the enum's own fallback.
    envelopePaper: json['envelopePaper'] == null
        ? CutEnvelopePaperMode.cut
        : CutEnvelopePaperMode.fromJson(json['envelopePaper']),
    envelopeImage: paperDocumentFormatFromJson(json['envelopeImage']),
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
          setEquals(other.kinds, kinds) &&
          other.label == label &&
          other.take == take &&
          other.applyPaper == applyPaper &&
          other.base == base &&
          other.attach == attach &&
          other.sheetOnly == sheetOnly &&
          other.scope == scope &&
          other.sheetFormat == sheetFormat &&
          other.sheetImage == sheetImage &&
          other.envelopePaper == envelopePaper &&
          other.envelopeImage == envelopeImage;

  @override
  int get hashCode => Object.hash(
    format,
    sizeMode,
    applyLayerFx,
    naming,
    Object.hashAllUnordered(kinds),
    label,
    take,
    applyPaper,
    base,
    attach,
    sheetOnly,
    scope,
    sheetFormat,
    sheetImage,
    envelopePaper,
    envelopeImage,
  );
}

/// The picture a PAPER DOCUMENT is written as — a timesheet page, a conte
/// page, a cut envelope: PNG, or JPG at a quality (F-289, 유저 2026-10-05:
/// 「시트 그리고 png말고 jpg도 추가」).
///
/// The format module's own value ([ExportFormatSelection]), held to what a
/// sheet of paper can be: a still, opaque — the paper is its ground.
///
/// ↩️Each of the three carried a SCALE over its paper beside it (1x–4x,
/// `SheetImageScale`). 유저 2026-10-06 took the row out: 「시트 이미지는 배율
/// 없앰. 늘 용지 그대로. 콘티든 컷봉투든 똑같음. 필요하다면 해당 패널에
/// 용지크기 설정을 만들어서 용지 크기를 바꾸게할것임」 — a paper document goes
/// out at its paper's own pixels, what its panel shows at 100% (F-294).
const ExportFormatSelection paperDocumentFormat = ExportFormatSelection(
  kind: ExportMediaKind.still,
  channels: ExportChannels.rgb,
);

/// [json] read as a paper document's picture: [paperDocumentFormat] where
/// the file names none, and a format a paper cannot be (PSD) is PNG.
ExportFormatSelection paperDocumentFormatFromJson(Object? json) {
  if (json is! Map<String, dynamic>) {
    return paperDocumentFormat;
  }
  final read = ExportFormatSelection.fromJson(json);
  return paperDocumentFormat.copyWith(
    stillFormat: read.stillFormat == ExportStillFormat.jpg
        ? ExportStillFormat.jpg
        : ExportStillFormat.png,
    jpgQuality: read.jpgQuality,
  );
}

/// The Conte tab: the storyboard sheet as one vector PDF, or its pages as
/// images.
class ConteExportSpec extends ExportTabSpec {
  const ConteExportSpec({
    this.format = ExportConteFormat.pdf,
    this.image = paperDocumentFormat,
  });

  final ExportConteFormat format;

  /// The picture a page image is written as ([paperDocumentFormat]); the
  /// PDF is vector and does not ask it.
  final ExportFormatSelection image;

  @override
  ExportTab get tab => ExportTab.conte;

  ConteExportSpec copyWith({
    ExportConteFormat? format,
    ExportFormatSelection? image,
  }) => ConteExportSpec(
    format: format ?? this.format,
    image: image ?? this.image,
  );

  @override
  Map<String, dynamic> toJson() => {
    if (format != ExportConteFormat.pdf) 'format': format.jsonValue,
    if (image != paperDocumentFormat) 'image': image.toJson(),
  };

  static ConteExportSpec fromJson(Map<String, dynamic> json) => ConteExportSpec(
    format: ExportConteFormat.fromJson(json['format']),
    image: paperDocumentFormatFromJson(json['image']),
  );

  @override
  bool operator ==(Object other) =>
      other is ConteExportSpec &&
      other.format == format &&
      other.image == image;

  @override
  int get hashCode => Object.hash(format, image);
}

/// The dialog's last-used spec per tab (app state, persisted with the
/// presets in the export settings file).
class ExportTabSpecs {
  const ExportTabSpecs({
    this.sequence = const SequenceExportSpec(),
    this.image = const ImageExportSpec(),
    this.cels = const CelsExportSpec(),
    this.conte = const ConteExportSpec(),
  });

  final SequenceExportSpec sequence;
  final ImageExportSpec image;
  final CelsExportSpec cels;
  final ConteExportSpec conte;

  ExportTabSpec specFor(ExportTab tab) => switch (tab) {
    ExportTab.sequence => sequence,
    ExportTab.image => image,
    ExportTab.cels => cels,
    ExportTab.conte => conte,
  };

  ExportTabSpecs withSpec(ExportTabSpec spec) => switch (spec) {
    SequenceExportSpec() => copyWith(sequence: spec),
    ImageExportSpec() => copyWith(image: spec),
    CelsExportSpec() => copyWith(cels: spec),
    ConteExportSpec() => copyWith(conte: spec),
  };

  ExportTabSpecs copyWith({
    SequenceExportSpec? sequence,
    ImageExportSpec? image,
    CelsExportSpec? cels,
    ConteExportSpec? conte,
  }) => ExportTabSpecs(
    sequence: sequence ?? this.sequence,
    image: image ?? this.image,
    cels: cels ?? this.cels,
    conte: conte ?? this.conte,
  );

  Map<String, dynamic> toJson() => {
    'sequence': sequence.toJson(),
    'image': image.toJson(),
    'cels': cels.toJson(),
    'conte': conte.toJson(),
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
    conte: json['conte'] == null
        ? const ConteExportSpec()
        : ConteExportSpec.fromJson(json['conte'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportTabSpecs &&
          other.sequence == sequence &&
          other.image == image &&
          other.cels == cels &&
          other.conte == conte;

  @override
  int get hashCode => Object.hash(sequence, image, cels, conte);
}
