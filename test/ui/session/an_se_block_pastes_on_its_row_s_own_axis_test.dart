import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/timeline/timeline_defaults.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';

/// F-115 (유저 2026-09-12): 「se 블록 복붙, 우선 복사하고나서는 독립 붙여넣기만
/// 가능. 왜냐하면 링크붙여넣기의 차이점이 없기때문. 그리고 지금 붙여넣기하면
/// 기존 블럭이 이상하게 움직일뿐 붙여넣어지지않음. 제대로 붙여넣어지도록.
/// 그리고 내용은 이름/대사/링크된 오디오 등 모든 정보가 똑같음. 프레임블록쪽
/// 복붙이랑 로직 통일할거 통일해서 따름. 붙여넣는 위치던 겹쳐있으면
/// 어떻게할지던.」
///
/// A track-owned SE row keys its blocks on the track's GLOBAL frames and a cut
/// shows a projection of it (F-102). Copy, cut and paste ask ONE question —
/// where on the active row they act — and hand the answer to a controller
/// that reads and writes the track's row. From cut 2 on, an answer left on
/// the cut's axis reads, lifts and inserts on cut 1's frames: nothing pastes
/// and the blocks after the playhead slide — 「기존 블럭이 이상하게
/// 움직일뿐」.
///
/// The collaborator the three verbs live in — named so
/// `tool/mutation_run.dart` runs this file for it.
FrameClipboard clipboardOf(EditorSessionManager session) => session.clipboard;

