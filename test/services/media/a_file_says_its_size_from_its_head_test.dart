import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/media/image_viewer_document.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/media_pixel_size.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart'
    show psdHeaderLength;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/the_file_itself.dart';

/// 🚨A file says its size in pixels without being decoded (F-375,
/// 2026-10-17): what the import window's resolution column asks of every
/// row, so a batch of large pictures costs their headers, not their pixels.
///
/// Every kind the window lists: a picture its own pixels, a Photoshop
/// document its canvas, a movie its frame, a PDF its first page as the
/// renderer draws it 1:1 — and a sound none.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('anicel-pixel-size');
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    PdfRenderService.debugResetForTests();
    deleteTempQuietly(dir);
  });

  String write(String name, List<int> bytes) {
    final file = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  (int, int)? said(CanvasSize? size) =>
      size == null ? null : (size.width, size.height);

  Future<(int, int)?> sizeOf(
    WidgetTester tester,
    MediaAssetKind kind,
    String path, {
    HoldMediaBytes hold = theFileItself,
  }) async => said(
    await tester.runAsync<CanvasSize?>(
      () => readMediaPixelSize(kind, path, hold),
    ),
  );

  /// [bytes] stored seven bytes into a file of their own, as a carried
  /// file sits inside the project — read through what the hold hands back,
  /// never by a path of their own.
  HoldMediaBytes inside(List<int> bytes) {
    final archive = write('project.anicel', [...List.filled(7, 0x2A), ...bytes]);
    return (path) async => HeldMediaBytes(
      source: MediaArchiveBytes(
        archivePath: archive,
        dataOffset: 7,
        length: bytes.length,
      ),
      release: () {},
      moved: const Stream<HeldBytesMove>.empty(),
      again: () => throw UnimplementedError(),
    );
  }

  testWidgets('a picture says its own pixels — from a file of its own and '
      'from inside the project', (tester) async {
    final png = (await tester.runAsync(
      () => writeSolidPng(dir, 'a.png', width: 37, height: 23),
    ))!;
    expect(await sizeOf(tester, MediaAssetKind.image, png), (37, 23));

    expect(
      await sizeOf(
        tester,
        MediaAssetKind.image,
        'carried.png',
        hold: inside(File(png).readAsBytesSync()),
      ),
      (37, 23),
    );
  });

  testWidgets('🚨a Photoshop document says its canvas from its HEADER — '
      'a file that is nothing but the header still answers', (tester) async {
    final head = buildPsd(width: 640, height: 480).sublist(0, psdHeaderLength);
    final psd = write('only-the-head.psd', head);

    expect(await sizeOf(tester, MediaAssetKind.image, psd), (640, 480));
    expect(
      await sizeOf(
        tester,
        MediaAssetKind.image,
        'carried.psd',
        hold: inside(head),
      ),
      (640, 480),
    );

    // CONTROL: the document itself cannot be read from these bytes — the
    // answer above came from the header alone, never from a whole read.
    final opened = await tester.runAsync(() async {
      try {
        return await ImageViewerDocument.open(MediaFileBytes(psd));
      } on FormatException {
        return null;
      }
    });
    expect(opened, isNull, reason: 'a header is not a document');
  });

  testWidgets('a movie says its frame as its decoder reads it', (
    tester,
  ) async {
    final backend = FakeVideoBackend(width: 1920, height: 1080);
    debugVideoDecodeBackend = backend;
    final movie = write('cut.mp4', const [0, 0, 0, 24]);

    expect(await sizeOf(tester, MediaAssetKind.video, movie), (1920, 1080));
    expect([for (final at in backend.openedAt) at.path], [movie]);
  });

  testWidgets('a PDF says its first page as the renderer draws it 1:1, and '
      'the document is closed after', (tester) async {
    final pdf = FakePdfDocument(
      pageSizes: const [ui.Size(595.3, 841.9), ui.Size(100, 100)],
    );
    PdfRenderService.debugOpenerOverride = (source) async => pdf;
    final path = write('conte.pdf', const [0x25, 0x50, 0x44, 0x46]);

    expect(await sizeOf(tester, MediaAssetKind.pdf, path), (595, 842));
    expect(pdf.disposed, isTrue);
  });

  testWidgets('every kind gives back the bytes it held once it has its '
      'answer — a list of files asks of every row, and holds none', (
    tester,
  ) async {
    debugVideoDecodeBackend = FakeVideoBackend(width: 64, height: 36);
    PdfRenderService.debugOpenerOverride = (source) async =>
        FakePdfDocument(pageSizes: const [ui.Size(100, 50)]);
    final png = (await tester.runAsync(
      () => writeSolidPng(dir, 'a.png', width: 4, height: 4),
    ))!;
    final files = {
      MediaAssetKind.image: png,
      MediaAssetKind.video: write('cut.mp4', const [0, 0, 0, 24]),
      MediaAssetKind.pdf: write('conte.pdf', const [0x25, 0x50, 0x44, 0x46]),
    };
    for (final MapEntry(key: kind, value: path) in files.entries) {
      var held = 0;
      Future<HeldMediaBytes> counted(String path) async {
        held += 1;
        final file = await theFileItself(path);
        return HeldMediaBytes(
          source: file.source,
          release: () => held -= 1,
          moved: file.moved,
          again: file.again,
        );
      }

      expect(
        await sizeOf(tester, kind, path, hold: counted),
        isNotNull,
        reason: '$kind',
      );
      expect(held, 0, reason: '$kind: given back');
    }
  });

  testWidgets('a sound has none — and neither has a file that cannot be '
      'read', (tester) async {
    final sound = write('se.wav', const [0x52, 0x49, 0x46, 0x46]);
    expect(await sizeOf(tester, MediaAssetKind.audio, sound), isNull);

    final broken = write('broken.png', Uint8List(64));
    expect(await sizeOf(tester, MediaAssetKind.image, broken), isNull);
    expect(
      await sizeOf(tester, MediaAssetKind.image, '${dir.path}/gone.png'),
      isNull,
    );
  });
}
