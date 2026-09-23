import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/toggle_id_in_set_command.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★**UNDOING SOMETHING THAT DID NOT MOVE THE DOCUMENT MUST NOT TIDY
/// THE DOCUMENT UP.** `_stepHistory` ran `refreshAfterCutCommand` after
/// every step, and that verb dropped the copied frame (until F-152) and
/// clears the frame-range selection — the housekeeping a CUT command owes.
/// So pressing Ctrl+Z after a brush stroke, a pixel verb or an onion-skin
/// toggle threw away what the user had copied and the band they had drawn,
/// for an edit that moved no row.
///
/// 🔬**THE WHOLE FAMILY.** Of the 53 command classes that enter history,
/// five never touch the repository — the three pixel commands,
/// `ToggleIdInSetCommand`, and `RekeyBrushFramesCommand` (which is only
/// ever composed into a step that also moves layers, so its group does move
/// the document and does get the tidy-up). One question answers all of
/// them: did the project object change.
///
/// ⚠️**THE WITNESS IS A `ToggleIdInSetCommand` IN THE SESSION'S OWN
/// HISTORY** — a real command that enters the history `undo()` walks and
/// touches no project. ⛔A stroke driven through a standalone
/// `BrushFrameEditingCoordinator` is NOT a witness — it never enters the
/// session's history, so `undo()` steps something else entirely and the
/// test passes or fails for the wrong reason. That mistake cost a round.
///
/// ↩️It was the onion-skin toggle, the session verb that pushed that command
/// (유저 2026-08-29: 「아무튼 어니언 적용 미적용만 되면 되는건데」), until
/// F-162 (유저 2026-09-24: 「어니언/비지블솔로 등 내가 말한건 빼도록」) took
/// the onion out of the history. The command's other door — the property
/// lane twirl — is the workspace's, which a session test cannot press, so
/// the command is executed here as that door executes it.
void main() {
  /// What the lane twirl pushes: one row's membership of a view set.
  ValueNotifier<Set<LayerId>> pushANonDocumentStep(
    EditorSessionManager session,
    LayerId layerId,
  ) {
    final twirled = ValueNotifier<Set<LayerId>>(<LayerId>{});
    addTearDown(twirled.dispose);
    session.historyManager.execute(
      ToggleIdInSetCommand(
        notifier: twirled,
        layerId: layerId,
        debugLabel: 'Toggle layer lanes',
      ),
    );
    return twirled;
  }

  EditorSessionManager sessionWithADrawing() {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    session.createDrawingAtCurrentFrame();
    return session;
  }

  test('🚨undoing a step that moved no row keeps the copied frame and the '
      'band', () {
    final session = sessionWithADrawing();
    addTearDown(session.dispose);
    final layerId = session.activeLayer!.id;

    // Something on the frame board, and a band up.
    session.copyFrameAtCurrentFrame();
    session.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 2,
    );
    final banked = session.clipboard.bankedRowLayerIds;
    expect(banked, isNotEmpty, reason: 'fixture premise: the board holds one');
    expect(
      session.frameRangeSelection.value,
      isNotNull,
      reason: 'fixture premise: a band is up',
    );

    // An undoable edit that moves no row.
    pushANonDocumentStep(session, layerId);
    session.undo();

    expect(
      session.clipboard.bankedRowLayerIds,
      banked,
      reason: '⛔the board named cels in a cut this step did not touch',
    );
    expect(
      session.frameRangeSelection.value,
      isNotNull,
      reason: '⛔the band named rows this step did not move',
    );
  });

  test('and the step still does what it was for', () {
    final session = sessionWithADrawing();
    addTearDown(session.dispose);
    final layerId = session.activeLayer!.id;

    final twirled = pushANonDocumentStep(session, layerId);
    expect(
      twirled.value.contains(layerId),
      isTrue,
      reason: 'fixture premise: the step toggled',
    );

    session.undo();

    expect(
      twirled.value.contains(layerId),
      isFalse,
      reason: '🚨유저 2026-08-29: 「버튼 누르고 Ctrl+Z, 어니언이 돌아온다」 — '
          'staying silent about the DOCUMENT must not make the step itself '
          'stop undoing',
    );
  });

  test('⛔but a step that DOES move the document still tidies up', () {
    final session = sessionWithADrawing();
    addTearDown(session.dispose);
    final layerId = session.activeLayer!.id;

    // 🚨**THE BAND, NOT THE CLIPBOARD.** A first attempt used the frame
    // board here and the mutation caught it: 「the guard ALWAYS fires」 left
    // every test green, because creating a cut SWITCHES cuts and the board
    // was dropped on a cut switch anyway. It is dropped on nothing now
    // (F-161), so it witnesses the refresh even less. The witness has to be
    // something only `refreshAfterCutCommand` clears, on a step that stays
    // put.
    session.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(
      session.frameRangeSelection.value,
      isNotNull,
      reason: 'fixture premise: a band is up',
    );

    // A layer attribute — the project changes, the active cut does not.
    session.effectsAndFx.toggleLayerTransformFx(layerId);
    session.undo();

    expect(
      session.frameRangeSelection.value,
      isNull,
      reason: '🚨THE OTHER HALF OF THE LAW, and the reason this is not just '
          '「stop tidying up」: a step that moves rows must clear the band, '
          'because the band names rows by index and the indices moved',
    );
  });

  /// 🚨F-152 (유저 2026-09-16): 「복사하고 무언가 붙혀넣는다고 해서 복사한게
  /// 사라지지않게. 복사한거는 들고있음. 그 상태에서 여러군데 붙혀넣기
  /// 가능하도록」 — and F-161 (09-17) took the cut's edge away: 「복사는 항상
  /// 언제든 들고있게. 컷2의 레이어에서 붙여넣기 가능 … 보통 프로그램이
  /// 그러니까」. The band still goes on a step that moves rows; the COPY does
  /// not — it carries its cels, sounds and pictures by value and names no row
  /// by index.
  group('the copy is always in hand', () {
    test('paste, undo the paste, paste again', () {
      final session = sessionWithADrawing();
      addTearDown(session.dispose);
      session.copyFrameAtCurrentFrame();
      session.selectFrameIndex(5);
      session.pasteIndependentFrameAtCurrentFrame();
      expect(session.activeLayer!.timeline[5], isNotNull, reason: 'LIVENESS');

      session.undo();
      expect(
        session.activeLayer!.timeline[5],
        isNull,
        reason: 'premise: the step moved the document',
      );

      session.selectFrameIndex(9);
      session.pasteIndependentFrameAtCurrentFrame();
      expect(
        session.activeLayer!.timeline[9],
        isNotNull,
        reason: '「복사한거는 들고있음」 — the undo did not take it',
      );
    });

    test('a cut command keeps it', () {
      final session = sessionWithADrawing();
      addTearDown(session.dispose);
      session.copyFrameAtCurrentFrame();
      final banked = session.clipboard.bankedRowLayerIds;
      expect(banked, isNotEmpty, reason: 'fixture premise');

      session.cutVerbs.renameActiveCut('renamed');

      expect(session.clipboard.bankedRowLayerIds, banked);
    });

    test('🚨leaving its cut keeps it, and it pastes on the next cut\'s '
        'layer — 「컷2의 레이어에서 붙여넣기 가능」', () {
      final session = sessionWithADrawing();
      addTearDown(session.dispose);
      final cut1 = session.activeCutId!;
      session.copyFrameAtCurrentFrame();
      final banked = session.clipboard.bankedRowLayerIds;

      session.cutVerbs.createCut();
      expect(session.activeCutId, isNot(cut1), reason: 'premise: in cut 2');
      expect(session.clipboard.bankedRowLayerIds, banked);

      session.selectFrameIndex(3);
      expect(
        session.canPasteIndependentFrameAtCurrentFrame,
        isTrue,
        reason: 'the paste is lit in cut 2',
      );
      session.pasteIndependentFrameAtCurrentFrame();
      expect(
        session.activeLayer!.timeline[3],
        isNotNull,
        reason: 'it landed on cut 2\'s layer',
      );
    });

    test('picking a cut keeps it too', () {
      final session = sessionWithADrawing();
      addTearDown(session.dispose);
      final cut1 = session.activeCutId!;
      session.cutVerbs.createCut();
      session.createDrawingAtCurrentFrame();
      session.copyFrameAtCurrentFrame();
      final banked = session.clipboard.bankedRowLayerIds;
      expect(banked, isNotEmpty, reason: 'LIVENESS');

      session.selectCut(cut1);

      expect(session.clipboard.bankedRowLayerIds, banked);
    });
  });
}
