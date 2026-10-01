import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/conte_track_fixture.dart';

/// What the session hands its verbs — the active layer the kind toggle
/// works on, the stroke in flight, the disposed flag, the row the timeline
/// stands on — is READ where it is asked.
///
/// 🧪Pinned because each was moved off `SessionInternals` in the audit's
/// seventeenth family (2026-09-28) and a mutant that blinded it survived
/// every suite: nothing measured the positive half of the kind toggle, a
/// scrub or a row press under a live stroke, a publish after dispose, or a
/// row span asked while the two panels stand on different rows.
void main() {
  EditorSessionManager defaultSession() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  group('the kind toggle works on the active layer', () {
    test('an animation layer, with no storyboard row in the cut, toggles', () {
      final s = defaultSession();
      final layer = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      s.selectLayer(layer.id);
      expect(s.layerSwitches.canToggleTargetLayerKind, isTrue);

      s.layerSwitches.toggleTargetLayerKind();

      expect(s.layerById(layer.id)!.kind, LayerKind.storyboard);
    });

    test('a second storyboard row in the cut is refused, and says so', () {
      final s = defaultSession();
      final first = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      s.selectLayer(first.id);
      s.layerSwitches.toggleTargetLayerKind();
      expect(
        s.layerById(first.id)!.kind,
        LayerKind.storyboard,
        reason: '⛔premise: the cut holds a storyboard row now',
      );
      s.layerStack.addLayerOfKind(LayerKind.animation);
      expect(s.activeLayer!.kind, LayerKind.animation, reason: '⛔premise');

      expect(s.storyboardCursor.targetLayerStoryboardRefusal, isNotNull);
    });
  });

  group('a live stroke holds where the user stands', () {
    test('a scrub out of the cut does not park while the pen draws', () {
      final s = defaultSession();
      s.setBrushInputActive(true);
      addTearDown(() => s.setBrushInputActive(false));

      s.frameScrub.scrubGlobalFrame(s.activeCutFrameCount + 20);

      expect(s.editingSession.gapGlobalFrame, isNull);
    });

    test('a row press does not move the row while the pen draws', () {
      final s = defaultSession();
      final other = s.layers.firstWhere(
        (layer) => layer.id != s.activeLayerId && layer.kind.holdsDrawings,
      );
      final before = s.selectedRow;
      s.setBrushInputActive(true);
      addTearDown(() => s.setBrushInputActive(false));

      s.selectRow(LayerRowAddress(other.id));

      expect(s.selectedRow, before);
    });
  });

  test('a disposed session publishes no row', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.dispose();
    expect(() => s.standing.publishCurrentRow(), returnsNormally);
  });

  test('the row span is the TIMELINE row\'s, whatever the storyboard stands '
      'on', () {
    const conte = LayerId('cut-1-conte');
    // The cut's conte row: three panels, the span the timeline row selects.
    final s = EditorSessionManager(initialProject: conteTrackProject());
    addTearDown(s.dispose);
    s.selectCut(const CutId('cut-1'));
    // A LANE stood on in the storyboard stays the storyboard's — an S row
    // itself would stand on both panels under one address — and then the
    // TIMELINE is worked again, on its own row.
    s.standOnRow(
      const LaneRowAddress(conteSeId, 'position'),
      panel: WorkingPanel.storyboard,
    );
    s.standOnRow(const LayerRowAddress(conte));
    expect(
      [s.currentRow, s.storyboardStandingRow],
      [
        const LayerRowAddress(conte),
        const LaneRowAddress(conteSeId, 'position'),
      ],
      reason: '⛔premise: the two panels stand on different rows',
    );

    s.rangeSelections.selectRowSpanForCurrentRow();

    expect(s.frameRangeSelection.value?.spanLayerIds, [conte]);
  });
}
