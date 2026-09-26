import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/session/visibility_solo.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**THE FILE NEVER SEES A VIEW STATE** (F-153).
///
/// 🗣️유저 2026-09-18: 「활성레이어 솔로는 **저장시 저장안되도록**. 지금 솔로
/// on한상태로 저장하고 열면 **적용된채로 모드는 off**되있는 상태」 — answered
/// on `solo-and-the-saved-file` with 「**저장이 솔로 이전의 눈을 기록한다**」.
///
/// The solo really does flip the rows' eyes (유저's own rule, 2026-08-29:
/// 「REAL eye flips」), so a save cannot decline to look at them — it asks
/// the snapshot the solo is already holding for its own exit.
///
/// ⚠️**THE SE ROWS ARE THE POINT OF THE FIRST TEST.** A track's SE rows
/// and its transition row live BESIDE the cuts and reach a cut's row list
/// as display clones; the solo turns them off like any other row. The
/// first version of this fix walked `tracks → cuts → layers` and so put
/// back only a cut's eyes — the SE rows went into the file soloed, and a
/// pin that looked only at drawing rows would have called it fixed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Held by its own type — `tool/mutation_run.dart` picks a file's
  /// witnesses by which tests IMPORT it.
  VisibilitySolo soloOf(EditorSessionManager s) => s.visibilitySolo;

  /// ⛔**THE INSTRUMENT WALKS THE TREE ITSELF.** Asking the product where
  /// the rows live would go blind in exactly the place the product was
  /// wrong. Cut layers AND the tracks' SE rows, by hand.
  Map<LayerId, bool> eyesIn(Project project) {
    final eyes = <LayerId, bool>{};
    for (final track in project.tracks) {
      for (final layer in track.seLayers) {
        eyes[layer.id] = layer.isVisible;
      }
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          eyes[layer.id] = layer.isVisible;
        }
      }
    }
    return eyes;
  }

  Map<LayerId, bool> eyesOf(EditorSessionManager s) =>
      eyesIn(s.repository.requireProject());

  String scratchFile(String name) {
    final dir = Directory.systemTemp.createTempSync('anicel-$name');
    deleteAfterSessionEnds(dir);
    return '${dir.path}/$name.anicel';
  }

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  Future<EditorSessionManager> reopened(String path) async {
    final s = await openedSession(path);
    addTearDown(s.dispose);
    return s;
  }

  /// The first SE row — a TRACK fixture, not one of the cut's layers.
  LayerId seRowOf(EditorSessionManager s) =>
      s.repository.requireProject().tracks.first.seLayers.first.id;

  test('a save while the solo is up records the eyes from BEFORE it — the '
      'track SE rows included', () async {
    final path = scratchFile('solo-save');
    final s = session();

    // One row deliberately OFF before the solo: 「what the eyes were」 must
    // not be readable as 「everything on」, or a save that writes every eye
    // true passes without ever asking the snapshot.
    final offBefore = seRowOf(s);
    s.layerSwitches.toggleLayerVisibility(offBefore);
    final before = eyesOf(s);
    expect(
      before[offBefore],
      isFalse,
      reason: '⛔전제: the row really is off before the solo',
    );

    soloOf(s).toggleLayerVisibilitySolo();

    // ⛔전제, and the one the first fix failed: the solo really does reach
    // the TRACK's rows. Without this the pin below could be measuring a
    // solo that never touched them.
    final active = s.activeLayerId!;
    final soloed = eyesOf(s);
    expect(soloed[active], isTrue);
    for (final row in soloed.keys.where((id) => id != active)) {
      expect(
        soloed[row],
        isFalse,
        reason: '⛔전제: the solo turned $row off, SE rows included',
      );
    }

    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    expect(
      eyesIn((await reopened(path)).repository.requireProject()),
      before,
      reason: '🚨유저: 「저장이 솔로 이전의 눈을 기록한다」 — every row, '
          'not the drawing rows only',
    );
    expect(
      eyesOf(s),
      soloed,
      reason: '⛔the save changed the FILE, never what is on screen',
    );
  });

  test('and once the solo is off, a save records the eyes as they are', () async {
    final path = scratchFile('solo-left');
    final s = session();

    // 🚨THE CONTROL. A door that put the snapshot back on every save
    // forever passes the pin above and loses every eye the person turns
    // off afterwards.
    soloOf(s).toggleLayerVisibilitySolo();
    soloOf(s).toggleLayerVisibilitySolo();
    expect(soloOf(s).layerVisibilitySoloEnabled, isFalse);

    final byHand = seRowOf(s);
    s.layerSwitches.toggleLayerVisibility(byHand);
    final asLeft = eyesOf(s);
    expect(asLeft[byHand], isFalse, reason: '⛔전제: the hand turned it off');

    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    expect(
      eyesIn((await reopened(path)).repository.requireProject()),
      asLeft,
      reason: '솔로가 끝난 뒤의 눈은 손이 정한 그대로다',
    );
  });
}
