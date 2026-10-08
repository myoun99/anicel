import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨F-304 (유저 2026-10-06): 「무거운 상태에서 저장버튼누르면 화면이 멈추고
/// … 멈추는게 아니라 뭔가 하고있다라는걸 제대로 표시하기위해」.
///
/// The save window comes up first now — but a window drawn over a frozen
/// isolate is a picture, not a spinner. What froze it was the cels still in
/// RAM: each one copied tile by tile into an entry, and the whole lot copied
/// again into the save isolate's message (🧪40 whole-canvas cels: 773ms and
/// 1,211ms of a 2,005ms block — `a_heavy_save_holds_the_screen_benchmark_
/// test`). A cel crosses the way the park road's do now, and the screen
/// gets its turn after each one.
void main() {
  test('🚨the event loop runs between two cels a save serialises', () async {
    final folder = Directory.systemTemp.createTempSync('screen-turns');
    deleteAfterSessionEnds(folder);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    for (var i = 0; i < 3; i += 1) {
      s.cutVerbs.createCut();
      drawOnCurrentFrame(s);
    }
    final events = <String>[];
    // Something else that wants the UI isolate — a frame, a spinner — as a
    // zero timer that asks again each time it is answered, until the last
    // cel is out (past it, the isolate's own wait answers it anyway).
    var asking = true;
    AnicelFileService.debugAfterScreenTurn = () {
      events.add('cel');
      asking = events.where((event) => event == 'cel').length < 3;
    };
    addTearDown(() => AnicelFileService.debugAfterScreenTurn = null);
    void ask() {
      if (!asking) {
        return;
      }
      events.add('turn');
      Timer.run(ask);
    }

    Timer.run(ask);
    await s.projectDoor.saveProjectToFile(
      '${folder.path}/three.anicel',
      asked: SaveAsked.byAPerson,
    );
    asking = false;

    final cels = [
      for (final (index, event) in events.indexed)
        if (event == 'cel') index,
    ];
    expect(cels, hasLength(3), reason: '⛔premise: three cels in RAM');
    for (var i = 1; i < cels.length; i += 1) {
      expect(
        events.sublist(cels[i - 1], cels[i]),
        contains('turn'),
        reason: 'between cel ${i - 1} and cel $i the screen had no turn',
      );
    }
  });

  test('a cel in RAM crosses as ONE serialised payload — never an entry of '
      'tile copies for the message to copy again', () {
    final source = File(
      'lib/src/services/persistence/anicel_file_service.dart',
    ).readAsStringSync();
    expect(source, contains('encodeCelEntryFromSurface('));
    expect(source, contains('TransferableTypedData.fromList('));
    expect(source, isNot(contains('AnicelCelEntry.fromSurface(')));
  });
}
