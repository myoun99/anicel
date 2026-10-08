import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/session/tvpp_import_door.dart'
    show readTvppProject;

import '../helpers/temp_dir.dart';
import '../models/import/tvpp_test_builder.dart';

/// 🚨new-project-default-fps-23976 (유저 2026-10-06): 「프로젝트 기본 fps
/// 23.976으로하자」.
///
/// Every road to a new project — the app opening, File ▸ New, the last tab
/// closing — is [newUntitledProject] (the F-211 pins hold each road to it:
/// `the_app_opens_on_a_cel_to_draw_on_test`, `project_tabs_test`), so the
/// rate is pinned once, here, at the one place that makes it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new project runs at 24000/1001 and counts 24', () {
    final rate = newUntitledProject().frameRate;

    expect(
      (rate.numerator, rate.denominator, rate.countingBase),
      (24000, 1001, 24),
      reason: 'the exact pulldown rate, not a 23.976 that drifts — and the '
          'sheet still counts 24 to a second',
    );
    expect(rate.label, '23.976 fps', reason: 'what the picker shows');
  });

  test('⛔a .tvpp opened as a project stays at 24 — the new default is a '
      'new project\'s, not every project\'s', () async {
    final temp = Directory.systemTemp.createTempSync('anicel-fps-default');
    addTearDown(() => deleteTempQuietly(temp));
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 64, cameraHeight: 48);
    b.clipProperties('clip');
    // Every TVPaint file measured says 24000 here (10-08: six samples).
    b.clipHeader(width: 64, height: 48);
    b.layerHead('A', end: 0, count: 1, layerId: 901);
    b.layerExt(const {});
    b.zchkSlot(srawRecord(List.filled(64 * 48, 0), 64, 48));
    b.clipConfig();
    final path = '${temp.path}${Platform.pathSeparator}clip.tvpp';
    File(path).writeAsBytesSync(b.bytes);

    final read = await readTvppProject(tvppPath: path);

    expect(read, isNotNull, reason: '⛔전제: the file opens');
    expect(read!.project.frameRate, ProjectFrameRate.fps24);
  });
}
