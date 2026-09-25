import 'package:flutter/foundation.dart';

import '../../core/set_toggle.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../services/project_tree_editor.dart';
import 'session_roles.dart';

/// VISIBILITY SOLO — showing one layer alone and remembering what the others
/// looked like so leaving solo restores them — as its own object: the
/// snapshot, the cut it was taken in, and the toggles that enter and leave.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and eight
/// session members touched. It names the roles it needs in its constructor.
class VisibilitySolo {
  VisibilitySolo({required ProjectAccess project, required SelectionAccess selection, required ChangeSink changes, required TimelineAccess timeline}) : _project = project, _selection = selection, _changes = changes, _timeline = timeline;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;

  /// The SE solo set — pure MONITORING state (never persisted, never
  /// exported): non-empty narrows playback/scrub to these SE rows. Held by
  /// [toggleLayerSolo], its one writer; playback and the rows read it.
  final ValueNotifier<Set<LayerId>> soloedSeLayerIds =
      ValueNotifier<Set<LayerId>>(const {});

  void dispose() => soloedSeLayerIds.dispose();

  /// The legend eye's SOLO MODE (R4 #7 rework — REAL eye flips, user rule):
  /// engaging it snapshots every row's eye (cut layers + track SE), turns
  /// every non-active eye OFF and the active one ON — the rows show it and
  /// playback/fill follow naturally, exactly like clicking the eyes by
  /// hand (view-ish controller writes, not undoable). Switching the active
  /// layer re-solos; disengaging restores each eye from the snapshot.
  /// Leaving the cut exits the mode (restoring first) — the snapshot is
  /// cut-scoped.
  ///
  /// 🚨★★NO PART OF IT IS AN UNDO STEP (F-125, 유저 2026-09-15: 「비지블
  /// 솔로모드 전환은 언두에 기록안되게. 스트로크하고 솔로모드하고 언두했는데
  /// 솔로모드가 언두 되고싶지않아」 · 「캔버스 관련 확대나 축소가 언두에
  /// 기록안되는거랑 같은 느낌 … 진짜 표시용만 바꿀뿐인거거든」).
  ///
  /// ↩️The 2026-08-29 round (#1345, 「눈을 껏다키든 뭐든 다 언두」) had put the
  /// solo's flips into history as batches while the MODE stayed outside it.
  /// Undoing those eyes moved the document, the tidy-up after the step
  /// re-soloed for the mode that was still on, and the re-solo wrote a fresh
  /// entry — so each press undid the entry the press before it had made, and
  /// nothing from before the solo could be reached. Entering, leaving and
  /// following the active row all write the eyes straight through the
  /// repository now ([_writeEyes]); an eye clicked by hand still undoes.
  bool _layerVisibilitySoloEnabled = false;

  Map<LayerId, bool>? _visibilitySoloSnapshot;

  CutId? _visibilitySoloCutId;

  bool get layerVisibilitySoloEnabled => _layerVisibilitySoloEnabled;

  void toggleLayerVisibilitySolo() {
    if (_layerVisibilitySoloEnabled) {
      exitVisibilitySolo();
    } else {
      _layerVisibilitySoloEnabled = true;
      _visibilitySoloCutId = _timeline.editingSession.activeCutId;
      _visibilitySoloSnapshot = {
        for (final layer in _project.layers) layer.id: layer.isVisible,
      };
      _applyVisibilitySolo();
    }
    _changes.notifyChanged();
  }

  /// Re-solos to the CURRENT active layer. Rows born during the solo join
  /// the snapshot with their pre-flip eye so exiting restores them too.
  void _applyVisibilitySolo() {
    final activeId = _selection.activeLayerId;
    if (activeId == null) {
      return;
    }
    final stack = _project.layers;
    // 🚨THE ANCESTORS STAY ON. Solo means "show this row alone", and a row
    // inside a folder is not shown by its own eye — turning every OTHER row
    // off turned its folders off with them, so soloing a row inside a folder
    // hid the very thing it was soloing. On the editing canvas that read as
    // "nothing happened"; in playback and export the frame came out EMPTY.
    //
    // 🚨AND STANDING ON A FOLDER SOLOS WHAT IT HOLDS (F-129, 유저 2026-09-14:
    // 「폴더에 서있으면 폴더 내용물 전부 on해서 보여주도록. 중첩이 몇개있던
    // 관계없이 내용물 전부」) — its whole subtree, the folders nested in it
    // and their rows too, whatever their own eyes said before. A row that
    // holds nothing has an empty subtree, so every row asks this one way.
    final keepShown = <LayerId>{
      activeId,
      for (final folder in stack.ancestryOf(
        stack.where((layer) => layer.id == activeId).firstOrNull?.folderId,
      ))
        folder.id,
      for (final member in stack.subtreeMembersOf(activeId)) member.id,
    };
    // ⛔ONE pass, and the eye is read ONCE per row. Splitting the two
    // batches into two comprehensions read the row's own eye twice, and
    // `hidden_folder_is_hidden_test`'s downward ratchet caught it — that
    // count only goes down, because every extra place that re-derives
    // "is this row shown" is a place a hidden folder can be forgotten.
    final flips = <LayerId, bool>{};
    for (final layer in stack) {
      _visibilitySoloSnapshot?.putIfAbsent(layer.id, () => layer.isVisible);
      final shouldShow = keepShown.contains(layer.id);
      if (layer.isVisible == shouldShow) {
        continue;
      }
      flips[layer.id] = shouldShow;
    }
    // ↩️Two history batches stood here (2026-08-29: 「Two batches, not one
    // per row: Solo hides most of the stack and shows a few, and each side
    // is one undo step rather than a screenful」). F-125 took the solo out of
    // history altogether — see [_layerVisibilitySoloEnabled].
    _writeEyes(flips);
  }

