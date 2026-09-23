import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/auto_frame_for_stroke.dart';
import 'package:anicel/src/models/app_input_settings.dart';

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
    expect(autoFrameOf(session).canAutoCreateFrameForStroke, isFalse);
    expect(
      autoFrameOf(session).beginAutoFrameForStroke(),
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
    expect(autoFrameOf(session).canAutoCreateFrameForStroke, isTrue);
    expect(autoFrameOf(session).beginAutoFrameForStroke(), isTrue);
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
    autoFrameOf(session).beginAutoFrameForStroke();
    expect(
      session.historyManager.canUndo,
      before,
      reason:
          '⛔pushing here would make TWO undos out of one stroke, which '
          'is exactly what 「답은 추천대로(merged)」 ruled out',
    );

    final taken = autoFrameOf(session).takeAutoFrameForStroke();
    expect(taken, isNotNull, reason: 'the stroke gets it to compose with');
    expect(
      autoFrameOf(session).takeAutoFrameForStroke(),
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
    autoFrameOf(session).beginAutoFrameForStroke();
    expect(session.activeLayer!.frames, hasLength(1));

    autoFrameOf(session).flushAutoFrameForStroke();
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
    autoFrameOf(session).beginAutoFrameForStroke();
    // Nothing consumed it. The next press must not sweep it into ITS undo
    // entry — that would put two unrelated blocks behind one undo.
    session.selectFrameIndex(4);
    expect(autoFrameOf(session).beginAutoFrameForStroke(), isTrue);
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
    // A storyboard row's panel head: the manual button refuses there (the
    // row covers its cut edge to edge — nowhere to push, F-151) — and the
    // auto path must say no for the SAME reason rather than growing a
    // second answer to 「can this row take a cel here」.
    //
    // ↩️This stood on an animation block's head until F-151 made add push
    // there. A pen on a head never reaches this path anyway — the canvas
    // asks for a cel only while its view stands down on an EMPTY frame —
    // so the fixture moved to a place the button still refuses.
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    session.selectFrameIndex(0);
    expect(session.frameVerbs.canCreateDrawingAtCurrentFrame, isFalse);
    expect(autoFrameOf(session).canAutoCreateFrameForStroke, isFalse);
    expect(autoFrameOf(session).beginAutoFrameForStroke(), isFalse);
  });
}

/// The collaborator that owns the laws above, under its OWN name.
///
/// 🚨`tool/mutation_run.dart` picks the tests that will witness a mutation by
/// asking which tests IMPORT the file. Round 8 carved ~50 collaborators out of
/// `EditorSessionManager` and every pin still arrived through the session, so
/// 63 of the 71 files under `lib/src/ui/session/` reported UNNAMED and the
/// campaign skipped exactly the code that round wrote. ⛔Widening the runner to
/// transitive reachability was tried and reverted (one small file drew 390
/// namers); a collaborator that holds a law gets a test that names it instead.
AutoFrameForStroke autoFrameOf(EditorSessionManager session) =>
    session.autoFrame;
