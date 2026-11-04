/// Where an import lands (§2's three destinations).
///
/// A model since F-429: a cut folder's rows are answered it too
/// (`CutFolderEdits.into`), and the answers are the model's.
enum ImportDestination {
  /// A layer in the ACTIVE cut.
  activeCutLayer,

  /// A new cut appended to the selected track.
  newCut,

  /// A NEW PROJECT of the file's own, in a tab of its own — the file its
  /// one cut, made as a new cut is: at the file's size and as long as it
  /// runs (07-29 임포트 설계 §2: 「미디어 크기로 새 프로젝트」).
  ///
  /// 🗣️I-156 (유저 2026-11-04: 「임포트창에서 넣을곳에 새 프로젝트도 신설」;
  /// Q1 「파일마다 프로젝트 하나」 · Q2 「그 동영상의 fps」). ↩️「a later
  /// round, documented」 until then.
  ///
  /// ⛔No landing lands it: a landing lands in its own project. The import
  /// window opens the project and lands the file there as [newCut].
  newProject;

  /// The destinations inside THIS project — what a cut folder's row is
  /// asked (F-429-Q1: 「레이어당 하나하나 새 컷 만들어서 넣는다거나 새
  /// 레이어 정한다거나」). A new project is a FILE's answer (I-156-Q1:
  /// 「파일마다 프로젝트 하나」).
  static const List<ImportDestination> inThisProject = [
    activeCutLayer,
    newCut,
  ];

  /// Whether the file arrives in a cut made FOR it — at its own size, so
  /// the 1:1 fit is the only one that means anything there.
  bool get makesItsCut => this != activeCutLayer;
}

/// [into] where there is a cut open to put a layer in, and a new cut where
/// a layer was asked for and there is none — the ONE answer for a file the
/// import window lists and a cut folder's row alike (유저 2026-09-12:
/// 「액티브 컷이 없는 상태에서 캔버스 떨구면 새 컷 고정」).
ImportDestination importDestinationGiven(
  ImportDestination into, {
  required bool hasOpenCut,
}) => into == ImportDestination.activeCutLayer && !hasOpenCut
    ? ImportDestination.newCut
    : into;
