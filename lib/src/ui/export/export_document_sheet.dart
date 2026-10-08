import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/export_overrides.dart';
import '../../models/export_spec.dart';
import 'export_list_sheet.dart';
import 'export_plan.dart' show sanitizeExportFileComponent;

/// ONE DOCUMENT FILE of a cut the Cels tab writes beside its cels: a page of
/// its timesheet (or the sheet's digital file), or its cut envelope.
///
/// 🗣️F-289 (유저 2026-10-05): 「타임시트 탭을 그냥 셀 탭의 내부로 편입.
/// 컷봉투탭도 셀 내부로 편입 … 기존의 범위는 셀의 범위 규칙 따라가고」.
class ExportDocumentSheet extends ExportListSheet {
  const ExportDocumentSheet({
    required this.kind,
    required this.listedIn,
    required this.of,
    required this.page,
    required this.pageCount,
    required this.fileName,
    this.skipped = false,
    this.refused,
  });

  /// [ExportCelKind.timesheet] or [ExportCelKind.envelope].
  final ExportCelKind kind;

  /// The cut the window lists it in.
  final Cut listedIn;

  /// The cut the document is OF — a timesheet's own cut, an envelope's
  /// owner — which is the cut that answers for it: a 겸용 group is one
  /// entry of the list, and each of its cuts keeps a sheet of its own.
  final Cut of;

  /// Which page of the timesheet, from 0; 0 for an envelope, and for the
  /// sheet's digital file, which is one file whatever its pages.
  final int page;

  /// How many files the document is written as.
  final int pageCount;

  @override
  final String fileName;

  @override
  final bool skipped;

  @override
  final ExportCelRefusal? refused;

  @override
  CutId get deltaCut => of.id;

  @override
  String get idValue => '${kind.jsonValue}-${of.id.value}-$page';

  /// A page says its number; a document that is one file says its cut.
  @override
  String get word => pageCount > 1 ? '${page + 1}' : of.name;

  @override
  String get fullName => exportDocumentBase(kind, of, page, pageCount);

  /// Nothing is laid over a document.
  @override
  bool get laid => false;

  ExportDocumentPage get ref => (document: kind, page: page);
}

/// What a document file is called before its prefix and its extension.
///
/// A TIMESHEET is `TS` and its cut — and its page, from 1, once it has more
/// than one (유저 2026-10-05: 「타임시트는 기본적으로 파일이름 TS로서 출력.
/// TS+컷번호 이런식. 페이지가 2개이상 있다면 TS301_1 , TS301_2 이런식」).
/// ↩️`CUT301` · `CUT301_p1`, the name its tab gave it.
///
/// A cut ENVELOPE keeps `CUT301_envelope`.
String exportDocumentBase(ExportCelKind kind, Cut of, int page, int pageCount) {
  final cut = sanitizeExportFileComponent(of.name);
  return switch (kind) {
    ExportCelKind.envelope => 'CUT${cut}_envelope',
    _ => pageCount > 1 ? 'TS${cut}_${page + 1}' : 'TS$cut',
  };
}

/// The extension a document of [kind] is written with under [spec].
String exportDocumentExtension(ExportCelKind kind, CelsExportSpec spec) =>
    switch (kind) {
      ExportCelKind.envelope => spec.envelopeImage.stillFormat.fileExtension,
      _ =>
        spec.sheetFormat == ExportTimesheetFormat.xdts
            ? 'xdts'
            : spec.sheetImage.stillFormat.fileExtension,
    };
