/// Where an import lands (§2's three destinations; PROJECT — a new
/// project sized to the media — is a later round, documented).
///
/// A model since F-429: a cut folder's rows are answered it too
/// (`CutFolderEdits.into`), and the answers are the model's.
enum ImportDestination {
  /// A layer in the ACTIVE cut.
  activeCutLayer,

  /// A new cut appended to the selected track.
  newCut,
}

/// [into] where there is a cut open to put a layer in, and a new cut where
/// there is none — the ONE answer for a file the import window lists and a
/// cut folder's row alike (유저 2026-09-12: 「액티브 컷이 없는 상태에서
/// 캔버스 떨구면 새 컷 고정」).
ImportDestination importDestinationGiven(
  ImportDestination into, {
  required bool hasOpenCut,
}) => hasOpenCut ? into : ImportDestination.newCut;
