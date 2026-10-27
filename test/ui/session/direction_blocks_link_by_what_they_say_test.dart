import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-72-direction-link (유저 2026-10-08): 「디렉션 레이어도 링크프레임
/// 시스템 작동하도록. 뭐냐면 아무것도 없으면 독립인건 동일한데,
/// 같은이름이라는 규칙을 시작이름,끝이름,지시 세개 같으면 같은 링크로서
/// 작동하도록 … 이름이 비우면 기호이름이란 시스템이잖아? 그거의 결과를 지시
/// 라는 항목으로」 — and Q1 (10-25): 「링크로 들어온다」, with its note:
/// 「독립붙여넣기나 복제는 프레임블록은 링크발동안되게 이름 없음으로
/// 태어나니 디렉션도 시작이름 끝이름만 없음으로 태어나게」.
///
/// What a block says names its drawing, hidden (09-12: 「이름을 안보이게,
/// 수정못하게」), so the frame rows' link law answers for it: the edit asks
/// before it links, the copies are born without the ends, and the pastes
/// and moves keep the name as they keep a drawing's.
void main() {
  late EditorSessionManager session;

  Layer row([LayerId? id]) => session.requireActiveCut.layers.firstWhere(
    (layer) =>
        id == null ? layer.kind == LayerKind.instruction : layer.id == id,
  );

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    session.selectLayer(row().id);
  });

  tearDown(() => session.dispose());

  /// A one-frame block on [at] of the active direction row.
  void block(int at) {
    session.selectFrameIndex(at);
    session.instructionVerbs.createDefaultInstructionEventAtCurrentFrame();
  }

  /// What the block on [at] is told through the window's commit — the
  /// drawing that already says it handed back, or null when it wrote.
  FrameId? say(
    int at, {
    String? id = 'pan',
    String? text,
    String? from,
    String? to,
  }) => session.instructionVerbs.upsertInstructionEventAt(
    row().id,
    at,
    InstructionEvent(
      instructionId: id,
      length: 1,
      text: text,
      valueA: from,
      valueB: to,
    ),
  );

  FrameId celAt(int frame, [LayerId? id]) =>
      row(id).timeline[frame]!.frameId!;

  InstructionEvent? spanAt(int frame, [LayerId? id]) =>
      row(id).instructions[frame];

  /// The words the PAN mark stands for.
  String pan() => session.camera.cameraInstructionSet.defById('pan')!.name;

  group('the name a block writes', () {
    test('is its ends and what it says — and shows nowhere', () {
      block(2);
      say(2, from: 'A', to: 'B');
      final name = row().frameById(celAt(2))!.name;

      expect(isWrittenDrawingName(name), isTrue, reason: 'it has one');
      expect(celNumberOf(name), isNull, reason: 'and it prints none');
      expect(
        drawingHeadOf(name, kind: LayerKind.instruction),
        (word: '', mark: null),
      );
      session.selectFrameIndex(2);
      session.clipboard.copyFrameAtCurrentFrame();
      expect(session.copiedFrameStatusText, isNot(contains(name)));
    });

    test('with neither end, a block names nothing, whatever it says', () {
      block(2);
      say(2, text: 'PAN');
      expect(row().frameById(celAt(2))!.name, isNull);
    });

    test('is written again when the block is told otherwise, and undone '
        'with it', () {
      block(2);
      say(2, from: 'A', to: 'B');
      say(2);
      expect(row().frameById(celAt(2))!.name, isNull);

      session.undo();
      expect(isWrittenDrawingName(row().frameById(celAt(2))!.name), isTrue);
    });
  });

  group('an edit saying what another drawing says', () {
    test('writes nothing, and hands that drawing back', () {
      block(2);
      say(2, from: 'A', to: 'B');
      block(6);
      final own = celAt(6);

      expect(say(6, from: 'A', to: 'B'), celAt(2));
      expect(celAt(6), own, reason: 'the block still shows its own');
      expect(spanAt(6)?.valueA, isNull, reason: 'and says what it said');
    });

    test('words or a mark — the same thing said is the same', () {
      block(2);
      say(2, from: 'A', to: 'B');
      block(6);

      expect(say(6, id: 'fix', text: pan(), from: 'A', to: 'B'), celAt(2));
    });

    test('names a drawing only with an end: two blocks saying PAN alone '
        'stay their own', () {
      block(2);
      say(2);
      block(6);

      expect(say(6), isNull);
      expect(celAt(6), isNot(celAt(2)));
    });

    test('one end is a name', () {
      block(2);
      say(2, from: 'A');
      block(6);

      expect(say(6, from: 'A'), celAt(2));
    });

    test('told again what it says, a block writes and asks nothing — its '
        'own drawing is no other', () {
      block(2);
      say(2, from: 'A', to: 'B');

      expect(say(2, id: 'fix', text: pan(), from: 'A', to: 'B'), isNull);
      expect(spanAt(2)?.instructionId, 'fix');
    });

    test('on an empty cell, a new block shows that drawing and asks nothing '
        '— no picture of its own is thrown away — and they say the same', () {
      block(2);
      say(2, from: 'A', to: 'B');
      final drawings = row().frames.length;

      expect(say(6, id: 'fix', text: pan(), from: 'A', to: 'B'), isNull);
      expect(celAt(6), celAt(2));
      expect(row().frames, hasLength(drawings));
      expect(spanAt(2)?.instructionId, 'fix');
    });

    test('any of the three told otherwise is another drawing', () {
      block(2);
      say(2, from: 'A', to: 'B');
      block(6);

      expect(say(6, from: 'A', to: 'C'), isNull);
      expect(say(6, from: 'B', to: 'B'), isNull);
      expect(say(6, id: 'fo', from: 'A', to: 'B'), isNull);
    });
  });

  group('the link, taken', () {
    test('shows the drawing that says it, and its own goes — one undo', () {
      block(2);
      say(2, from: 'A', to: 'B');
      block(6);
      final own = celAt(6);
      final held = say(6, from: 'A', to: 'B')!;

      session.instructionVerbs.linkInstructionEventAt(
        row().id,
        6,
        const InstructionEvent(
          instructionId: 'pan',
          length: 1,
          valueA: 'A',
          valueB: 'B',
        ),
        held,
      );

      expect(celAt(6), celAt(2));
      expect(spanAt(6)?.valueA, 'A');
      expect(row().frameById(own), isNull, reason: 'its own picture went');

      session.undo();
      expect(celAt(6), own);
      expect(row().frameById(own), isNotNull);
      expect(spanAt(6)?.valueA, isNull);
    });

    test('says what it was told on every block of the drawing', () {
      block(2);
      say(2, text: 'one', from: 'A', to: 'B');
      block(6);
      final held = say(6, from: 'A', to: 'B', text: 'one')!;

      session.instructionVerbs.linkInstructionEventAt(
        row().id,
        6,
        const InstructionEvent(
          instructionId: 'fix',
          length: 1,
          text: 'one',
          valueA: 'A',
          valueB: 'B',
        ),
        held,
      );

      expect(spanAt(2)?.instructionId, 'fix');
      expect(spanAt(6)?.instructionId, 'fix');
    });
  });

  test('an edit of a linked block says it on every block of its drawing', () {
    block(2);
    say(2, from: 'A', to: 'B');
    session.selectFrameIndex(2);
    session.frameVerbs.duplicateActiveBlock(linked: true);
    expect(celAt(3), celAt(2), reason: '⛔전제: linked');

    expect(say(3, from: 'A', to: 'C'), isNull);

    expect(spanAt(2)?.valueB, 'C');
    expect(spanAt(3)?.valueB, 'C');
  });

  group('a copy of a drawing of its own is born with neither end', () {
    test('the block duplicate', () {
      block(2);
      say(2, text: 'one', from: 'A', to: 'B');
      session.selectFrameIndex(2);
      session.frameVerbs.duplicateActiveBlock(linked: false);

      expect(celAt(3), isNot(celAt(2)));
      expect(spanAt(3)?.instructionId, 'pan');
      expect(spanAt(3)?.text, 'one');
      expect((spanAt(3)?.valueA, spanAt(3)?.valueB), (null, null));
      expect(row().frameById(celAt(3))!.name, isNull);
    });

    test('the independent paste', () {
      block(2);
      say(2, from: 'A', to: 'B');
      session.selectFrameIndex(2);
      session.clipboard.copyFrameAtCurrentFrame();
      session.selectFrameIndex(8);
      session.clipboard.pasteIndependentFrameAtCurrentFrame();

      expect(celAt(8), isNot(celAt(2)));
      expect(spanAt(8)?.instructionId, 'pan');
      expect((spanAt(8)?.valueA, spanAt(8)?.valueB), (null, null));
    });
  });

  group('the linked paste', () {
    /// A second direction row, and the block on the first's frame 2 told
    /// to say A → B, copied.
    LayerId copiedOntoASecondRow() {
      final first = row().id;
      block(2);
      say(2, from: 'A', to: 'B');
      session.selectFrameIndex(2);
      session.clipboard.copyFrameAtCurrentFrame();
      session.layerStack.addLayerOfKind(LayerKind.instruction);
      final second = session.activeLayer!.id;
      expect(second, isNot(first), reason: '⛔전제');
      return second;
    }

    test('onto another direction row keeps the name, and asks before it '
        'joins the drawing there saying the same', () {
      final second = copiedOntoASecondRow();
      session.selectFrameIndex(6);
      session.instructionVerbs.createDefaultInstructionEventAtCurrentFrame();
      session.instructionVerbs.upsertInstructionEventAt(
        second,
        6,
        const InstructionEvent(
          instructionId: 'pan',
          length: 1,
          valueA: 'A',
          valueB: 'B',
        ),
      );
      final there = celAt(6, second);

      session.selectFrameIndex(10);
      expect(session.clipboard.canPasteLinkedFrameAtCurrentFrame, isTrue);
      final joins = session.clipboard.pasteLinkedFrameAtCurrentFrame();
      expect(joins, isNotNull, reason: 'it asked first');
      session.clipboard.pasteLinkedFrameAtCurrentFrame(joinTakenNames: true);

      expect(celAt(10, second), there);
    });

    test('a drawing row wears no name a direction block writes: only the '
        'independent paste is lit there, and it brings the picture alone', () {
      copiedOntoASecondRow();
      final drawing = session.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.animation)
          .id;
      session.selectLayer(drawing);
      session.selectFrameIndex(10);

      expect(session.clipboard.canPasteLinkedFrameAtCurrentFrame, isFalse);
      session.clipboard.pasteIndependentFrameAtCurrentFrame();

      final landed = row(drawing).timeline[10]?.frameId;
      expect(landed, isNotNull, reason: '⛔전제: it pasted');
      expect(row(drawing).frameById(landed!)!.name, isNull);
      expect(row(drawing).timeline[10]?.instruction, isNull);
    });

    test('on its own row, a linked paste of a standing copy says what the '
        'drawing says', () {
      block(2);
      say(2, from: 'A', to: 'B');
      session.selectFrameIndex(2);
      session.clipboard.copyFrameAtCurrentFrame();
      session.selectFrameIndex(8);
      session.clipboard.pasteLinkedFrameAtCurrentFrame();

      expect(celAt(8), celAt(2));
      expect((spanAt(8)?.valueA, spanAt(8)?.valueB), ('A', 'B'));
    });
  });
}
