import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/path_names.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';

/// One basename rule, in `core/`, for the services that plan an import or
/// stage a file and the dialogs that name a picked one.
void main() {
  test('the name comes off either platform separator', () {
    expect(fileNameOfPath(r'C:\work\cut 01.anicel'), 'cut 01.anicel');
    expect(fileNameOfPath('/home/me/cut 01.anicel'), 'cut 01.anicel');
    expect(fileNameOfPath('bare.anicel'), 'bare.anicel');
  });

  test('a mixed-separator path answers its LAST segment', () {
    expect(fileNameOfPath(r'C:\work/cuts\A1.png'), 'A1.png');
    expect(fileNameOfPath('C:/work/cuts/'), '');
  });

  test('the folder a path stands in comes off either separator — the half '
      'the name leaves', () {
    expect(folderOfPath(r'C:\work\cuts\A1.png'), 'C:/work/cuts');
    expect(folderOfPath('/home/me/cut 01.anicel'), '/home/me');
    expect(folderOfPath(r'C:\work/cuts\A1.png'), 'C:/work/cuts');
  });

  test('a root keeps its slash, and a bare name stands in no folder', () {
    expect(folderOfPath('C:/shot.mp4'), 'C:/');
    expect(folderOfPath('/shot.mp4'), '/');
    expect(folderOfPath('bare.anicel'), '');
  });

  test('a name goes into a folder as the folder answers it — one slash '
      'after a root, none before a bare name', () {
    expect(pathInFolder('C:/work', 'snd/a.wav'), 'C:/work/snd/a.wav');
    expect(pathInFolder('C:/', 'a.wav'), 'C:/a.wav');
    expect(pathInFolder('/', 'a.wav'), '/a.wav');
    expect(pathInFolder('', 'a.wav'), 'a.wav');
    for (final path in ['C:/work/a.wav', 'C:/a.wav', '/a.wav', 'a.wav']) {
      expect(
        pathInFolder(folderOfPath(path), fileNameOfPath(path)),
        path,
        reason: 'the two halves put back together',
      );
    }
  });

  // 🚨★★A PATH IS CUT IN ONE FILE. The save kept a folder of its own that
  // answered `.` for `/a.anicel` — the working directory, not the root
  // (board `the-save-keeps-its-own-folder-of-a-path`, 2026-10-08) — and four
  // more files cut a name or an extension off a path by hand, five times. A
  // behaviour test passes two copies that agree today, so the cuts are
  // counted where they are written.
  test('no file but this one cuts a path at its last separator', () {
    final cut = RegExp(
      r"lastIndexOf\('/'\)|lastIndexOf\(Platform\.pathSeparator\)"
      r"|split\('/'\)\.last",
    );
    final cutting = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            cut.hasMatch(file.readAsStringSync()))
          file.path.replaceAll(r'\', '/'),
    ];
    expect(cutting, ['lib/src/core/path_names.dart']);
  });

  // The recent-projects row used to split on `/` alone and lean on the
  // constructor's normalisation to make that safe. It answers through the
  // one rule now, so the row is right whichever way the path was spelled.
  test('a recent-projects row names the FILE on a Windows path', () {
    expect(
      RecentProject(path: r'C:\work\cut 01.anicel').name,
      'cut 01.anicel',
    );
    expect(
      RecentProject(path: '/home/me/cut 01.anicel').name,
      'cut 01.anicel',
    );
  });

  // 🪦「a staged name keeps the source file name after its hash」 lived here
  // while the staging store spelled the name itself; the name is the
  // carry's now (`mediaCarryName`), and so is the test — `media_asset_test`.
}
