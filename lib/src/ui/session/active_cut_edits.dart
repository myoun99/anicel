import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import 'session_roles.dart';

/// THE ENVELOPE EVERY ACTIVE-ROW CUT COMMAND RIDES IN: refuse unless the
/// verb's own gate says yes, take the ACTIVE row's id, run one coordinator
/// command keyed by (cut, layer), then refresh KEEPING THAT ROW ACTIVE and
/// notify.
///
/// Four verbs across two collaborators wrote it out by hand — 링크 복제,
/// 링크 해제, 폴더 생성, 공정 폴더 생성. What differs between them is a bool
/// getter and a two-argument command, and both are values.
///
/// ⚠️The trailing step is the one that goes missing when an envelope is
/// copied: `CutVerbs._moveActiveCut` carries a comment recording exactly
/// that loss. It has one writer now.
class ActiveCutEdits {
  ActiveCutEdits({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
  }) : _project = project,
       _selection = selection,
       _changes = changes;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;

  void onActiveLayer({
    required bool when,
    required void Function(CutId cutId, LayerId layerId) command,
  }) {
    if (!when) {
      return;
    }
    // A non-null active layer implies an active cut (the gap state has no
    // rows at all), which every one of these gates already establishes.
    final layerId = _selection.activeLayer!.id;
    command(_project.requireActiveCut.id, layerId);
    _changes.refreshAfterCutCommand(preferredActiveLayerId: layerId);
    _changes.notifyChanged();
  }
}
