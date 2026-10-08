import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';

/// The kinds a test of the CELS writes: the cut's cel rows and its art rows,
/// and no document.
///
/// The app's own default also writes the cut's timesheet (F-289, 유저
/// 2026-10-06: 「기본값은 셀/미술/시트 체크 나머진 해제」) — a row of the list
/// and a file of the run, which a test about cels would have to name in
/// every expectation it makes. What the default itself lists and writes is
/// pinned where the documents are
/// (`the_cuts_documents_are_kinds_of_the_cels_tab_test.dart`).
const Set<ExportCelKind> celKindsAlone = {ExportCelKind.cel, ExportCelKind.art};

/// A cels spec writing [celKindsAlone].
const CelsExportSpec celsAlone = CelsExportSpec(kinds: celKindsAlone);

/// The export settings a test of the cels opens the window on.
AppExportSettings exportSettingsWritingCelsAlone({
  ExportScopeKind scope = ExportScopeKind.cut,
}) => AppExportSettings(
  lastSpecs: ExportTabSpecs(
    cels: CelsExportSpec(kinds: celKindsAlone, scope: scope),
  ),
);
