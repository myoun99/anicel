import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/handed_text_file.dart';

import '../../helpers/temp_dir.dart';

/// One road for every file of the app's own text a person takes away — a
/// brush pack, a palette, a shortcut preset (I-142): what came of it, told
/// apart, and a name a file can have.
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_text_file_'));
  tearDown(() => deleteTempQuietly(folder));

  test('it is written where the hand says, under a name a file can '
      'have', () async {
    String? asked;
    final handed = await handTextFile(
      'Skin: face/hair.',
      'anipalette',
      () => 'text',
      hand: (name, write) async {
        asked = name;
        final path = '${folder.path}/$name';
        return await write(path) ? path : null;
      },
    );

    expect(asked, 'Skin_ face_hair.anipalette');
    expect(handed, isA<TextFileLanded>());
    final where = (handed as TextFileLanded).where;
    expect(where, '${folder.path}/$asked');
    expect(File(where).readAsStringSync(), 'text');
  });

  test('a person who would not have it costs nothing — the text is never '
      'made', () async {
    var made = 0;
    final handed = await handTextFile(
      'Skin',
      'anipalette',
      () {
        made++;
        return 'text';
      },
      hand: (_, _) async => null,
    );

    expect(handed, isA<TextFileDeclined>());
    expect(made, 0);
  });

  test('a file not written is told from a place not chosen', () async {
    final notWritten = await handTextFile(
      'Skin',
      'anipalette',
      () => 'text',
      hand: (name, write) async =>
          await write('${folder.path}/no/such/folder/$name') ? 'landed' : null,
    );
    final unmade = await handTextFile(
      'Skin',
      'anipalette',
      () => throw StateError('no text'),
      hand: (name, write) async =>
          await write('${folder.path}/$name') ? 'landed' : null,
    );
    final notPlaced = await handTextFile(
      'Skin',
      'anipalette',
      () => 'text',
      hand: (_, _) async => throw StateError('no window'),
    );

    expect(notWritten, isA<TextFileNotWritten>());
    expect((unmade as TextFileNotWritten).error, isA<StateError>());
    expect(File('${folder.path}/Skin.anipalette').existsSync(), isFalse);
    expect(
      '${(notPlaced as TextFileNotPlaced).error}',
      'Bad state: no window',
    );
  });
}
