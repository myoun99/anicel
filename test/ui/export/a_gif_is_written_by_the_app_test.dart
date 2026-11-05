import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️I-152 (유저 2026-11-03): 「동영상 출력? 에 gif 추가 … 아무튼 형식으로
/// 새롭게 gif를 넣고싶음」.
///
/// A GIF is the app's own movie: no OS encoder and no ffmpeg is asked for
/// one, so every machine writes it — a picture a held drawing, shown as
/// long as it is held.
void main() {
  /// Every frame made here: a run lets go of each one it is handed.
  final made = <ui.Image>[];

  tearDown(() {
    expect(
      [
        for (final (index, image) in made.indexed)
          if (!image.debugDisposed) index,
      ],
      isEmpty,
      reason: 'frames still held when the run was over',
    );
    made.clear();
  });

  const red = ui.Color(0xFFE02010);
  const green = ui.Color(0xFF10C030);
  const blue = ui.Color(0xFF2040E0);

  /// A 4×2 frame, all of it [color].
  Future<ui.Image> frame(ui.Color color) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(4, 2);
    made.add(image);
    return image;
  }

  /// [image] handed again, as the renderer hands a held frame.
  ui.Image held(ui.Image image) {
    final again = image.clone();
    made.add(again);
    return again;
  }

  /// The service, failing the test if it asks ffmpeg or an OS encoder.
  final service = VideoExportService(
    processStarter: (executable, arguments) =>
        throw StateError('ffmpeg was started for a GIF'),
    encoderResolver: () => throw StateError('an OS encoder was asked'),
  );

  File outputIn(String name) {
    final folder = Directory.systemTemp.createTempSync('qa-gif');
    deleteAfterSessionEnds(folder);
    return File('${folder.path}${Platform.pathSeparator}$name');
  }

  /// The GIF at [file]: each picture's hundredths and colour.
  List<_Picture> picturesOf(File file) {
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(6)), 'GIF89a');
    final gif = img.decodeGif(bytes)!;
    return [
      for (final picture in gif.frames)
        (
          hundredths: picture.frameDuration ~/ 10,
          r: picture.getPixel(1, 1).r.toInt(),
          g: picture.getPixel(1, 1).g.toInt(),
          b: picture.getPixel(1, 1).b.toInt(),
          a: picture.getPixel(1, 1).a.toInt(),
        ),
    ];
  }

  /// A picture of about [color] — cut to a palette, so near it.
  Matcher about(ui.Color color) => isA<_Picture>()
      .having((p) => p.r, 'r', closeTo((color.r * 255).round(), 12))
      .having((p) => p.g, 'g', closeTo((color.g * 255).round(), 12))
      .having((p) => p.b, 'b', closeTo((color.b * 255).round(), 12));

  test('🚨every machine writes it: nothing but the app is asked — a GIF89a '
      'of the frames, each shown its frame\'s time as the GIF counts it, '
      'in hundredths that add up to the film\'s', () async {
    final file = outputIn('film.gif');
    final colors = [red, green, blue];
    final summary = await service.exportVideo(
      count: 3,
      renderImage: (index) => frame(colors[index]),
      outputFilePath: file.path,
      frameRate: const ProjectFrameRate.integer(12),
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    expect(summary, (written: 3, processed: 3));
    final pictures = picturesOf(file);
    expect([for (final p in pictures) p.hundredths], [8, 9, 8]);
    expect(pictures, [about(red), about(green), about(blue)]);
  });

  test('🚨a frame that is the picture before it goes in as no picture of its '
      'own: the picture is shown as long as it is held', () async {
    final file = outputIn('held.gif');
    final first = await frame(red);
    final last = await frame(blue);
    final frames = [first, held(first), held(first), last];
    final summary = await service.exportVideo(
      count: 4,
      renderImage: (index) async => frames[index],
      outputFilePath: file.path,
      frameRate: ProjectFrameRate.fps24,
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    expect(summary.written, 4, reason: 'every frame of the film is in it');
    final pictures = picturesOf(file);
    // 24 fps: the frames start at 0, 4.17, 8.33, 12.5 and end at 16.67.
    expect([for (final p in pictures) p.hundredths], [13, 4]);
    expect(pictures, [about(red), about(blue)]);
  });

  test('a picture held for less than a GIF can show is let go, and the next '
      'takes its time — the film keeps its length', () async {
    final file = outputIn('quick.gif');
    final colors = [red, green, blue];
    await service.exportVideo(
      count: 3,
      renderImage: (index) => frame(colors[index]),
      outputFilePath: file.path,
      frameRate: const ProjectFrameRate.integer(60),
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    final pictures = picturesOf(file);
    // 60 fps: the frames start at 0, 1.67, 3.33 and end at 5 — the green
    // one stands from 2 to 3, under the two hundredths a GIF shows.
    expect([for (final p in pictures) p.hundredths], [2, 3]);
    expect(pictures, [about(red), about(blue)]);
  });

  test('a GIF asked for RGB is opaque: a frame that leaves its ground clear '
      'is no transparent colour of it', () async {
    final file = outputIn('clear.gif');
    await service.exportVideo(
      count: 1,
      renderImage: (_) => frame(const ui.Color(0x00000000)),
      outputFilePath: file.path,
      frameRate: ProjectFrameRate.fps24,
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    expect(picturesOf(file).single.a, 255);
  });

  test('🚨cancelled mid-run, the GIF keeps the frames it got to', () async {
    final file = outputIn('stopped.gif');
    var rendered = 0;
    final colors = [red, green, blue];
    final summary = await service.exportVideo(
      count: 3,
      renderImage: (index) {
        rendered += 1;
        return frame(colors[index]);
      },
      outputFilePath: file.path,
      frameRate: const ProjectFrameRate.integer(12),
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
      isCancelled: () => rendered >= 2,
    );

    expect(summary, (written: 2, processed: 2));
    expect([for (final p in picturesOf(file)) p.hundredths], [8, 9]);
  });

  group('🗣️what a GIF is asked (「색처리든 뭐든 gif에대한 세부설정가능한거 '
      '두고싶어」)', () {
    /// A frame [width]×[height] whose pixel at (x, y) is [colorAt]'s.
    Future<ui.Image> painted(
      int width,
      int height,
      ui.Color Function(int x, int y) colorAt,
    ) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (var y = 0; y < height; y += 1) {
        for (var x = 0; x < width; x += 1) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            ui.Paint()
              ..color = colorAt(x, y)
              ..blendMode = ui.BlendMode.src,
          );
        }
      }
      final image = await recorder.endRecording().toImage(width, height);
      made.add(image);
      return image;
    }

    /// 64 greys, 0 to 252, a column apiece.
    Future<ui.Image> greys() =>
        painted(64, 2, (x, _) => ui.Color.fromARGB(255, x * 4, x * 4, x * 4));

    /// The GIF at [name] of the one frame [image], as [settings] ask.
    Future<File> written(
      String name,
      ui.Image image, {
      ExportGifSettings settings = const ExportGifSettings(),
      bool alpha = false,
    }) async {
      final file = outputIn(name);
      await service.exportVideo(
        count: 1,
        renderImage: (_) async => image,
        outputFilePath: file.path,
        frameRate: ProjectFrameRate.fps24,
        container: ExportVideoContainer.gif,
        codec: ExportVideoCodec.gif,
        alpha: alpha,
        gif: settings,
      );
      return file;
    }

    /// The first picture of the GIF at [file], a pixel at a time, row by
    /// row.
    List<(int, int, int, int)> pixelsOf(File file) => [
      for (final p in img.decodeGif(file.readAsBytesSync())!)
        (p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()),
    ];

    /// How often the colour changes along the first row of [pixels], 64
    /// long.
    int changesOf(List<(int, int, int, int)> pixels) => [
      for (var x = 1; x < 64; x += 1)
        if (pixels[x] != pixels[x - 1]) x,
    ].length;

    test('an octree keeps every colour of a picture that holds no more '
        'than its palette', () async {
      final file = await written('exact.gif', await greys());
      expect(
        [for (final p in pixelsOf(file).take(64)) p.$1],
        [for (var x = 0; x < 64; x += 1) x * 4],
      );
    });

    test('🚨the palette is as large as it is asked: 64 greys cut to four '
        'colours hold four', () async {
      final file = await written(
        'four.gif',
        await greys(),
        settings: const ExportGifSettings(
          colors: 4,
          dither: ExportGifDither.none,
        ),
      );
      expect(pixelsOf(file).toSet(), hasLength(4));
    });

    test('black and white is two, by brightness, whatever count is '
        'asked', () async {
      final file = await written(
        'bw.gif',
        await greys(),
        settings: const ExportGifSettings(
          reduction: ExportGifReduction.blackWhite,
          dither: ExportGifDither.none,
        ),
      );
      expect(pixelsOf(file).toSet(), {
        (0, 0, 0, 255),
        (255, 255, 255, 255),
      });
    });

    // 🐞I-152 (2026-11-05): the package's black and white asked a dither's
    // channels their brightness out of 255 against a half — every grey but
    // black went white, and the ramp came out light.
    test('🚨black and white cuts by brightness through a dither too: the '
        'greys come out as dark as they went in', () async {
      final undithered = pixelsOf(
        await written(
          'bw-none.gif',
          await greys(),
          settings: const ExportGifSettings(
            reduction: ExportGifReduction.blackWhite,
            dither: ExportGifDither.none,
          ),
        ),
      ).where((p) => p.$1 == 0).length;
      expect(undithered, 64, reason: 'the greys straddle the cut mid-row');
      for (final dither in [
        ExportGifDither.floydSteinberg,
        ExportGifDither.stucki,
        ExportGifDither.atkinson,
      ]) {
        final black = pixelsOf(
          await written(
            'bw-${dither.name}.gif',
            await greys(),
            settings: ExportGifSettings(
              reduction: ExportGifReduction.blackWhite,
              dither: dither,
            ),
          ),
        ).where((p) => p.$1 == 0).length;
        expect(
          black,
          closeTo(undithered, 2),
          reason: '${dither.name}: a dither spreads the cut, not the mean',
        );
      }
    });

    test('a neural net learns the colours near: not the octree\'s '
        'palette', () async {
      const eight = ExportGifSettings(colors: 8, dither: ExportGifDither.none);
      final octree = pixelsOf(
        await written('octree.gif', await greys(), settings: eight),
      );
      final neural = pixelsOf(
        await written(
          'neural.gif',
          await greys(),
          settings: eight.copyWith(reduction: ExportGifReduction.neural),
        ),
      );
      expect(neural, isNot(octree));
    });

    test('🚨undithered, greys cut to two are two plain halves; each kernel '
        'spreads them, each its own way', () async {
      const two = ExportGifSettings(colors: 2, dither: ExportGifDither.none);
      final plain = pixelsOf(
        await written('plain.gif', await greys(), settings: two),
      );
      expect(changesOf(plain), 1);
      final spread = <String>{};
      for (final dither in [
        ExportGifDither.floydSteinberg,
        ExportGifDither.stucki,
        ExportGifDither.atkinson,
      ]) {
        final pixels = pixelsOf(
          await written(
            '${dither.name}.gif',
            await greys(),
            settings: two.copyWith(dither: dither),
          ),
        );
        expect(changesOf(pixels), greaterThan(1), reason: dither.name);
        spread.add('$pixels');
      }
      expect(spread, hasLength(3), reason: 'three kernels, three pictures');
    });

    /// What [strokes] lays at (x, y): a soft red stroke over white in the
    /// top eight rows, a soft blue one under it — every pixel its own
    /// cover, as a brush lays them.
    ui.Color strokeAt(int x, int y) => ui.Color.lerp(
      const ui.Color(0xFFFFFFFF),
      y < 8 ? const ui.Color(0xFFD83C2C) : const ui.Color(0xFF3C7FCD),
      (x * 4 + (y % 8) * 31) % 256 / 255,
    )!;

    /// More colours than a palette holds.
    Future<ui.Image> strokes() => painted(64, 16, strokeAt);

    /// [pixel]'s distance from what [strokes] laid there, the worst channel.
    int offBy((int, int, int, int) pixel, int x, int y) {
      final laid = strokeAt(x, y);
      final (r, g, b, _) = pixel;
      return [
        (r - (laid.r * 255).round()).abs(),
        (g - (laid.g * 255).round()).abs(),
        (b - (laid.b * 255).round()).abs(),
      ].reduce(math.max);
    }

    test('🚨a colour the palette has no room for goes to the NEAREST entry: '
        'a red stroke stays red and a blue one blue, dithered or not — '
        '「빨강 획까지 전부 파랑」 (AI 검증 11-04)', () async {
      for (final dither in [
        ExportGifDither.floydSteinberg,
        ExportGifDither.none,
      ]) {
        final pixels = pixelsOf(
          await written(
            '${dither.name}-strokes.gif',
            await strokes(),
            settings: ExportGifSettings(dither: dither),
          ),
        );
        // A near-white pixel may lean either way by a few levels; the
        // stroke itself never crosses over.
        for (final (at, pixel) in pixels.indexed) {
          final (r, _, b, _) = pixel;
          final red = at ~/ 64 < 8;
          expect(
            red ? r + 16 >= b : b + 16 >= r,
            isTrue,
            reason: '${dither.name}: ${red ? 'red' : 'blue'} stroke at '
                '${at % 64},${at ~/ 64} came out $pixel',
          );
        }
        if (dither == ExportGifDither.none) {
          final worst = [
            for (final (at, pixel) in pixels.indexed)
              offBy(pixel, at % 64, at ~/ 64),
          ].reduce(math.max);
          expect(worst, lessThan(24), reason: 'undithered, each is near');
        }
      }
    });

    test('🚨cut to four, a small stroke keeps a colour of its own: an '
        'octree folds a branch whole, never part of it into its parent — '
        '「획이 통째로 없다」 (AI 검증 11-04)', () async {
      // White, and in its corners a red square and a blue one — 16 shades
      // each, a sixty-fourth of the picture.
      Future<ui.Image> squares() => painted(32, 32, (x, y) {
        final shade = (x % 4) * 4 + y % 4;
        return x < 4 && y < 4
            ? ui.Color.fromARGB(255, 200 + shade, 40, 30)
            : x >= 28 && y >= 28
            ? ui.Color.fromARGB(255, 30, 60, 200 + shade)
            : const ui.Color(0xFFFFFFFF);
      });
      for (final dither in [
        ExportGifDither.none,
        ExportGifDither.floydSteinberg,
      ]) {
        final pixels = pixelsOf(
          await written(
            '${dither.name}-four.gif',
            await squares(),
            settings: ExportGifSettings(colors: 4, dither: dither),
          ),
        );
        final red = pixels[33];
        final (r, g, b, _) = red;
        expect(
          r > 150 && g < 100 && b < 100,
          isTrue,
          reason: '${dither.name}: the red square came out $red',
        );
        final blue = pixels[30 * 32 + 30];
        final (r2, g2, b2, _) = blue;
        expect(
          b2 > 150 && r2 < 100 && g2 < 120,
          isTrue,
          reason: '${dither.name}: the blue square came out $blue',
        );
      }
    });

    /// The loop count the GIF at [file] says, or null where it says none.
    int? loopCountOf(File file) {
      final bytes = file.readAsBytesSync();
      final at = String.fromCharCodes(bytes).indexOf('NETSCAPE2.0');
      return at < 0 ? null : bytes[at + 13] | bytes[at + 14] << 8;
    }

    test('🚨it plays as many times as it is asked: forever is a count of '
        'zero, and once is no count at all — a player plays a GIF once more '
        'than its count says', () async {
      expect(loopCountOf(await written('forever.gif', await frame(red))), 0);
      expect(
        loopCountOf(
          await written(
            'thrice.gif',
            await frame(red),
            settings: const ExportGifSettings(plays: 3),
          ),
        ),
        2,
      );

      final once = outputIn('once.gif');
      final colors = [red, green, blue];
      await service.exportVideo(
        count: 3,
        renderImage: (index) => frame(colors[index]),
        outputFilePath: once.path,
        frameRate: const ProjectFrameRate.integer(12),
        container: ExportVideoContainer.gif,
        codec: ExportVideoCodec.gif,
        gif: const ExportGifSettings(plays: 1),
      );
      expect(loopCountOf(once), isNull);
      expect(
        picturesOf(once),
        [about(red), about(green), about(blue)],
        reason: 'the film is whole without its loop block',
      );
    });

    test('🚨asked for RGBA, a pixel under half covered is the clear colour, '
        'and the rest are opaque in the colour they were laid with', () async {
      final image = await painted(4, 1, (x, _) => switch (x) {
        0 => const ui.Color(0x00000000),
        1 => red.withAlpha(0x40),
        2 => red.withAlpha(0xC0),
        _ => red,
      });
      final [none, quarter, threeQuarters, whole] = pixelsOf(
        await written('clear.gif', image, alpha: true),
      );
      expect(none.$4, 0);
      expect(quarter.$4, 0);
      expect(whole, (224, 32, 16, 255));
      expect(threeQuarters.$4, 255);
      expect(
        [threeQuarters.$1, threeQuarters.$2, threeQuarters.$3],
        [closeTo(224, 3), closeTo(32, 3), closeTo(16, 3)],
        reason: 'the colour it was laid with, not darkened by its cover',
      );
    });

    test('a frame left all clear is all the clear colour, whichever way '
        'the palette is found among no colours', () async {
      for (final reduction in ExportGifReduction.values) {
        final pixels = pixelsOf(
          await written(
            'nothing-${reduction.name}.gif',
            await frame(const ui.Color(0x00000000)),
            alpha: true,
            settings: ExportGifSettings(reduction: reduction),
          ),
        );
        expect({for (final p in pixels) p.$4}, {0}, reason: reduction.name);
      }
    });

    test('🚨the clear colour is an entry of its own beside a full palette — '
        'as the octree finds it and as the net does', () async {
      for (final reduction in [
        ExportGifReduction.octree,
        ExportGifReduction.neural,
      ]) {
        // 1024 colours, the top left 4×4 of them clear.
        final image = await painted(
          32,
          32,
          (x, y) => x < 4 && y < 4
              ? const ui.Color(0x00000000)
              : ui.Color.fromARGB(255, x * 8, y * 8, 128),
        );
        final pixels = pixelsOf(
          await written(
            '${reduction.name}-full.gif',
            image,
            alpha: true,
            settings: ExportGifSettings(reduction: reduction),
          ),
        );
        expect(
          [
            for (final (index, p) in pixels.indexed)
              if (p.$4 == 0) (index % 32, index ~/ 32),
          ],
          [
            for (var y = 0; y < 4; y += 1)
              for (var x = 0; x < 4; x += 1) (x, y),
          ],
          reason: reduction.name,
        );
      }
    });

    test('🚨a clear pixel carries no error of its own into the laid ones '
        'beside it: under a clear row, greys dither as they do '
        'alone', () async {
      // The same greys, alone and under a row left clear — one colour more
      // asked of the second for its clear entry, so both palettes are found
      // among the same greys at the same size.
      final alone = pixelsOf(
        await written(
          'alone.gif',
          await greys(),
          settings: const ExportGifSettings(colors: 2),
        ),
      );
      final underClear = pixelsOf(
        await written(
          'under-clear.gif',
          await painted(
            64,
            3,
            (x, y) => y == 0
                ? const ui.Color(0x00000000)
                : ui.Color.fromARGB(255, x * 4, x * 4, x * 4),
          ),
          alpha: true,
          settings: const ExportGifSettings(colors: 3),
        ),
      );
      expect(changesOf(alone), greaterThan(1), reason: 'LIVENESS — dithered');
      expect(underClear.sublist(64), alone);
    });
  });

  test('every machine may pick it: no encoder and no ffmpeg stands between '
      'the window and a GIF', () {
    final availability = ExportFormatAvailability(
      encoderResolver: () => null,
      ffmpegCheck: () async => false,
      jpgSupported: true,
    );
    addTearDown(availability.dispose);
    expect(
      availability.videoAllowed(
        ExportVideoContainer.gif,
        ExportVideoCodec.gif,
      ),
      isTrue,
    );
    expect(
      availability.videoAllowed(
        ExportVideoContainer.mp4,
        ExportVideoCodec.h264,
      ),
      isFalse,
      reason: 'LIVENESS — a movie the machine writes, with nothing to write it',
    );
  });

  test('🚨where the OS writes movies, it is asked of its own alone: a GIF is '
      'no pair of its to probe', () {
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    final availability = ExportFormatAvailability(
      encoderResolver: () => encoder,
      ffmpegCheck: () async => false,
      jpgSupported: true,
    );
    addTearDown(availability.dispose);
    expect(
      availability.videoAllowed(
        ExportVideoContainer.gif,
        ExportVideoCodec.gif,
      ),
      isTrue,
    );
  });
}

/// One picture of a GIF: how long it is shown, and its colour.
typedef _Picture = ({int hundredths, int r, int g, int b, int a});
