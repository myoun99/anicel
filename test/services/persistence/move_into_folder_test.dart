import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/move_into_folder.dart';

import '../../helpers/temp_dir.dart';

/// What the desktops do with finished outputs handed over when the run is
/// done (drive-folder-windows-Q1): they move into the folder picked then,
/// the way an export into that folder would have written them.
void main() {
  late Directory temp;
  late Directory from;
  late Directory into;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa-move-into-folder');
    from = Directory('${temp.path}/from')..createSync();
    into = Directory('${temp.path}/into')..createSync();
  });

  tearDown(() => deleteTempQuietly(temp));

  Map<String, String> contentsOf(Directory directory) => {
    for (final file in directory.listSync(recursive: true).whereType<File>())
      file.path
          .substring(directory.path.length + 1)
          .replaceAll('\\', '/'): file.readAsStringSync(),
  };

  test('a file moves in under its own name and is gone from where it was',
      () {
    final file = File('${from.path}/frame_0001.png')..writeAsStringSync('a');

    moveIntoFolder(file.path, into.path);

    expect(contentsOf(into), {'frame_0001.png': 'a'});
    expect(file.existsSync(), isFalse);
  });

  test('a file by the same name is replaced, as an export there replaces it',
      () {
    File('${into.path}/frame_0001.png').writeAsStringSync('old');
    final file = File('${from.path}/frame_0001.png')..writeAsStringSync('new');

    moveIntoFolder(file.path, into.path);

    expect(contentsOf(into), {'frame_0001.png': 'new'});
  });

  test('a folder moves with all it holds, and one already there takes its '
      'contents beside its own', () {
    final cut = Directory('${from.path}/CUT001/A')..createSync(recursive: true);
    File('${cut.path}/0001.png').writeAsStringSync('1');
    File('${from.path}/CUT001/sheet.png').writeAsStringSync('s');
    Directory('${into.path}/CUT001/A').createSync(recursive: true);
    File('${into.path}/CUT001/A/0002.png').writeAsStringSync('2');

    moveIntoFolder('${from.path}/CUT001', into.path);

    expect(contentsOf(into), {
      'CUT001/A/0001.png': '1',
      'CUT001/A/0002.png': '2',
      'CUT001/sheet.png': 's',
    });
    expect(Directory('${from.path}/CUT001').existsSync(), isFalse);
  });

  test('a folder standing where a file would land refuses it — the move '
      'fails rather than lose either', () {
    Directory('${into.path}/frame_0001.png').createSync();
    final file = File('${from.path}/frame_0001.png')..writeAsStringSync('a');

    expect(
      () => moveIntoFolder(file.path, into.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(file.readAsStringSync(), 'a');
  });
}
