import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/folder_bands.dart';

/// THE FOLDER BANDS ARE MEASURED.
///
/// A folder row paints as the union of its members' exposures — the BAND
/// (folder-row parity, R10). The cache that builds it was carved out of the
/// session as `_FolderBands` on 2026-09-02, and the adversarial check found
/// that nothing noticed when it stopped filling: every query fell back to
/// 「no members, no runs, the folder itself」 and 157 tests stayed green. So
/// the band's three questions are asked here, against the session, with the
/// answers the model gives — and the cache's identity contract, which is the
/// reason it exists at all (R5 #2: the same band instance while nothing about
/// the folder changed, a NEW one the moment something did).
void main() {
  /// A session whose active row sits inside a folder, with a cel drawn at
  /// the first frame.
  (EditorSessionManager, LayerId member, LayerId folder) sessionWithFolder() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final member = s.activeLayer!.id;
    s.folders.groupActiveLayerIntoFolder();
    final folder = s.activeCutOrNull!.layers.folderLayers.single.id;
    s.selectLayer(member);
    return (s, member, folder);
  }

  test('a folder\'s band members are its subtree', () {
    final (s, member, folder) = sessionWithFolder();
    expect(
      bandsOf(s).folderBandMembersOf(folder).map((l) => l.id),
      [member],
      reason: 'the cache is filled from the layer stack; empty means it '
          'never was',
    );
  });

  test('a folder\'s runs are the union of its members\' exposures', () {
    final (s, _, folder) = sessionWithFolder();
    final runs = bandsOf(s).folderBandRunsOf(folder);
    expect(runs, hasLength(1), reason: 'one cel drawn at the first frame');
    expect(runs.single.start, 0);
    expect(runs.single.endExclusive, greaterThan(0));
  });

  test('the band is the folder carrying the union as its timeline', () {
    final (s, _, folder) = sessionWithFolder();
    final folderLayer = s.activeCutOrNull!.layers.byId(folder)!;
    final band = bandsOf(s).folderBandLayerFor(folderLayer);
    expect(band.id, folder);
    expect(band.timeline.keys, [0], reason: 'one run, so one exposure');
    expect(
      identical(bandsOf(s).folderBandLayerFor(folderLayer), band),
      isTrue,
      reason: 'nothing changed, so the SAME instance — repaint, the tile '
          'bake key and the row memo all compare the Layer instance',
    );
  });

  test('a member\'s own change keeps the band; the folder\'s own change '
      'renews it', () {
    final (s, member, folder) = sessionWithFolder();
    final band = bandsOf(s).folderBandLayerFor(s.activeCutOrNull!.layers.byId(folder)!);

    s.layerSwitches.toggleLayerVisibility(member);
    expect(
      identical(
        bandsOf(s).folderBandLayerFor(s.activeCutOrNull!.layers.byId(folder)!),
        band,
      ),
      isTrue,
      reason: 'the member\'s eye moved no exposure and the folder instance '
          'is the one the band was built from',
    );

    s.layerSwitches.toggleLayerVisibility(folder);
    final renewed = bandsOf(s).folderBandLayerFor(
      s.activeCutOrNull!.layers.byId(folder)!,
    );
    expect(identical(renewed, band), isFalse);
    expect(
      renewed.isVisible,
      isFalse,
      reason: 'R5 #2 — a band keyed on the union alone handed back the clone '
          'from BEFORE the folder\'s eye flipped, and the twirl and the eye '
          'read as dead controls',
    );
  });
}

/// The band cache under its OWN name.
///
/// 🚨A collaborator is only reachable by `tool/mutation_run.dart` through a
/// test that IMPORTS it, and every pin here used to arrive through
/// [EditorSessionManager] — so 63 of the 71 files under `lib/src/ui/session/`
/// reported UNNAMED and the campaign skipped exactly the code round 8 wrote.
FolderBands bandsOf(EditorSessionManager s) => s.folderBands;
