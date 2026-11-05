/// The XDTS Viewer's ink folder (opentoonz/xdts_viewer, BSD-3 — its FORMAT
/// only, read from its sources and its v1.3.0 release): what a timesheet's
/// handwriting — and the values the viewer does not print — is written as
/// beside its `.xdts` so the viewer shows it.
///
/// 🗣️I-161 (유저 2026-11-05): 「형식 xdts로하면 잉크 출력 on off버튼 둠 …
/// 같은이름 폴더안에 잉크층을 png로 저장하면 볼수있었던거같은데」. The viewer
/// keeps a page's scribble as `<folder>/<page>.png` — transparent, its
/// sheet's paper at 250 dpi, laid from the top left — and the sheet it lays
/// them on in that folder's `config.ini`.
library;

import '../../models/timesheet_document.dart' show TimesheetContentPart;
import '../../models/transition_geometry.dart';
import '../../models/xdts_viewer_sheet.dart';

/// The folder the viewer reads [xdtsFileName]'s ink from: the name less
/// its `.xdts`, and less the `_genga_ts` / `_douga_ts` a genga or douga
/// sheet's name carries (in any case), with `_xdts` after it — the
/// viewer's `MyParams::getImageFolderPath`.
String xdtsInkFolderName(String xdtsFileName) {
  final pairSuffix = RegExp('_(genga|douga)_ts', caseSensitive: false);
  final name = xdtsFileName.replaceAll(pairSuffix, '');
  return '${name.substring(0, name.length - '.xdts'.length)}_xdts';
}

/// The file the viewer reads page [pageIndex]'s ink from — its pages count
/// from 1 (0 is a sheet's back, which the app has none of), one picture a
/// page while every column fits it.
String xdtsInkPageFileName(int pageIndex) => '${pageIndex + 1}.png';

/// The values a page's ink picture carries beside the handwriting: those
/// the viewer does not print of the file — it reads the cel field alone
/// and leaves the dialog and the camera columns blank grids — and the cuts
/// the cut is 겸용 with, which the file has no field for.
/// 🗣️I-161-Q3 (유저 2026-11-05): 「데이터로서 내보낼수있는건 다 내보내고싶음.
/// 거기서 xdts뷰어용일때만 추가로 잉크로서 내보내게」 · Q4: 「컷번호밑에 겸용컷
/// 써준다거나 … 똑같이」 — under the cut's name, as our sheet writes it.
const Set<TimesheetContentPart> xdtsViewerUnprintedParts = {
  TimesheetContentPart.se,
  TimesheetContentPart.camera,
  TimesheetContentPart.linkedCuts,
};

/// The viewer's `config.ini` for a sheet laid on [sheet] that draws
/// [handles] of のりしろ: the template, the cells area and the O.L each
/// end — every other setting the viewer's own default. `Version` says
/// which page names it reads (1A, 1B from 1.2.0).
///
/// An O.L is written as twice the のりしろ its side draws: the viewer takes
/// half an O.L off each end of a sheet's frames for its 尺, so twice the
/// のりしろ gives back the conte 尺 the app prints — my call, not the
/// user's (I-161); an O.L laid evenly across the cut is exactly that.
String xdtsViewerConfig({
  required XdtsViewerSheet sheet,
  required CutTransitionHandles handles,
}) =>
    '[General]\n'
    'Version=1.3.0\n'
    '\n'
    '[FormatSettings]\n'
    'TemplateName="${sheet.label}"\n'
    'ExportArea=Cells\n'
    'StartOverlapFrameLength=${handles.head * 2}\n'
    'EndOverlapFrameLength=${handles.tail * 2}\n';
