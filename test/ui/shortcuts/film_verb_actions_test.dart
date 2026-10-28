import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// The film verbs joined the registry so they can be bound to a key, and
/// so a future custom rail slot has something to point at. Before this
/// they existed only as toolbar icons — the most-pressed buttons in the
/// app with no id to their name.
void main() {
  const filmVerbs = <String>[
    EditorActionIds.frameNewDrawing,
    EditorActionIds.frameBlankExposure,
    EditorActionIds.frameToggleMarkOne,
    EditorActionIds.frameToggleMarkTwo,
    EditorActionIds.frameMarkEvery,
    EditorActionIds.timelinePushBlocks,
    EditorActionIds.timelinePullBlocks,
  ];

  EditorActionDefinition definitionFor(String id) =>
      editorActionDefinitions.firstWhere((definition) => definition.id == id);

  test('every film verb is registered on the frame pill', () {
    for (final id in filmVerbs) {
      final definition = definitionFor(id);
      expect(definition.shelf, ShortcutShelf.framePill, reason: id);
      expect(definition.label, isNotEmpty, reason: id);
    }
  });

  test('the film verbs ship deliberately unbound — but Add Frame, whose key '
      'the user named', () {
    // Which key belongs on these is a working habit, not something to
    // guess — and the digits are already the comma set's. Registering
    // them unbound is what puts a row in the shortcut dialog to fill in.
    // 🗣️I-63-Q4 (유저 2026-10-09): Add Frame takes TVPaint's key.
    for (final id in filmVerbs) {
      expect(
        definitionFor(id).defaultActivators,
        id == EditorActionIds.frameNewDrawing ? isNotEmpty : isEmpty,
        reason: id,
      );
    }
  });

  test('🗣️I-63 ③ · I-58: the two ＋ rows read as the user named them — '
      '「새 프레임」 and 「새 레이어」 beside it', () {
    // 유저 2026-10-03: 「프레임 추가랑 레이어 추가버튼도 단축키 기본값
    // 등록하고싶음. 프레임추가는 이름이 새 그림인데 그게아니라 프레임 추가로」 —
    // then I-58 (10-18 12:31): 「ㅁㅁ 추가말고 새 ㅁㅁ로 하자」. ↩️They read
    // 「프레임 추가」 (it was 「새 그림」) and 「레이어 추가」.
    final korean = AppStrings.of(AppLanguage.ko);
    expect(
      korean.shortcutLabel(EditorActionIds.frameNewDrawing, 'unnamed'),
      '새 프레임',
    );
    expect(
      definitionFor(EditorActionIds.frameNewDrawing).label,
      'New Frame',
      reason: 'the registry\'s wording IS the English row',
    );
    expect(
      korean.shortcutLabel(EditorActionIds.layerAdd, 'unnamed'),
      '새 레이어',
    );
    final ids = [for (final it in editorActionDefinitions) it.id];
    expect(
      ids.indexOf(EditorActionIds.layerAdd),
      ids.indexOf(EditorActionIds.frameNewDrawing) + 1,
      reason: 'the shortcut list prints the registry in order',
    );
  });

  test('🗣️I-58: the frame pill\'s rows and the cut\'s ＋ read as the user '
      'named them — 「새 ㅁㅁ」, 비우기, 프레임 자동 생성, 중간나누기 마크', () {
    // 유저 2026-10-18: 「컷 추가버튼은 새 컷이고 레이어는 레이어 추가고
    // 프레임은 추가임 … 통일(레이어 추가 이런식으로 ㅁㅁ 추가. ㅁㅁ 삭제)하고,
    // x버튼은 비우기, 빈 칸에 그리면 프레임 자동 생성은 프레임 자동 생성, 마크
    // 점은 중간나누기 마크」 — and at 12:31, 「ㅁㅁ 추가말고 새 ㅁㅁ로 하자」.
    // ↩️The cut's ＋ read 「컷 추가」.
    final korean = AppStrings.of(AppLanguage.ko);
    String label(String id) => korean.shortcutLabel(id, 'unnamed');
    expect(label(EditorActionIds.cutNew), '새 컷');
    expect(label(EditorActionIds.frameBlankExposure), '비우기');
    expect(label(EditorActionIds.frameAutoCreate), '프레임 자동 생성');
    // 🗣️I-130 (유저 2026-10-25): two marks, 마크1 the hollow ○ and 마크2
    // the filled ●. ↩️The ● read 「중간나누기 마크」 while it was the one.
    expect(label(EditorActionIds.frameToggleMarkOne), '중간나누기 마크1');
    expect(label(EditorActionIds.frameToggleMarkTwo), '중간나누기 마크2');
    expect(label(EditorActionIds.frameMarkEvery), '중간나누기 마크 자동 추가');
    final ids = [for (final it in editorActionDefinitions) it.id];
    expect(
      ids.indexOf(EditorActionIds.frameMarkEvery),
      ids.indexOf(EditorActionIds.frameToggleMarkTwo) + 1,
      reason: 'the shortcut list prints the registry in order, and the '
          'button stands right of the ● (I-58-Q1)',
    );
    expect(
      ids.indexOf(EditorActionIds.frameToggleMarkOne),
      ids.indexOf(EditorActionIds.frameToggleMarkTwo) - 1,
      reason: '「기존 중간나누기 버튼 왼쪽에 중간나누기 마크1 버튼 신설」 (I-130)',
    );
  });

  test('no action id is registered twice', () {
    final ids = editorActionDefinitions.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every film verb reads in every language', () {
    // The registry is const and holds only English; the other languages
    // are tabled by id. An untabled verb falls back to English silently,
    // which is exactly how two menu ids stayed English for months.
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.en) {
        continue;
      }
      final strings = AppStrings.of(language);
      for (final id in filmVerbs) {
        final english = definitionFor(id).label;
        expect(
          strings.shortcutLabel(id, english),
          isNot(english),
          reason: '$id has no ${language.name} wording',
        );
      }
    }
  });
}
