import 'project.dart';
import 'project_background.dart';

/// A plane the stage may leave out — the backdrop, the pasteboard: its
/// colour, and whether it is there at all (F-114: 「없음」 keeps the colour
/// for the next pick).
typedef StagePlaneSetting = ({int argb, bool none});

/// The canvas's three STAGE PLANES as one value: the paper, the backdrop and
/// the pasteboard — as a project holds them ([stagePlanesOf]), or as a
/// colour window shows them before it closes (`StagePlanesPreview`).
typedef StagePlanes = ({
  ProjectBackground paper,
  StagePlaneSetting backdrop,
  StagePlaneSetting pasteboard,
});

/// [project]'s planes, as it holds them.
StagePlanes stagePlanesOf(Project project) => (
  paper: project.background,
  backdrop: (argb: project.backdropArgb, none: project.backdropNone),
  pasteboard: (argb: project.pasteboardArgb, none: project.pasteboardNone),
);
