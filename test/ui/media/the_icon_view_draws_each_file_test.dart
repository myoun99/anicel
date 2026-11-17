import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/media/media_pool_pictures.dart';
import 'package:anicel/src/ui/media/media_pool_view.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🗣️asset-placement-presets Q4 · Q6 (유저 2026-11-17): the icon view draws
/// each file as a big picture — 「아이콘보기는 큰 썸네일」 — and a movie or
/// a GIF follows the cursor across it — 「프리미어처럼 호버된 마우스커서대로
/// 플립」. Its pictures are held as large as their boxes, like every picture
/// drawn as large as it is shown.
void main() {
  final movie = MediaAsset(
    path: 'C:/mov/walk.mp4',
    name: 'walk',
    kind: MediaAssetKind.video,
    frameCount: 10,
  );
  final still = MediaAsset(
    path: 'C:/pic/cloud.png',
    name: 'cloud',
    kind: MediaAssetKind.image,
  );
  final book = MediaAsset(
    path: 'C:/doc/board.pdf',
    name: 'board',
    kind: MediaAssetKind.pdf,
    pageCount: 4,
  );

  FakePdfDocument pages(int count, {ui.Size size = const ui.Size(320, 200)}) =>
      FakePdfDocument(
        pageSizes: List.filled(count, size),
        drawnAtAnySize: false,
      );

  Future<void> settle(WidgetTester tester) async {
    for (var turn = 0; turn < 6; turn += 1) {
      await tester.pump();
    }
  }

  group('the pictures', () {
    late List<String> opened;
    MediaPoolPictures poolOf(Map<String, FakePdfDocument?> files) {
      opened = [];
      return MediaPoolPictures(
        open: (asset) async {
          opened.add(asset.path);
          return files[asset.path];
        },
      );
    }

    testWidgets('a page is drawn contained in its box, never past its own '
        'pixels unless it is drawn at any size', (tester) async {
      final wide = pages(1, size: const ui.Size(1000, 500));
      final small = pages(1, size: const ui.Size(100, 50));
      final vector = FakePdfDocument(pageSizes: const [ui.Size(100, 50)]);
      final pictures = poolOf({
        movie.path: wide,
        still.path: small,
        book.path: vector,
      });
      addTearDown(pictures.dispose);

      expect(pictures.pictureOf(movie, page: 0, width: 160), isNull);
      await settle(tester);
      final drawn = pictures.pictureOf(movie, page: 0, width: 160)!;
      expect((drawn.width, drawn.height), (160, 80));

      pictures.pictureOf(still, page: 0, width: 320);
      await settle(tester);
      pictures.pictureOf(book, page: 0, width: 320);
      await settle(tester);

      expect(wide.renderRequests, [(0, 160, 80)]);
      expect(small.renderRequests, [(0, 100, 50)], reason: 'its own pixels');
      expect(vector.renderRequests, [(0, 320, 160)], reason: 'drawn any size');
    });

    testWidgets('a file that cannot be opened is asked once, however often '
        'its box is drawn', (tester) async {
      final pictures = poolOf({});
      addTearDown(pictures.dispose);
      for (var draw = 0; draw < 3; draw += 1) {
        expect(pictures.pictureOf(still, page: 0, width: 160), isNull);
        await settle(tester);
      }
      expect(opened, [still.path]);
    });

    testWidgets('no more than two files stay open, the one drawn from '
        'least recently closed first', (tester) async {
      final files = {
        movie.path: pages(2),
        still.path: pages(1),
        book.path: pages(1),
      };
      final pictures = poolOf(files);
      for (final (asset, page) in [
        (movie, 0),
        (still, 0),
        (movie, 1),
        (book, 0),
      ]) {
        pictures.pictureOf(asset, page: page, width: 160);
        await settle(tester);
      }
      expect(opened, [movie.path, still.path, book.path]);
      expect(files[still.path]!.disposed, isTrue);
      expect(files[movie.path]!.disposed, isFalse);
      expect(files[book.path]!.disposed, isFalse);

      pictures.dispose();
      await settle(tester);
      expect(files.values.every((file) => file.disposed), isTrue);
    });

    testWidgets('while the frame under the cursor renders, the box keeps the '
        'frame it drew last', (tester) async {
      final walk = pages(10);
      final pictures = poolOf({movie.path: walk});
      addTearDown(pictures.dispose);
      pictures.pictureOf(movie, page: 0, width: 160);
      await settle(tester);
      final first = pictures.pictureOf(movie, page: 0, width: 160);

      walk.holdRender(6);
      await settle(tester);
      expect(pictures.pictureOf(movie, page: 6, width: 160), same(first));

      walk.releaseRender(6);
      await settle(tester);
      final sixth = pictures.pictureOf(movie, page: 6, width: 160);
      expect(sixth, isNotNull);
      expect(sixth, isNot(same(first)));
    });
  });

  group('the boxes', () {
    late Map<String, FakePdfDocument> files;
    late MediaPoolPictures pictures;

    Future<void> pump(WidgetTester tester) async {
      files = {
        // Wider than any box here, so a box asks for its own width.
        movie.path: pages(10, size: const ui.Size(1920, 1200)),
        still.path: pages(1),
        book.path: pages(4),
      };
      pictures = MediaPoolPictures(open: (asset) async => files[asset.path]);
      addTearDown(pictures.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 600,
                child: MediaPoolPanel(
                  assets: [movie, still, book],
                  usesOf: (_) => const [],
                  onImportRequested: () {},
                  onRenameAsset: (_, _) {},
                  onRelinkAsset: (_, _, _) {},
                  onRemoveAsset: (_) {},
                  onExportAssetWav: (_) async => true,
                  onPromoteAsset: (_) async => true,
                  view: const MediaPoolView(icons: true),
                  pictures: pictures,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    Finder box(MediaAsset asset) =>
        find.byKey(ValueKey<String>('media-pool-box-${asset.path}'));

    /// The page [asset]'s box draws now.
    int pageDrawn(WidgetTester tester, MediaAsset asset) {
      final painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: box(asset),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.painter.runtimeType.toString() == '_PicturePainter',
              ),
            ),
          )
          .painter;
      // ignore: avoid_dynamic_calls
      return (painter! as dynamic).page as int;
    }

    Future<TestGesture> hover(WidgetTester tester, Offset at) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // Added, a pointer is not hovering yet: the move in is the hover.
      await mouse.addPointer();
      await mouse.moveTo(at);
      await settle(tester);
      return mouse;
    }

    testWidgets('each file is a box over its name, drawn at the box\'s width '
        'and dragged as its line is', (tester) async {
      await pump(tester);
      expect(find.text('walk'), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('media-asset-row-${movie.path}')),
        findsOneWidget,
      );
      final width = tester.getSize(box(movie)).width;
      expect(
        files[movie.path]!.renderRequests.first.$2,
        (width * tester.view.devicePixelRatio).round(),
      );
    });

    testWidgets('the cursor across a movie is its place in the movie, and off '
        'the box it draws its first frame again', (tester) async {
      await pump(tester);
      final area = tester.getRect(box(movie));
      final mouse = await hover(
        tester,
        Offset(area.left + area.width * 0.75, area.center.dy),
      );
      expect(pageDrawn(tester, movie), 7);
      expect(files[movie.path]!.renderRequests.map((ask) => ask.$1), [0, 7]);

      await mouse.moveTo(Offset(area.left + 1, area.center.dy));
      await settle(tester);
      expect(pageDrawn(tester, movie), 0);

      await mouse.moveTo(Offset(area.right - 1, area.center.dy));
      await settle(tester);
      expect(pageDrawn(tester, movie), 9);

      await mouse.moveTo(area.bottomRight + const Offset(40, 40));
      await settle(tester);
      expect(pageDrawn(tester, movie), 0);
      await mouse.removePointer();
    });

    testWidgets('a still and a PDF\'s pages stay as they are under the '
        'cursor', (tester) async {
      await pump(tester);
      for (final asset in [still, book]) {
        final area = tester.getRect(box(asset));
        final mouse = await hover(
          tester,
          Offset(area.left + area.width * 0.75, area.center.dy),
        );
        expect(pageDrawn(tester, asset), 0);
        await mouse.removePointer();
      }
      expect(files[book.path]!.renderRequests.map((ask) => ask.$1), [0]);
    });
  });
}
