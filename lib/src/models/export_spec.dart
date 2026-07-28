import 'export_cel_naming.dart';
import 'export_format_selection.dart';
import 'export_size_mode.dart';

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
  conte;

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

  static ImageExportSpec fromJson(Map<String, dynamic> json) =>
      ImageExportSpec(
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
class CelsExportSpec extends ExportTabSpec {
  const CelsExportSpec({
    this.format = const ExportFormatSelection(kind: ExportMediaKind.still),
    this.sizeMode = ExportSizeMode.canvas,
    this.naming = const ExportCelNaming(),
    this.onTimesheetOnly = false,
    this.includeInstructionLayers = true,
    this.includeSyncedAttach = true,
    this.includeFreeAttach = true,
    this.includeFolderMembers = false,
    this.markFilterA,
    this.markFilterB,
    this.scope = ExportScopeKind.cut,
  });

  final ExportFormatSelection format;
  final ExportSizeMode sizeMode;
  final ExportCelNaming naming;
  final bool onTimesheetOnly;

  /// 지시 레이어 출력 (v10 ⑤: 기본 on, 프리셋 저장).
  final bool includeInstructionLayers;

  /// Attach-group gates: whether a base layer's synced/free attach rows
  /// join the cel list.
  final bool includeSyncedAttach;
  final bool includeFreeAttach;

  /// 소속 폴더 전부 포함: any included layer pulls its whole folder.
  final bool includeFolderMembers;

  /// Mark-filter slots (자리 확보 — 마크 2중화와 함께 활성). Null = off.
  final String? markFilterA;
  final String? markFilterB;

  final ExportScopeKind scope;

  @override
  ExportTab get tab => ExportTab.cels;

  static const Object _unset = Object();

  CelsExportSpec copyWith({
    ExportFormatSelection? format,
    ExportSizeMode? sizeMode,
    ExportCelNaming? naming,
    bool? onTimesheetOnly,
    bool? includeInstructionLayers,
    bool? includeSyncedAttach,
    bool? includeFreeAttach,
    bool? includeFolderMembers,
    Object? markFilterA = _unset,
    Object? markFilterB = _unset,
    ExportScopeKind? scope,
  }) => CelsExportSpec(
    format: format ?? this.format,
    sizeMode: sizeMode ?? this.sizeMode,
    naming: naming ?? this.naming,
    onTimesheetOnly: onTimesheetOnly ?? this.onTimesheetOnly,
    includeInstructionLayers:
        includeInstructionLayers ?? this.includeInstructionLayers,
    includeSyncedAttach: includeSyncedAttach ?? this.includeSyncedAttach,
    includeFreeAttach: includeFreeAttach ?? this.includeFreeAttach,
    includeFolderMembers: includeFolderMembers ?? this.includeFolderMembers,
    markFilterA: identical(markFilterA, _unset)
        ? this.markFilterA
        : markFilterA as String?,
    markFilterB: identical(markFilterB, _unset)
        ? this.markFilterB
        : markFilterB as String?,
    scope: scope ?? this.scope,
  );

  @override
  Map<String, dynamic> toJson() => {
    'format': format.toJson(),
    if (sizeMode != ExportSizeMode.canvas) 'sizeMode': sizeMode.jsonValue,
    'naming': naming.toJson(),
    if (onTimesheetOnly) 'onTimesheetOnly': true,
    if (!includeInstructionLayers) 'includeInstructionLayers': false,
    if (!includeSyncedAttach) 'includeSyncedAttach': false,
    if (!includeFreeAttach) 'includeFreeAttach': false,
    if (includeFolderMembers) 'includeFolderMembers': true,
    if (markFilterA != null) 'markFilterA': markFilterA,
    if (markFilterB != null) 'markFilterB': markFilterB,
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
    naming: json['naming'] == null
        ? const ExportCelNaming()
        : ExportCelNaming.fromJson(json['naming'] as Map<String, dynamic>),
    onTimesheetOnly: json['onTimesheetOnly'] as bool? ?? false,
    includeInstructionLayers:
        json['includeInstructionLayers'] as bool? ?? true,
    includeSyncedAttach: json['includeSyncedAttach'] as bool? ?? true,
    includeFreeAttach: json['includeFreeAttach'] as bool? ?? true,
    includeFolderMembers: json['includeFolderMembers'] as bool? ?? false,
    markFilterA: json['markFilterA'] as String?,
    markFilterB: json['markFilterB'] as String?,
    scope: ExportScopeKind.fromJson(json['scope']),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelsExportSpec &&
          other.format == format &&
          other.sizeMode == sizeMode &&
          other.naming == naming &&
          other.onTimesheetOnly == onTimesheetOnly &&
          other.includeInstructionLayers == includeInstructionLayers &&
          other.includeSyncedAttach == includeSyncedAttach &&
          other.includeFreeAttach == includeFreeAttach &&
          other.includeFolderMembers == includeFolderMembers &&
          other.markFilterA == markFilterA &&
          other.markFilterB == markFilterB &&
          other.scope == scope;

  @override
  int get hashCode => Object.hash(
    format,
    sizeMode,
    naming,
    onTimesheetOnly,
    includeInstructionLayers,
    includeSyncedAttach,
    includeFreeAttach,
    includeFolderMembers,
    markFilterA,
    markFilterB,
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
    if (format != ExportTimesheetFormat.sheetImage)
      'format': format.jsonValue,
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

  static ConteExportSpec fromJson(Map<String, dynamic> json) =>
      ConteExportSpec(
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

/// The dialog's last-used spec per tab (app state, persisted with the
/// presets in the export settings file).
class ExportTabSpecs {
  const ExportTabSpecs({
    this.sequence = const SequenceExportSpec(),
    this.image = const ImageExportSpec(),
    this.cels = const CelsExportSpec(),
    this.timesheet = const TimesheetExportSpec(),
    this.conte = const ConteExportSpec(),
  });

  final SequenceExportSpec sequence;
  final ImageExportSpec image;
  final CelsExportSpec cels;
  final TimesheetExportSpec timesheet;
  final ConteExportSpec conte;

  ExportTabSpec specFor(ExportTab tab) => switch (tab) {
    ExportTab.sequence => sequence,
    ExportTab.image => image,
    ExportTab.cels => cels,
    ExportTab.timesheet => timesheet,
    ExportTab.conte => conte,
  };

  ExportTabSpecs withSpec(ExportTabSpec spec) => switch (spec) {
    SequenceExportSpec() => copyWith(sequence: spec),
    ImageExportSpec() => copyWith(image: spec),
    CelsExportSpec() => copyWith(cels: spec),
    TimesheetExportSpec() => copyWith(timesheet: spec),
    ConteExportSpec() => copyWith(conte: spec),
  };

  ExportTabSpecs copyWith({
    SequenceExportSpec? sequence,
    ImageExportSpec? image,
    CelsExportSpec? cels,
    TimesheetExportSpec? timesheet,
    ConteExportSpec? conte,
  }) => ExportTabSpecs(
    sequence: sequence ?? this.sequence,
    image: image ?? this.image,
    cels: cels ?? this.cels,
    timesheet: timesheet ?? this.timesheet,
    conte: conte ?? this.conte,
  );

  Map<String, dynamic> toJson() => {
    'sequence': sequence.toJson(),
    'image': image.toJson(),
    'cels': cels.toJson(),
    'timesheet': timesheet.toJson(),
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
    timesheet: json['timesheet'] == null
        ? const TimesheetExportSpec()
        : TimesheetExportSpec.fromJson(
            json['timesheet'] as Map<String, dynamic>,
          ),
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
          other.timesheet == timesheet &&
          other.conte == conte;

  @override
  int get hashCode => Object.hash(sequence, image, cels, timesheet, conte);
}
