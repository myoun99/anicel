import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🗣️I-126 (유저 2026-10-23) — WHERE THE TIMELINE STANDS, THE STORYBOARD
/// STANDS: 「기본적으로 서로 서있는거 동기화되도록 … 글로벌에도 있는
/// 행이면 같은곳에 서있고, 아니면 비디오행에 서있도록」. The other half,
/// a storyboard stand seating the timeline, is F-187's
/// (`where_the_storyboard_stands_the_timeline_stands_test.dart`).
///
/// [conteTrackProject]: cut-1 holds a conte, cut-2 none, and S1 is the
/// track's.
void main() {
  const conteId = LayerId('cut-1-conte');
  final conteRow = LayerRowAddress(trackConteRowId(conteTrackId));
  const vRow = TrackRowAddress(conteTrackId);

  EditorSessionManager session() {
    final manager = EditorSessionManager(initialProject: conteTrackProject());
    addTearDown(manager.dispose);
    manager.selectCut(const CutId('cut-1'));
    manager.selectLayer(conteCelId);
    return manager;
  }

  test('an S row stood on in the timeline is where the storyboard stands', () {
    final s = session();

    s.selectLayer(conteSeId);

    expect(s.selectedRow, const LayerRowAddress(conteSeId));
    s.claimStoryboardRow();
    expect(s.currentRow, const LayerRowAddress(conteSeId));
  });

  test('the conte stood on in the timeline is the storyboard\'s conte row', () {
    final s = session();

    s.selectLayer(conteId);

    expect(s.selectedRow, conteRow);
  });

  test('a lane stood on in the timeline is that lane of the storyboard\'s '
      'row — the S row\'s, and the conte row\'s', () {
    final s = session();

    s.standOnRow(const LaneRowAddress(conteSeId, 'position'));
    expect(
      s.storyboardStandingRow,
      const LaneRowAddress(conteSeId, 'position'),
    );

    s.standOnRow(const LaneRowAddress(conteId, 'position'));
    expect(
      s.storyboardStandingRow,
      LaneRowAddress(conteRow.layerId, 'position'),
    );
  });

  test('a row the storyboard does not show — a cel — stands it on the V '
      'row', () {
    final s = session();
    s.standOnRow(
      const LayerRowAddress(conteSeId),
      panel: WorkingPanel.storyboard,
    );
    expect(s.selectedRow, const LayerRowAddress(conteSeId));

    s.selectLayer(conteCelId);

    expect(s.selectedRow, vRow);
  });

  test('⛔a stand made in the storyboard is its own: where the timeline has '
      'no such row it keeps its own (F-187), and that writes nothing back', () {
    final s = session();
    s.selectCut(const CutId('cut-2'));
    s.selectLayer(const LayerId('cut-2-cel'));

    s.standOnRow(conteRow, panel: WorkingPanel.storyboard);

    expect(
      s.activeLayerId,
      const LayerId('cut-2-cel'),
      reason: 'cut-2 holds no conte — 「…그냥 그대로둠. 아무것도 안하고」',
    );
    expect(s.selectedRow, conteRow, reason: 'where the press stood it');
  });

  test('a storyboard on the screen hears its row move under a timeline stand '
      'that moves no layer; one off it hears nothing, and reads its row when '
      'it opens', () {
    final s = session();
    s.selectLayer(conteSeId);
    var heard = 0;
    s.addListener(() => heard++);

    s.standOnRow(const LaneRowAddress(conteSeId, 'position'));
    expect(heard, 0, reason: 'no storyboard on the screen');

    final surface = Object();
    s.standing.panelInSight(
      WorkingPanel.storyboard,
      surface: surface,
      inSight: true,
    );
    s.standOnRow(const LayerRowAddress(conteSeId));
    expect(heard, 1, reason: 'its lit row went from the V row back to S1');

    s.standOnRow(const LayerRowAddress(conteSeId));
    expect(heard, 1, reason: 'standing where it stands moves nothing');
  });
}
