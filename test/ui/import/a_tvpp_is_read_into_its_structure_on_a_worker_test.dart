import 'dart:io';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/ui/session/tvpp_import_door.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';
import '../../models/import/tvpp_test_builder.dart';

/// Card F-621 ⑤ (유저 2026-11-19: 「50%되고나면 앱이 멈추고 5초쯤지나면
/// 다시진행되」): a .tvpp is read in, and its structure made — parsed, every
/// clip converted and its camera fitted — on a worker, never on the
/// window's isolate.
///
/// 🚨ON A WORKER OF ITS OWN: the suite runs every worker's job here
/// ([debugWorkersRunHere]), where a job that carries what no isolate
/// message can — its caller's scope, a structure that will not cross —
/// reads the same as one that crosses. This file turns that off.
void main() {
  late bool corpus;
  late Directory temp;

  setUp(() {
    corpus = debugWorkersRunHere;
    debugWorkersRunHere = false;
    temp = Directory.systemTemp.createTempSync('tvpp-on-a-worker');
  });

  tearDown(() {
    debugWorkersRunHere = corpus;
    deleteTempQuietly(temp);
  });

  String movingCamera() => [
    for (final (i, x, rotation, zoom, instant) in [
      (0, 160, 0, 1, 0),
      (1, 200, -12.5, 1.56, 24),
    ]) ...[
      'mpoints-$i-x=$x.000000',
      'mpoints-$i-y=90.000000',
      'mpoints-$i-rotation=$rotation',
      'mpoints-$i-zoomfactor=$zoom',
      'mpoints-$i-camerasizex=320.000000',
      'mpoints-$i-camerasizey=180.000000',
      'mpoints-$i-instant=$instant',
    ],
    '',
  ].join('\n');

  test('🚨the bytes cross to a worker and the clips come back from it — two '
      'cuts, the first with the camera its move needs, the percent from 0 to '
      '1', () async {
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 320, cameraHeight: 180);
    for (final name in ['cut12', 'cut13']) {
      b.clipProperties(name);
      b.clipHeader(width: 320, height: 180);
      b.layerHead('A', end: 0, count: 1, layerId: 7);
      b.layerExt(const {0: '1'});
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.clipConfig(cameraData: name == 'cut12' ? movingCamera() : '');
    }
    final path = '${temp.path}${Platform.pathSeparator}two.tvpp';
    File(path).writeAsBytesSync(b.bytes);
    final told = <double>[];

    final read = await readTvppProject(
      tvppPath: path,
      isCancelled: () => false,
      onRead: told.add,
    );

    expect(read, isNotNull);
    final cuts = read!.project.tracks.single.cuts;
    expect([for (final cut in cuts) cut.name], ['cut12', 'cut13']);
    expect(cuts.first.camera.isEmpty, isFalse, reason: 'the moving camera');
    expect(cuts.last.camera.isEmpty, isTrue, reason: 'no camera keyed');
    expect((told.first, told.last), (0, 1));
  });

  test('🎯the percent follows the work: the bytes coming in fill the first '
      'half, each clip made the second (F-615)', () async {
    // Here, so every word the worker says is heard in the order it said it.
    debugWorkersRunHere = true;
    final b = TvppBuilder();
    b.projectProperties(cameraWidth: 320, cameraHeight: 180);
    for (final name in ['cut12', 'cut13']) {
      b.clipProperties(name);
      b.clipHeader(width: 320, height: 180);
      b.layerHead('A', end: 0, count: 1, layerId: 7);
      b.layerExt(const {});
      b.zchkSlot(srawRecord(List.filled(320 * 180, 0), 320, 180));
      b.clipConfig();
    }
    final path = '${temp.path}${Platform.pathSeparator}two.tvpp';
    File(path).writeAsBytesSync(b.bytes);
    final told = <double>[];

    await readTvppProject(
      tvppPath: path,
      isCancelled: () => false,
      onRead: told.add,
    );

    expect(told, [0, 0.5, 0.75, 1], reason: 'one piece, then two clips');
  });

  test('a file that is not a .tvpp comes back from the worker as none',
      () async {
    final path = '${temp.path}${Platform.pathSeparator}junk.tvpp';
    File(path).writeAsBytesSync(List<int>.filled(64, 7));

    expect(
      await readTvppProject(tvppPath: path, isCancelled: () => false),
      isNull,
    );
  });
}