void main() {
  late EditorSessionManager session;
  late LayerId s1;
  late LayerId s2;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    s1 = session.activeTrack.seLayers[0].id;
    s2 = session.activeTrack.seLayers[1].id;
  });
  tearDown(() => session.dispose());

  /// The track's own row — what every verb commits to.
  Layer row(LayerId id) =>
      session.activeTrack.seLayers.firstWhere((layer) => layer.id == id);

  /// Opens cut 2 after cut 1 and stands in it; returns where it starts.
  int openCut2() {
    session.cutVerbs.createCut();
    final start = session.activeCutGlobalStartFrame;
    expect(
      start,
      defaultCutDurationFrames,
      reason: 'fixture premise: cut 2 is active and starts where cut 1 ends',
    );
    return start;
  }

  void stand(LayerId id, int localFrame) {
    session.clearAllSelections();
    session.selectLayer(id);
    session.selectFrameIndex(localFrame);
  }

  /// An SE entry on [id] at [localFrame] of the ACTIVE cut.
  Frame entry(
    LayerId id,
    int localFrame, {
    required String speaker,
    String dialogue = '',
    int length = 2,
  }) {
    stand(id, localFrame);
    session.seEntries.createSeEntryAtCurrentFrame(
      name: dialogue,
      seName: speaker,
      lengthFrames: length,
    );
    final global = localFrame + session.activeCutGlobalStartFrame;
    final frameId = row(id).timeline[global]?.frameId;
    expect(
      frameId,
      isNotNull,
      reason: 'fixture premise: $speaker starts at global $global',
    );
    return row(id).frames.firstWhere((frame) => frame.id == frameId);
  }

  /// The block STARTING at [globalFrame] on [id]'s row, or null.
  ({Frame frame, int length})? blockAt(LayerId id, int globalFrame) {
    final exposure = row(id).timeline[globalFrame];
    final frameId = exposure?.frameId;
    if (frameId == null) {
      return null;
    }
    return (
      frame: row(id).frames.firstWhere((frame) => frame.id == frameId),
      length: exposure!.length ?? 1,
    );
  }

  group('🚨the verbs act on the track\'s row, where the playhead is on it', () {
    test('in cut 2, a copied block pastes AT the playhead and what was after '
        'it moves aside by the pasted length', () {
      final cut2 = openCut2();
      final a = entry(s1, 1, speaker: 'A');
      final b = entry(s1, 6, speaker: 'B', length: 1);

      stand(s1, 1);
      session.copyFrameAtCurrentFrame();
      stand(s1, 3);
      session.pasteIndependentFrameAtCurrentFrame();

      expect(
        blockAt(s1, cut2 + 1)?.frame.id,
        a.id,
        reason: 'the source stays where it was — 「기존 블럭이 이상하게 움직일뿐」',
      );
      final pasted = blockAt(s1, cut2 + 3);
      expect(
        pasted?.frame.seName,
        'A',
        reason: '「붙여넣어지지않음」 — it lands at the playhead',
      );
      expect(pasted?.length, 2, reason: 'the clip brings its length');
      expect(
        blockAt(s1, cut2 + 8)?.frame.id,
        b.id,
        reason: 'what was after the playhead moves aside by that length',
      );
    });

    test('the same presses in cut 1, where the two axes agree', () {
      final a = entry(s1, 1, speaker: 'A');
      final b = entry(s1, 6, speaker: 'B', length: 1);

      stand(s1, 1);
      session.copyFrameAtCurrentFrame();
      stand(s1, 3);
      session.pasteIndependentFrameAtCurrentFrame();

      expect(blockAt(s1, 1)?.frame.id, a.id);
      expect(blockAt(s1, 3)?.frame.seName, 'A');
      expect(blockAt(s1, 8)?.frame.id, b.id);
    });

    test('in cut 2, 잘라내기 lifts the block under the playhead and leaves its '
        'hole — and cut 1 is not touched', () {
      final cut2 = openCut2();
      final a = entry(s1, 1, speaker: 'A');
      final b = entry(s1, 4, speaker: 'B', length: 1);

      stand(s1, 1);
      clipboardOf(session).cutRunAtCurrentFrame();

      expect(
        row(s1).frames.map((frame) => frame.id),
        isNot(contains(a.id)),
        reason: 'the lifted block leaves the row',
      );
      expect(
        blockAt(s1, cut2 - 1),
        isNull,
        reason: 'nothing slid into cut 1',
      );
      // ⚠️A HOLE, not a close-up — the splice's own law (유저 08-15 ⑳:
      // 「프레임 잘라내기하면 뒤 프레임을 앞당김. 이딴거 누가넣으랫지?」). The
      // first draft of this line expected B pulled forward by the lifted
      // length; the row was right to leave it.
      expect(
        blockAt(s1, cut2 + 4)?.frame.id,
        b.id,
        reason: 'what was after the lifted block stays where it stood',
      );
      expect(blockAt(s1, cut2 + 1), isNull, reason: 'the lift left its hole');
    });

    test('a selection means exactly its cells — also where a block spills in '
        'from cut 1', () {
      // A: made in cut 1 at 22, four frames long — two of them run into cut 2.
      entry(s1, 22, speaker: 'A', length: 4);
      final cut2 = openCut2();
      entry(s1, 2, speaker: 'B');

      stand(s1, 0);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: s1,
        startIndex: 0,
        endIndexExclusive: 4,
      );
      session.copyFrameAtCurrentFrame();
      stand(s1, 10);
      session.pasteIndependentFrameAtCurrentFrame();

      final first = blockAt(s1, cut2 + 10);
      final second = blockAt(s1, cut2 + 12);
      expect(
        first?.frame.seName,
        'A',
        reason: 'cut 2\'s first two cells are the end of A',
      );
      expect(
        first?.length,
        2,
        reason: 'only the cells the selection covered — not A counted from '
            'where cut 1 started it',
      );
      expect(second?.frame.seName, 'B');
      expect(second?.length, 2);
    });

    test('with nothing selected, the block under the playhead is the WHOLE '
        'block — a spill-in is the block cut 1 started, as Delete takes it', () {
      entry(s1, 22, speaker: 'A', length: 4);
      final cut2 = openCut2();

      stand(s1, 1);
      session.copyFrameAtCurrentFrame();
      stand(s1, 10);
      session.pasteIndependentFrameAtCurrentFrame();

      final pasted = blockAt(s1, cut2 + 10);
      expect(pasted?.frame.seName, 'A');
      expect(
        pasted?.length,
        4,
        reason: 'the block runs four frames on its row, two of them in cut 1 '
            '— the block `deleteCellForLayer` removes from the same press',
      );
    });

    test('a band across both S rows pastes on each row at the same cells', () {
      final cut2 = openCut2();
      entry(s1, 1, speaker: 'A');
      stand(s1, 1);
      session.copyFrameAtCurrentFrame();

      stand(s1, 5);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: s1,
        startIndex: 5,
        endIndexExclusive: 7,
        layerIds: [s1, s2],
      );
      session.pasteIndependentFrameAtCurrentFrame();

      expect(blockAt(s1, cut2 + 5)?.frame.seName, 'A');
      expect(
        blockAt(s2, cut2 + 5)?.frame.seName,
        'A',
        reason: 'the other swept row resolves the band on its OWN axis',
      );
    });
  });

  test('⛔an SE block offers no LINKED paste — 「링크붙여넣기의 차이점이 '
      '없기때문」', () {
    entry(s1, 1, speaker: 'A');
    stand(s1, 1);
    session.copyFrameAtCurrentFrame();
    stand(s1, 5);

    expect(
      session.canPasteIndependentFrameAtCurrentFrame,
      isTrue,
      reason: 'premise: the paste the row keeps',
    );
    expect(clipboardOf(session).canPasteLinkedFrameAtCurrentFrame, isFalse);
  });

  group('the pasted block says what the source says — 「이름/대사/링크된 오디오 '
      '등 모든 정보가 똑같음」', () {
    // In cut 1, where the two axes agree: these measure the content alone.
    void linkDoorSound(Frame to) {
      session.cutCommandCoordinator.updateLayerAudioClips(
        cutId: session.activeCutId,
        layerId: s1,
        audioClips: [
          ...row(s1).audioClips,
          AudioClip(
            filePath: 'C:/sounds/door.wav',
            frameId: to.id,
            offsetFrames: 3,
            gain: 0.5,
          ),
        ],
      );
    }

    test('its dialogue and its speaker', () {
      final a = entry(s1, 1, speaker: 'A', dialogue: 'hello');
      stand(s1, 1);
      session.copyFrameAtCurrentFrame();
      stand(s1, 5);
      session.pasteIndependentFrameAtCurrentFrame();

      final pasted = blockAt(s1, 5)!.frame;
      expect(pasted.id, isNot(a.id), reason: 'premise: a new entry');
      expect(pasted.seName, 'A', reason: '「이름」');
      expect(
        pasted.name,
        'hello',
        reason: '「대사」 — an SE row lets two entries share their text (its '
            'rename allows it), so the copy keeps it; a drawing row\'s name '
            'is its identity and stays behind (F-62)',
      );
    });

    test('its sound, as a sound of its own', () {
      final a = entry(s1, 1, speaker: 'A');
      linkDoorSound(a);
      stand(s1, 1);
      session.copyFrameAtCurrentFrame();
      stand(s1, 5);
      session.pasteIndependentFrameAtCurrentFrame();

      final pasted = blockAt(s1, 5)!.frame;
      expect(
        [
          for (final clip in row(s1).audioClips)
            if (clip.frameId == pasted.id)
              (clip.filePath, clip.offsetFrames, clip.gain),
        ],
        [('C:/sounds/door.wav', 3, 0.5)],
        reason: '「링크된 오디오」 — the sound belongs to the instance, so the '
            'new instance carries a copy of it',
      );
      expect(
        row(s1).audioClips.where((clip) => clip.frameId == a.id),
        hasLength(1),
        reason: 'the source keeps its own',
      );
    });

    test('잘라내기 then paste brings the sound back with the block', () {
      final a = entry(s1, 1, speaker: 'A');
      linkDoorSound(a);
      stand(s1, 1);
      clipboardOf(session).cutRunAtCurrentFrame();
      expect(
        row(s1).audioClips,
        isEmpty,
        reason: 'premise: the lift took the sound with its instance (REC1-A)',
      );

      stand(s1, 5);
      session.pasteIndependentFrameAtCurrentFrame();

      final pasted = blockAt(s1, 5)!.frame;
      expect(
        [for (final clip in row(s1).audioClips) (clip.frameId, clip.filePath)],
        [(pasted.id, 'C:/sounds/door.wav')],
        reason: 'the clipboard holds what was put on it — the sound included',
      );
    });

    test('the block and its sound land as ONE undo', () {
      final a = entry(s1, 1, speaker: 'A');
      linkDoorSound(a);
      stand(s1, 1);
      session.copyFrameAtCurrentFrame();
      stand(s1, 5);
      final steps = session.historyManager.undoCount;
      session.pasteIndependentFrameAtCurrentFrame();
      expect(session.historyManager.undoCount, steps + 1);

      session.undo();

      expect(blockAt(s1, 5), isNull);
      expect(row(s1).audioClips.map((clip) => clip.frameId), [a.id]);
    });
  });
}
