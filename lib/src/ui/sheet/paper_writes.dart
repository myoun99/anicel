import '../../models/cut_id.dart';
import '../../models/layer_mark.dart';
import '../../models/timesheet_info.dart';
import '../editor_session_manager.dart';

/// Where the words typed into a paper's box land — ONE set of roads for
/// every paper, because the papers print the same values: the work's
/// episode and title (the values its settings show), a cut's name and its
/// scene, and a stage's worker on a cut (the name 컷 설정 shows).
///
/// 🗣️I-127-Q2 (유저 2026-10-27): 「같은 값을 찍는 칸은 전부 — 타임시트
/// 머리와 같은 길」 — the envelope's boxes write by the roads the
/// timesheet's header writes by. ↩️The timesheet's paper held them.
class PaperWrites {
  const PaperWrites(this._session);

  final EditorSessionManager _session;

  /// The work's episode (I-112).
  void episode(String episode) =>
      _work((info) => info.copyWith(episode: episode));

  /// The work's title (I-112).
  void title(String title) => _work((info) => info.copyWith(title: title));

  /// [cut]'s name.
  ///
  /// ⛔An empty name is no cut's name — the rename window refuses one
  /// inline ([RenameCutDialog]); a box has no line to say so, so it keeps
  /// the name it prints.
  void cutName(CutId cut, String name) {
    if (name.isNotEmpty) {
      _session.cutVerbs.renameCuts({cut: name});
    }
  }

  /// [stage]'s worker on [cut] (I-112 · I-127-Q1).
  void staffName(CutId cut, LayerMark stage, String name) =>
      _session.cutVerbs.setCutStaffName(cut, stage, name);

  /// [cut]'s scene (F-291) — empty clears it, as a scene may be none.
  void scene(CutId cut, String scene) =>
      _session.cutVerbs.setCutScene(cut, scene);

  void _work(TimesheetInfo Function(TimesheetInfo info) edit) =>
      _session.updateTimesheetInfo(edit(_session.timesheetInfo));
}
