import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★A CHOSEN 도장 HAS TO REACH THE PAINT PASS.
///
/// 「담당자 = 이름 + 도장 이미지 한 세트」 (cut-envelope 정본 §7), and the
/// card's own spec: 「고른 도장이 컷봉투의 해당 칸에 찍혀야 한다」.
///
/// The model held `stampAssetPath`, the envelope bound `{staff.<role>.stamp}`
/// and the painter took an `imageFor` — but the workspace passed none, with a
/// comment saying a resolver with no source is dead code. The stamp picker is
/// that source now, so this is the piece that was missing.
///
/// ⛔The painter asks SYNCHRONOUSLY, inside a paint pass. So the contract is
/// not "returns the image"; it is "answers null once, and has it by the time
/// it says so".
///
/// ⚠️Everything real here happens inside ONE [WidgetTester.runAsync]. The
/// decode is a genuine file read plus a codec round trip, and the fake async
/// zone a widget test normally runs in never lets it finish — a poll loop
/// that pumps between `runAsync` calls hangs forever (measured).
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('envelope-stamp');
  });
  tearDown(() => deleteTempQuietly(dir));

  /// A real PNG, encoded through the same pipeline the app decodes with — a
  /// hand-written byte blob would test the fixture, not the cache.
  Future<String> writePng(String name) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawPaint(ui.Paint()..color = const ui.Color(0xFF00FF00));
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file.path;
  }

  /// Real time, not pumped time: the decode is off in the engine.
  Future<void> settle(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  testWidgets('the first ask MISSES, and the image is there when it says so', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final path = await writePng('seal.png');
      var loaded = 0;
      final cache = SheetImageCache()..addListener(() => loaded += 1);
      addTearDown(cache.dispose);

      expect(
        cache.imageFor(path),
        isNull,
        reason:
            'a paint pass cannot await, so the first ask has to answer null '
            'rather than block',
      );
      expect(loaded, 0, reason: 'nothing has landed yet');

      await settle(() => loaded > 0);

      expect(loaded, 1, reason: 'the host has to be told exactly once');
      expect(
        cache.imageFor(path),
        isNotNull,
        reason: 'and the image is there the moment it says so',
      );
    });
  });

  testWidgets('⛔a file that cannot be read is remembered as a MISS', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Otherwise every paint reads the disk again for a stamp whose file
      // went away — a decode per frame that can never succeed.
      var loaded = 0;
      final cache = SheetImageCache()..addListener(() => loaded += 1);
      addTearDown(cache.dispose);
      final missing = '${dir.path}/gone.png';

      expect(cache.imageFor(missing), isNull);
      await settle(() => loaded > 0);

      expect(
        cache.imageFor(missing),
        isNull,
        reason: 'still null, and the point is that it did not try again',
      );
      expect(
        loaded,
        1,
        reason:
            'the miss LANDED once — a second ask must not start a second '
            'read, which is what asking `containsKey` rather than testing '
            'the value is for',
      );
    });
  });

  testWidgets('two asks for the same path decode ONCE', (tester) async {
    await tester.runAsync(() async {
      final path = await writePng('logo.png');
      var loaded = 0;
      final cache = SheetImageCache()..addListener(() => loaded += 1);
      addTearDown(cache.dispose);

      // The same frame can paint a box twice; a second decode would be work
      // for nothing and would hand back a second image nobody disposes.
      cache.imageFor(path);
      cache.imageFor(path);
      await settle(() => loaded > 0);

      expect(loaded, 1, reason: 'one decode, one notification');
    });
  });
}
