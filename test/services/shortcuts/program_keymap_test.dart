import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/shortcuts/program_keymap.dart';

import '../../helpers/program_shortcut_files.dart';
import '../../helpers/temp_dir.dart';
import '../import/clip_test_builder.dart' show clipDatabaseBytes;

/// 🗣️I-107 (유저): 「tvp나 클튜의 단축키파일 임포트 가능하게. 대응하는것만
/// 대응하게 해도 되니까」. Each shape below is the one the two programs' own
/// files have on the machine the round was built on (TVPaint Animation 12
/// Pro, CLIP STUDIO PAINT 1.5) — read there, never written.
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_keymap_'));
  tearDown(() => deleteTempQuietly(folder));

  ProgramKeymap read(String name, List<String> lines) =>
      readShortcutFile(name, utf8.encode(lines.join('\r\n')))!;

  group('TVPaint', () {
    test('config.ini: the [keyboard] section alone, each key=command with '
        'its modifiers first', () {
      final file = read('config.ini', [
        '[general]',
        'u=NotAKeyOfTheKeyboard',
        '[keyboard]',
        'ctrl z=Undo',
        'u=Undo',
        'shift page up=ZoomRotateAdd15',
        'braquet=ZoomFlipX',
        'equal=DisplayAllLayer',
        'ctrl pad 0=ZoomOneOne',
        'f2=Drawing Mode 1',
        '>=ZoomIn',
        'del=SelectDel',
        'a=none',
        'ctrl wheel up=ZoomIn',
        // The room's copy of the map — not the keyboard's.
        '[room-1]',
        'x=Undo',
      ]);

      expect(file.program, KeymapProgram.tvpaint);
      expect(file.keys, {
        'Undo': const [
          ProgramChord(LogicalKeyboardKey.keyZ, control: true),
          ProgramChord(LogicalKeyboardKey.keyU),
        ],
        'ZoomRotateAdd15': const [
          ProgramChord(LogicalKeyboardKey.pageUp, shift: true),
        ],
        'ZoomFlipX': const [ProgramChord(LogicalKeyboardKey.bracketLeft)],
        'DisplayAllLayer': const [ProgramChord(LogicalKeyboardKey.equal)],
        'ZoomOneOne': const [
          ProgramChord(LogicalKeyboardKey.numpad0, control: true),
        ],
        'Drawing Mode 1': const [ProgramChord(LogicalKeyboardKey.f2)],
        'ZoomIn': const [ProgramChord(LogicalKeyboardKey.greater)],
        'SelectDel': const [ProgramChord(LogicalKeyboardKey.delete)],
      });
      expect(file.unread, 1, reason: 'the wheel is no key: said, not dropped');
    });

    test('a keymap .cfg names its keys capitalised', () {
      final file = read('Anim.cfg', [
        '[Keyboard]',
        'Ctrl Z=Undo',
        'Shift Page Up=ZoomRotateAdd15',
        'Equal=DisplayAllLayer',
      ]);

      expect(file.keys, {
        'Undo': const [ProgramChord(LogicalKeyboardKey.keyZ, control: true)],
        'ZoomRotateAdd15': const [
          ProgramChord(LogicalKeyboardKey.pageUp, shift: true),
        ],
        'DisplayAllLayer': const [ProgramChord(LogicalKeyboardKey.equal)],
      });
    });

    test('the text its shortcut window saves names each command as it is '
        'shown — in Japanese, read back to the keymap\'s ids', () {
      final file = read('tvp_shortcut_default.txt', [
        '--------------------------------------',
        'All Available commands',
        '--------------------------------------',
        'ズーム: ズームイン',
        '',
        '--------------------------------------',
        'Shortcuts',
        '--------------------------------------',
        '',
        '"A" = noneズーム: シェーク',
        '"Ctrl Z" = noneアンドゥ: 最後のアクション',
        '"[" = noneズーム: 水平に反転',
        '"=" = noneレイヤー: 現在のレイヤーを見る / すべて',
        '"Wheel Up" = noneズーム: ズームイン',
      ]);

      expect(file.keys, {
        'ズーム: シェーク': const [ProgramChord(LogicalKeyboardKey.keyA)],
        'Undo': const [ProgramChord(LogicalKeyboardKey.keyZ, control: true)],
        'ZoomFlipX': const [ProgramChord(LogicalKeyboardKey.bracketLeft)],
        'DisplayAllLayer': const [ProgramChord(LogicalKeyboardKey.equal)],
      });
      expect(file.unread, 1);
    });

    test('a saved text in a language whose names are not known here, and a '
        'text that is no keymap at all, read as nothing', () {
      expect(
        readShortcutFile(
          'english.txt',
          utf8.encode('Shortcuts\n"Ctrl Z" = noneUndo: Last action\n'),
        ),
        isNull,
      );
      expect(readShortcutFile('notes.txt', utf8.encode('메모\n')), isNull);
      expect(
        readShortcutFile('desktop.ini', utf8.encode('[.ShellClassInfo]')),
        isNull,
      );
    });
  });

  group('CLIP STUDIO PAINT', () {
    test('a shortcut set (.khc): each command\'s keys, its modifiers as the '
        'set\'s bits — Alt 1, Shift 2, Ctrl 4', () {
      final file = readShortcutFile(
        'default.khc',
        clipShortcutSetBytes(folder, [
          ('filesaveas', 'S', 3),
          ('filesaveas', 'S', 6),
          ('filesaveas', 'S', 5),
          ('undo', 'Z', 4),
          ('clear', 'DELETE', 0),
          ('editpaint', 'BACKSPACE', 1),
          ('viewzoomin', '.', 2),
          ('helponlinehowto', 'F1', 0),
          ('viewreversehorz', 'H', 0),
          // Left without a key: written out.
          ('filenewfromclipboard', 'NULL', null),
          // A bit no modifier here is, and a key no name here is.
          ('windowshowtoolbar', 'Q', 8),
          ('applicationquit', 'PAUSE', 0),
        ]),
      )!;

      expect(file.program, KeymapProgram.clipStudio);
      expect(file.keys, {
        'filesaveas': const [
          ProgramChord(LogicalKeyboardKey.keyS, shift: true, alt: true),
          ProgramChord(LogicalKeyboardKey.keyS, control: true, shift: true),
          ProgramChord(LogicalKeyboardKey.keyS, control: true, alt: true),
        ],
        'undo': const [ProgramChord(LogicalKeyboardKey.keyZ, control: true)],
        'clear': const [ProgramChord(LogicalKeyboardKey.delete)],
        'editpaint': const [
          ProgramChord(LogicalKeyboardKey.backspace, alt: true),
        ],
        'viewzoomin': const [
          ProgramChord(LogicalKeyboardKey.period, shift: true),
        ],
        'helponlinehowto': const [ProgramChord(LogicalKeyboardKey.f1)],
        'viewreversehorz': const [ProgramChord(LogicalKeyboardKey.keyH)],
      });
      expect(file.unread, 2);
    });

    test('a tool palette (.todb): a key per kind of tool, by the number the '
        'palette gives it — A to Z are 1 to 26, the Zoom tool\'s / is 90', () {
      final palette = clipToolPaletteBytes(folder, [
        ('펜', 22, 20),
        ('펜 사본', 22, 20),
        ('연필', 2, 21),
        ('붓', 14, 22),
        ('돋보기', 90, 10),
        ('그라데이션', 7, 31),
        ('스포이트', 0, 16),
        // A sub tool: no kind of its own.
        ('G펜', 5, 0),
        ('뭔가', 91, 40),
      ]);

      final file = readShortcutFile('EditImageTool.todb', palette)!;

      expect(file.program, KeymapProgram.clipStudio);
      expect(file.keys, {
        clipStudioTool(20): const [ProgramChord(LogicalKeyboardKey.keyV)],
        clipStudioTool(21): const [ProgramChord(LogicalKeyboardKey.keyB)],
        clipStudioTool(22): const [ProgramChord(LogicalKeyboardKey.keyN)],
        clipStudioTool(10): const [ProgramChord(LogicalKeyboardKey.slash)],
        clipStudioTool(31): const [ProgramChord(LogicalKeyboardKey.keyG)],
      });
      expect(file.unread, 1);
    });

    test('bytes that are no database, or a database that is neither, read '
        'as nothing', () {
      expect(readShortcutFile('default.khc', [1, 2, 3, 4]), isNull);
      final other = clipDatabaseBytes(
        folder,
        (db) => db.execute('CREATE TABLE Unrelated(a INTEGER)'),
      );
      expect(readShortcutFile('default.khc', other), isNull);
      expect(readShortcutFile('EditImageTool.todb', other), isNull);
    });
  });

  test('a name no reader takes reads as nothing', () {
    expect(readShortcutFile('Pack.abr', utf8.encode('[keyboard]')), isNull);
  });
}
