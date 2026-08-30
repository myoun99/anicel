import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// 🚨I-10 — A PEN-DOWN ON AN EMPTY CELL MAKES THE BLOCK AND DRAWS INTO IT.
///
/// 유저 2026-08-30: 「빈 칸에서 펜다운하면 블록이 생기고 그대로 그려진다」,
/// on the undo boundary 「답은 추천대로」 (= **merged**, one undo for both),
/// and on the control 「**프레임 자동생성 on버튼** 만들게 햇던거같은데」.
///
/// ⚠️THE TWO HALVES HAPPEN AT DIFFERENT MOMENTS and that is the whole
/// design problem: the block must exist at pen-DOWN (there is nowhere for
/// ink to go otherwise) and the stroke commits at pen-UP.
/// `HistoryManager.runAsOneStep` groups a single synchronous body, so it
/// cannot span that — the block's command is HELD and composed with the
/// stroke when the pen lifts.
void main() {
  setUp(() {
    AppInput.settings.value = const AppInputSettings();
  });
  tearDown(() {
    AppInput.settings.value = const AppInputSettings();
  });

  EditorSessionManager sessionOnEmptyCell() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.selectFrameIndex(0);
    // ⛔The premise: a default project's drawing layer starts with NO cels,
    // so frame 0 really is the empty cell this feature is about. Without
    // this the cases below could pass on a row that already had a block.
    expect(session.activeLayer!.frames, isEmpty);
    return session;
  }

  test('⛔OFF by default — the toggle has to be asked for', () {
    final session = sessionOnEmptyCell();
    expect(AppInput.settings.value.autoCreateFrameOnDraw, isFalse);
    expect(session.canAutoCreateFrameForStroke, isFalse);
    expect(
      session.beginAutoFrameForStroke(),
      isFalse,
      reason:
          'a press on an empty cell is still refused until the user '
          'turns this on — it changes what EVERY empty cell does',
    );
    expect(session.activeLayer!.frames, isEmpty);
  });

  test('🚨on: the press makes the block', () {
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
    final session = sessionOnEmptyCell();
    expect(session.canAutoCreateFrameForStroke, isTrue);
    expect(session.beginAutoFrameForStroke(), isTrue);
    expect(
      session.activeLayer!.frames,
      hasLength(1),
      reason: '「빈 칸에서 펜다운하면 블록이 생기고」',
    );
  });

  test('🚨the block is HELD, not pushed — the stroke undoes it', () {
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
    final session = sessionOnEmptyCell();
    final before = session.historyManager.canUndo;
    session.beginAutoFrameForStroke();
    expect(
      session.historyManager.canUndo,
      before,
      reason:
          '⛔pushing here would make TWO undos out of one stroke, which '
          'is exactly what 「답은 추천대로(merged)」 ruled out',
    );

    final taken = session.takeAutoFrameForStroke();
    expect(taken, isNotNull, reason: 'the stroke gets it to compose with');
    expect(
      session.takeAutoFrameForStroke(),
      isNull,
      reason: 'and only once — a second stroke must not inherit it',
    );
  });

  test('🚨a block no stroke claimed keeps its own undo', () {
    // ⛔I nearly made this DISCARD the block. 「A press that drew nothing
    // leaves nothing」 sounded right and was MY rule; the user said the
    // pen-DOWN makes it. What must not happen is the block outliving its
    // command — sitting in the project with no history entry, unundoable.
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
    final session = sessionOnEmptyCell();
    session.beginAutoFrameForStroke();
    expect(session.activeLayer!.frames, hasLength(1));

    session.flushAutoFrameForStroke();
    expect(
      session.activeLayer!.frames,
      hasLength(1),
      reason: 'the block stays — 「펜다운하면 블록이 생기고」',
    );
    expect(
      session.historyManager.canUndo,
      isTrue,
      reason: 'and it is undoable, which it was not while held',
    );
    session.historyManager.undo();
    expect(session.activeLayer!.frames, isEmpty);
  });

  test('⛔a second press settles the first press\'s orphan', () {
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
    final session = sessionOnEmptyCell();
    session.beginAutoFrameForStroke();
    // Nothing consumed it. The next press must not sweep it into ITS undo
    // entry — that would put two unrelated blocks behind one undo.
    session.selectFrameIndex(4);
    expect(session.beginAutoFrameForStroke(), isTrue);
    expect(session.activeLayer!.frames, hasLength(2));
    expect(
      session.historyManager.canUndo,
      isTrue,
      reason:
          'the first block was settled on its own before the second '
          'press began',
    );
  });

  test('⛔it refuses everywhere the manual button refuses', () {
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
    final session = sessionOnEmptyCell();
    session.createDrawingAtCurrentFrame();
    // The cell is covered now, so the manual button says no — and the auto
    // path must say no for the SAME reason rather than growing a second
    // answer to 「can this row take a cel here」.
    expect(session.canCreateDrawingAtCurrentFrame, isFalse);
    expect(session.canAutoCreateFrameForStroke, isFalse);
    expect(session.beginAutoFrameForStroke(), isFalse);
  });
}