  /// 🚨★★★**THE FILE NEVER SEES A VIEW STATE.**
  ///
  /// 🗣️유저 2026-09-18 (F-153): 「활성레이어 솔로는 **저장시 저장안되도록**.
  /// 지금 솔로 on한상태로 저장하고 열면 **적용된채로 모드는 off**되있는
  /// 상태」 — answered on `solo-and-the-saved-file` with 「**저장이 솔로
  /// 이전의 눈을 기록한다**」.
  ///
  /// ⛔**BOTH LAWS SURVIVE, and that is why it is here and not in the
  /// door.** The eyes really do flip — 유저's own rule (「REAL eye flips」,
  /// 08-29) — so a save cannot simply refuse to look at them; it has to
  /// know what they were BEFORE, and the only thing that knows is the
  /// snapshot this object is already holding for the exit.
  ///
  /// ⚠️Identity with no solo up: a caller never has to ask first, so no
  /// write path can be the one that forgot.
  ///
  /// 🚨**THE SAME SEAM THE EXIT USES** ([updateLayerAnywhere], which is
  /// what `repository.updateLayer` is). ⛔A walk of `tracks → cuts →
  /// layers` written here instead would be the same algorithm spelled
  /// twice — and the second spelling was already WRONG: the eye rows are
  /// not only a cut's layers. A track's SE rows and its transition row
  /// live BESIDE the cuts, reach the cut's row list as display clones,
  /// and the solo flips them like any other row. Only the anywhere seam
  /// knows all three places.
  Project projectAsSavedWithoutSolo(Project project) {
    final snapshot = _visibilitySoloSnapshot;
    if (snapshot == null) {
      return project;
    }
    var asSaved = project;
    snapshot.forEach((layerId, wasVisible) {
      // Null = the row was deleted during the solo; nothing to put back,
      // exactly as [_writeEyes] skips it on the way out.
      asSaved =
          updateLayerAnywhere(asSaved, layerId, _eyeRestoredTo(wasVisible)) ??
          asSaved;
    });
    return asSaved;
  }

  /// What 「put this row's eye back to what the snapshot remembers」 MEANS,
  /// spelled once. [exitVisibilitySolo] writes it into the session and
  /// [projectAsSavedWithoutSolo] writes it into the project being saved —
  /// two sinks, one law.
  Layer Function(Layer) _eyeRestoredTo(bool visible) => (layer) =>
      layer.isVisible == visible ? layer : layer.copyWith(isVisible: visible);

  void exitVisibilitySolo() {
    _layerVisibilitySoloEnabled = false;
    _visibilitySoloCutId = null;
    final snapshot = _visibilitySoloSnapshot;
    _visibilitySoloSnapshot = null;
    if (snapshot == null) {
      return;
    }
    _writeEyes(snapshot);
  }

  /// Writes each row's eye OUTSIDE history — the solo is display, not an
  /// edit (F-125). Through the repository's anywhere seam; rows deleted
  /// during the solo have nothing to restore (skip).
  void _writeEyes(Map<LayerId, bool> eyes) {
    eyes.forEach((layerId, visible) {
      try {
        _project.repository.updateLayer(
          layerId: layerId,
          update: _eyeRestoredTo(visible),
        );
      } on StateError {
        // Layer gone.
      }
    });
  }

  /// Keeps the solo mode consistent after active-layer/cut changes: same
  /// cut → re-solo to the new active row; different cut → exit (restore).
  ///
  /// 🚨THIS RUNS AFTER EVERY UNDO THAT MOVES THE DOCUMENT
  /// (`refreshAfterCutCommand`), so nothing it writes may be a step: a
  /// re-solo that wrote history is what kept undo walking in place (F-125).
  void syncVisibilitySolo() {
    if (!_layerVisibilitySoloEnabled) {
      return;
    }
    if (_timeline.editingSession.activeCutId != _visibilitySoloCutId) {
      exitVisibilitySolo();
    } else {
      _applyVisibilitySolo();
    }
  }

  /// Toggles an SE row's solo (pro semantics: multiple solos stack).
  void toggleLayerSolo(LayerId layerId) {
    soloedSeLayerIds.value = toggledSet(
      soloedSeLayerIds.value,
      layerId,
    );
    _changes.refreshLiveAudioSchedule();
    _changes.notifyChanged();
  }
}
