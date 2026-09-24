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
