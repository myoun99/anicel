import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/import/cut_folder_parse.dart';

/// I-76: a picked picture's NUMBERED RUN is its layer as the cut folder
/// reads the folder it lives in — the folder import's grammar, not a
/// second one (rule B: symbol + cel number; rule E: a `_` name is no cel;
/// rule F: a revision folds into its cel).
void main() {
  CutFolderParseResult folderOf(List<String> names) => parseCutFolder(
    folderName: 'upn_02_063_lo',
    entries: [for (final name in names) CutFolderEntry(name)],
  );

  test('a cel of a layer with more cels is in that run, wherever it sits '
      'in it', () {
    final folder = folderOf(['A1.png', 'A2.png', 'A3.png', 'B1.png']);

    for (final picked in ['A1.png', 'A2.png', 'A3.png']) {
      final run = celRunOf(picked, folder);
      expect(run?.symbol, 'A', reason: picked);
      expect([for (final cel in run!.cells) cel.label], ['1', '2', '3']);
    }
  });

  test('the only cel of its symbol, and a name that is no cel, are in no '
      'run', () {
    final folder = folderOf(['A1.png', 'A2.png', 'B1.png', '_BG.png']);

    expect(celRunOf('B1.png', folder), isNull);
    expect(celRunOf('_BG.png', folder), isNull);
    expect(celRunOf('notes.png', folder), isNull);
  });

  test('a revision the folder folds into its cel is that cel\'s run', () {
    final folder = folderOf(['A1.png', 'A2.png', 'A2_.png']);

    final run = celRunOf('A2.png', folder);
    expect(run?.symbol, 'A');
    expect(
      [for (final cel in run!.cells) cel.file],
      ['A1.png', 'A2_.png'],
      reason: 'the run is what the folder import would bring',
    );
  });
}
