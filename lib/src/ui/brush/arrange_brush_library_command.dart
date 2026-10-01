import '../../services/command.dart';
import 'brush_preset_library.dart';

/// A move in the brush library — a preset's place, the group it was dragged
/// into, a group tab's place — as one undo step.
///
/// 🗣️F-250 (유저 2026-10-01): 「브러시 위치 바꾸는것도 언두에 기록. 그룹바꾸든
/// 순서바꾸든」. The library is the app's, not the project's, but a move is
/// undone where the hand is, so it rides the session's history beside the
/// strokes.
///
/// ⚠️It carries [BrushLibraryArrangement]s, which name brushes by id: a
/// delete or an import between the move and its undo is not on the stack,
/// and laying the old order over the library as it stands then leaves both
/// of them be.
class ArrangeBrushLibraryCommand implements Command {
  ArrangeBrushLibraryCommand(
    this._library, {
    required this.before,
    required this.after,
  });

  final BrushPresetLibrary _library;
  final BrushLibraryArrangement before;
  final BrushLibraryArrangement after;

  @override
  String get description => 'Arrange brushes';

  @override
  void execute() => _library.arrange(after);

  @override
  void undo() => _library.arrange(before);
}
