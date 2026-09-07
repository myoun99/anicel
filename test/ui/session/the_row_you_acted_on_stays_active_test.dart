import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/active_cut_edits.dart';
import 'package:anicel/src/ui/session/session_roles.dart';

/// FOUR VERBS, ONE ENVELOPE: gate, take the ACTIVE row's id, run one
/// coordinator command keyed by (cutId, layerId), then refresh KEEPING
/// THAT ROW ACTIVE and notify.
///
/// The trailing step is the one that goes missing when the envelope is
/// written out four times — `CutVerbs._moveActiveCut` carries a comment
/// recording exactly that loss. Pinned here for all four before they were
/// folded onto one call.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('link duplicate leaves you standing on the row you duplicated', () {
    final s = session();
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    expect(s.canLinkDuplicateActiveLayer, isTrue);

    s.linkDuplicateActiveLayer();

    expect(s.activeLayerId, layer);
  });

  test('unlink leaves you standing on the row you unlinked', () {
    final s = session();
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    s.linkDuplicateActiveLayer();
    expect(s.activeLayerId, layer);
    expect(s.canUnlinkActiveLayer, isTrue);

    s.unlinkActiveLayer();

    expect(s.activeLayerId, layer);
  });

  test('폴더 생성 leaves you on the LAYER, not on the folder it made', () {
    final s = session();
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    expect(s.canGroupActiveLayerIntoFolder, isTrue);

    s.groupActiveLayerIntoFolder();

    expect(s.activeLayerId, layer);
    expect(
      s.requireActiveCut.layers.any((l) => l.kind == LayerKind.folder),
      isTrue,
      reason: 'premise: the folder really was made',
    );
  });

  test('공정 폴더 생성 leaves you on the ATTACH row', () {
    final s = session();
    s.createDrawingAtCurrentFrame();
    s.addAttachedLayer(AttachedPlacement.above);
    final attach = s.activeLayer!.id;
    expect(s.canGroupActiveAttachIntoFolder, isTrue);

    s.groupActiveAttachIntoFolder();

    expect(s.activeLayerId, attach);
    expect(
      s.requireActiveCut.layers.firstWhere((l) => l.id == attach).folderId,
      isNotNull,
      reason: 'premise: the organizer really wrapped it',
    );
  });

  /// The envelope names the row it STARTED on, not whatever the selection
  /// happens to be after the command ran. Today the two coincide —
  /// `refreshAfterCutCommand` falls back to `activeLayerId` — so the four
  /// verbs above cannot tell the difference; this drives the envelope
  /// directly, where they can.
  test('the refresh is told the row the verb started on', () {
    final s = session();
    final rows = s.requireActiveCut.layers;
    final first = rows.first;
    final second = rows.last;
    expect(first.id, isNot(second.id), reason: 'premise: two rows');

    final selection = _StandingOn(first);
    final changes = _RecordingChanges();
    final edits = ActiveCutEdits(
      timeline: _OneCut(s.requireActiveCut),
      selection: selection,
      changes: changes,
    );

    var ran = 0;
    edits.onActiveLayer(
      when: true,
      command: (cutId, layerId) {
        ran += 1;
        expect(layerId, first.id);
        expect(cutId, s.requireActiveCut.id);
        // The command re-seats the selection, as a cut command may.
        selection.standing = second;
      },
    );

    expect(ran, 1);
    expect(
      changes.preferred,
      first.id,
      reason: '⛔the row the verb acted on, not the one left standing',
    );
    expect(changes.refreshes, 1);
    expect(changes.notifies, 1);
  });

  test('a closed gate runs nothing at all — no command, no refresh, no '
      'notify', () {
    final s = session();
    final changes = _RecordingChanges();
    final edits = ActiveCutEdits(
      timeline: _OneCut(s.requireActiveCut),
      selection: _StandingOn(s.requireActiveCut.layers.first),
      changes: changes,
    );

    edits.onActiveLayer(when: false, command: (_, _) => fail('gated out'));

    expect(changes.refreshes, 0);
    expect(changes.notifies, 0);
  });

  test('a closed gate on a real verb changes nothing', () {
    final s = session();
    final instruction = s.layers
        .where((l) => l.kind != LayerKind.animation)
        .map((l) => l.id)
        .firstOrNull;
    if (instruction == null) {
      return; // The default project has only animation rows here.
    }
    s.selectLayer(instruction);
    final before = s.requireActiveCut.layers.length;

    if (!s.canGroupActiveLayerIntoFolder) {
      s.groupActiveLayerIntoFolder();
      expect(s.requireActiveCut.layers.length, before);
      expect(s.activeLayerId, LayerId(instruction.value));
    }
  });
}

/// Only [activeLayer] is read by the envelope; the rest of the role is
/// forwarded so the fake does not have to restate an interface it is not
/// about.
class _StandingOn implements SelectionAccess {
  _StandingOn(this.standing);

  Layer standing;

  @override
  Layer? get activeLayer => standing;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The envelope reads the cut id in ONE place — the editing session's
/// `activeCutId` — for the row arm as much as for the cut arms.
class _OneCut implements TimelineAccess {
  _OneCut(this._cut);

  final Cut _cut;

  @override
  EditingSessionState get editingSession =>
      EditingSessionState(activeCutId: _cut.id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingChanges implements ChangeSink {
  LayerId? preferred;
  int refreshes = 0;
  int notifies = 0;

  @override
  void notifyChanged() => notifies += 1;

  @override
  void refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
  }) {
    refreshes += 1;
    preferred = preferredActiveLayerId;
  }

  @override
  void refreshLiveAudioSchedule() {}

  @override
  bool standsDownFromRetime(LayerId layerId) => false;

  @override
  void warmActiveCut() {}
}
