import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**THIS MOVES SOMEBODY'S SETTINGS. IT NEVER DELETES.**
///
/// 유저 2026-09-07 approved the migration on exactly that shape: these are
/// not project files, they are the shortcut overrides, brush presets,
/// imported tips and palettes on a real machine — 「새로 만들 수는 있어도
/// 되돌릴 수는 없는」. So every step is a rename into a name that does not
/// exist yet, and what is pinned below is what happens when that is NOT
/// true, rather than the happy path.
///
/// ⛔**Every case runs against an injected root.** `appSupportFilePath`
/// does not redirect under `FLUTTER_TEST`, so a test that let this resolve
/// the real container would move the developer's own settings — which is
/// the very thing being tested for care.
void main() {
  late Directory container;

  setUp(() {
    container = Directory.systemTemp.createTempSync('qa_settings_room');
  });

  tearDown(() => deleteTempQuietly(container));

  String root() => container.path.replaceAll(r'\', '/');
  File at(String name) => File('${root()}/$name');
  File inRoom(String name) => File('${root()}/Settings/$name');
  int migrate() => migrateSettingsIntoTheirRoom(containerRoot: root());

  test('an entry at the old address moves into the room, bytes and all', () {
    at('accent_settings.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"accent":1}');

    expect(migrate(), 1);

    expect(inRoom('accent_settings.json').readAsStringSync(), '{"accent":1}');
    expect(at('accent_settings.json').existsSync(), isFalse);
  });

  test('🚨 an entry already in the room is left alone — and so is the old '
      'one', () {
    // Choosing between two copies of a person's settings is not a choice
    // code gets to make silently, and the one thing it must never do is
    // put the older over the newer.
    at('accent_settings.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('OLD');
    inRoom('accent_settings.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('NEW');

    expect(migrate(), 0);

    expect(inRoom('accent_settings.json').readAsStringSync(), 'NEW');
    expect(
      at('accent_settings.json').readAsStringSync(),
      'OLD',
      reason: '⛔and it is NOT deleted. There is no delete in this function '
          'at all — both copies stay and the person can look.',
    );
  });

  test('a FOLDER entry moves with its contents', () {
    // `brush_tips/` is the user's own imported images, and the only entry
    // that is not a single file.
    Directory('${root()}/brush_tips').createSync(recursive: true);
    File('${root()}/brush_tips/mine.png').writeAsStringSync('png');

    expect(migrate(), 1);

    expect(
      File('${root()}/Settings/brush_tips/mine.png').readAsStringSync(),
      'png',
    );
    expect(Directory('${root()}/brush_tips').existsSync(), isFalse);
  });

  test('a second launch moves nothing', () {
    at('ui_scale.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('1');

    expect(migrate(), 1);
    expect(
      migrate(),
      0,
      reason: 'once the room holds them there is nothing at the old address',
    );
  });

  test('⛔ nothing outside the list is moved — a room is not a setting', () {
    // The container root also holds the folders that are NOT settings. A
    // migration that swept「whatever is lying around」would have carried a
    // run's scratch room into the settings folder.
    Directory('${root()}/Sessions/1234-5678').createSync(recursive: true);
    at('somebody-elses.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    expect(migrate(), 0);

    expect(Directory('${root()}/Sessions/1234-5678').existsSync(), isTrue);
    expect(at('somebody-elses.json').existsSync(), isTrue);
    expect(Directory('${root()}/Settings/Sessions').existsSync(), isFalse);
  });

  test('an empty container is silent', () {
    expect(migrate(), 0);
    expect(Directory('${root()}/Settings').existsSync(), isFalse,
        reason: 'nothing to move, nothing to create');
  });
}
