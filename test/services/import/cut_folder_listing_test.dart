import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/services/import/cut_folder_listing.dart';

/// 🚨WHAT A LISTED ENTITY MEANS, WHICH TWO WALKS SHARE.
///
/// The import door lists a delivery folder asynchronously and the import
/// dialog's preview lists it synchronously — a real difference in what
/// each may afford — and each used to write out the same three things
/// afterwards: slice the root off, spell it with forward slashes, and
/// address the parse with the folder's name plus its parent's. Round 8
/// (G1, 2026-09-06) left the walks alone and shared the meaning.
///
/// ⚠️Driven with WINDOWS paths on purpose. A fixture that builds its
/// folder with forward slashes gets the same answer whether the
/// normalisation is there or not, so it cannot see the rule at all —
/// while production on Windows gets `\` from every listing.
void main() {
  test('every listed path is relative to the folder, in one spelling', () {
    final entries = cutFolderEntriesFrom(r'C:\deliveries\A_01_069_genga', [
      File(r'C:\deliveries\A_01_069_genga\A1.png'),
      Directory(r'C:\deliveries\A_01_069_genga\_old'),
      File(r'C:\deliveries\A_01_069_genga\_old\A1.png'),
    ]);

    expect(entries.map((e) => e.relativePath), [
      'A1.png',
      '_old',
      '_old/A1.png',
    ]);
    expect(
      entries.map((e) => e.isDirectory),
      [false, true, false],
      reason: 'a folder is a folder however it was listed',
    );
  });

  test('the parse is addressed at the folder AND its parent', () {
    // Rule I (KHT style): the cut number is the folder's own name and the
    // PROCESS comes from the parent, which is the whole reason the parse
    // takes two names rather than one.
    final parsed = parseCutFolderAt(
      r'C:\deliveries\lo\069',
      entries: [const CutFolderEntry('A1.png')],
      config: const CutFolderParseConfig(
        nameRule: CutFolderNameRule.cutNumberOnly,
        parentFolderProcessHint: true,
      ),
    );

    expect(parsed.folderName, '069');
    expect(parsed.cutNumbers, ['069']);
    expect(
      parsed.processTokens,
      ['lo'],
      reason: 'the parent named the process; dropping it loses that answer',
    );
  });
}
