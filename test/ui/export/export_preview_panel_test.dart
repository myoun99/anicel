import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/viewport_pages_painter.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_preview_document.dart';
import 'package:anicel/src/ui/export/export_preview_panel.dart';
import 'package:anicel/src/ui/export/offscreen_raster.dart';
import 'package:anicel/src/ui/media/viewer_render_tier.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/export_preview_probe.dart';

/// 🗣️F-289 (유저 2026-10-06): the export window's preview is a canvas-base
/// panel, and such a panel wears what its document is — 「이 캔버스
/// 베이스패널은 형식에 따라 나누기로하자 … pdf면 타임시트나 콘티용지패널이랑
/// 같은 알약쓰고, 한장짜리면 그 알약조차 없애고, 동영상같은거면 아래에
/// 재생ui 넣고」.
///
/// The panel alone, over documents made here: what it wears, the pixels it
/// asks a page at, the picture it keeps up while another is on its way, and
/// its run.
void main() {
  late EditorSessionManager session;
  late ValueNotifier<int> at;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    at = ValueNotifier<int>(0);
  });
  tearDown(() {
    at.dispose();
    session.dispose();
  });

  const small = CanvasSize(width: 64, height: 36);
  const transport = ValueKey<String>('canvas-transport');
  const strip = ValueKey<String>('canvas-page-strip');

  /// A document of [pages] pages, each a flat picture of its own grey —
  /// every ask of it written down in [asks].
  ExportPreviewDocument document({
    Object subject = 'file',
    Object look = 'plain',
    ExportPreviewShape shape = ExportPreviewShape.runs,
    int pages = 4,
    CanvasSize size = small,
    bool opensAlpha = false,
    List<(int page, CanvasSize size)>? asks,
  }) => ExportPreviewDocument(
    subject: subject,
    look: look,
    shape: shape,
    pageCount: pages,
    framesPerSecond: shape == ExportPreviewShape.runs ? 24 : null,
    opensAlpha: opensAlpha,
    sizeOf: (_) => size,
    renderAt: (page, at) {
      asks?.add((page, at));
      return rasterizeOffscreen(
        width: at.width,
        height: at.height,
        paint: (canvas) => canvas.drawColor(
          Color.fromARGB(255, 40 + page * 40, 0, 0),
          BlendMode.src,
        ),
      );
    },
  );

  /// The panel over [shown], standing where [at] says — which a turn of the
  /// panel writes, as the window's own state does.
  Future<void> pump(
    WidgetTester tester,
    ExportPreviewDocument? shown, {
    TransportRange? range,
    String? fileName,
    bool fileAbsent = false,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 420,
              child: ValueListenableBuilder<int>(
                valueListenable: at,
                builder: (context, page, _) => ExportPreviewPanel(
                  session: session,
                  document: shown,
                  page: page,
                  onPage: (next) => at.value = next,
                  nothingToShow: 'Nothing to write',
                  range: range,
                  fileName: fileName,
                  fileAbsent: fileAbsent,
                  enabled: enabled,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Stands on [page] and waits for its picture.
  Future<ui.Image> landed(WidgetTester tester, int page) async {
    at.value = page;
    await tester.pump();
    await tester.settleExportPreview();
    return tester.exportPreviewImage!;
  }

  ViewportPagesPainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey<String>('export-preview-page')),
              )
              .painter!
          as ViewportPagesPainter;

  group('the panel wears what its document is', () {
    testWidgets('🚨one that runs stands on the transport; a book turns its '
        'pages on the left; a single picture has neither', (tester) async {
      await pump(tester, document());
      expect(find.byKey(transport), findsOneWidget);
      expect(find.byKey(strip), findsNothing);

      await pump(tester, document(shape: ExportPreviewShape.book, pages: 3));
      expect(find.byKey(transport), findsNothing);
      expect(find.byKey(strip), findsOneWidget);

      await pump(tester, document(shape: ExportPreviewShape.single, pages: 3));
      expect(find.byKey(transport), findsNothing);
      expect(
        find.byKey(strip),
        findsNothing,
        reason: 'the drawings of a row are each ONE picture — what turns '
            'from one to the next is the list under the panel',
      );
    });

    testWidgets('a run of ONE frame keeps its transport — the rows are there, '
        'with nowhere to go', (tester) async {
      await pump(tester, document(pages: 1));
      expect(find.byKey(transport), findsOneWidget);
      expect(tester.exportTransport.frameCount, 1);
      expect(tester.exportTransport.onPlayPause, isNull);
    });

    testWidgets('IN and OUT are a row of the transport where the window '
        'hands a span, and are not there where it does not', (tester) async {
      const range = ValueKey<String>('export-transport-range');
      await pump(tester, document());
      expect(find.byKey(range), findsNothing);

      await pump(
        tester,
        document(),
        range: TransportRange(inFrame: 1, outFrame: 2, onChanged: (_, _) {}),
      );
      expect(find.byKey(range), findsOneWidget);
    });

    testWidgets('the file\'s name is on the plate — in the ink of what is '
        'off while it names a picture the run does not write', (tester) async {
      Text plate() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('canvas-document-name')),
          matching: find.byType(Text),
        ),
      );

      await pump(tester, document(), fileName: 'A1.png');
      expect(plate().data, 'A1.png');
      expect(plate().style!.color, AppColors.text);

      await pump(tester, document(), fileName: 'A1', fileAbsent: true);
      expect(plate().data, 'A1');
      expect(
        plate().style!.color,
        AppColors.text.withValues(alpha: AppColors.offAlpha),
      );
    });

    testWidgets('with nothing to write the panel says so, wears nothing and '
        'names nothing', (tester) async {
      await pump(tester, null, fileName: 'A1.png');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('export-preview-empty')),
          matching: find.text('Nothing to write'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(transport), findsNothing);
      expect(find.byKey(strip), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('canvas-document-name')),
        findsNothing,
      );
      expect(
        tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
            .hasContentToView,
        isFalse,
      );
    });

    testWidgets('open alpha stands on the canvas\'s checker; an opaque file '
        'on nothing', (tester) async {
      await pump(tester, document(opensAlpha: true));
      expect(painter(tester).ground, ViewportPageGround.checker);
      await pump(tester, document());
      expect(painter(tester).ground, ViewportPageGround.none);
    });
  });

  group('the pixels a page is asked at', () {
    testWidgets('🚨never more than the file has: a small file fitted large is '
        'asked at its own pixels', (tester) async {
      final asks = <(int, CanvasSize)>[];
      await pump(tester, document(asks: asks));
      expect(
        painter(tester).viewport.zoom * painter(tester).effectiveRatio,
        greaterThan(1),
        reason: 'LIVENESS — the fit magnifies it',
      );
      expect(asks, [(0, small)]);
    });

    testWidgets('a large file fitted small is asked at the share of its '
        'pixels the view draws — the viewer\'s ladder, never less than is '
        'drawn', (tester) async {
      const large = CanvasSize(width: 4000, height: 3000);
      final asks = <(int, CanvasSize)>[];
      await pump(tester, document(size: large, asks: asks));
      final shown = painter(tester);
      final coverage = shown.viewport.zoom * shown.effectiveRatio;
      expect(coverage, lessThan(0.5), reason: 'LIVENESS — the fit reduces it');

      final (_, asked) = asks.single;
      final scale = asked.width / large.width;
      expect(scale, viewerRenderScaleFor(coverage, const Size(4000, 3000)));
      expect(scale, greaterThanOrEqualTo(coverage));
      expect(scale, lessThan(1));
      expect(asked.height, (large.height * scale).round());
    });

    testWidgets('a page of another size is a view nobody has framed yet: it '
        'is fitted again', (tester) async {
      await pump(tester, document());
      final before = painter(tester).viewport.zoom;
      await pump(
        tester,
        document(size: const CanvasSize(width: 640, height: 360)),
      );
      expect(painter(tester).viewport.zoom, closeTo(before / 10, before / 100));
    });
  });

  group('the picture that is up', () {
    testWidgets('one ask is out at a time, and it is the latest: frames a '
        'hand passes are not rendered', (tester) async {
      final asks = <(int, CanvasSize)>[];
      await pump(tester, document(asks: asks));
      for (final page in [1, 2, 3]) {
        at.value = page;
        await tester.pump();
      }
      expect(
        [for (final (page, _) in asks) page],
        [0],
        reason: 'the first ask has not answered, and nothing queues behind it',
      );

      await tester.settleExportPreview();
      expect([for (final (page, _) in asks) page], [0, 3]);
    });

    testWidgets('🚨a hand on the track: the last picture drawn stays up until '
        'the frame it stops on lands', (tester) async {
      await pump(tester, document());
      final first = await landed(tester, 0);

      at.value = 2;
      await tester.pump();
      expect(tester.exportTransport.currentFrame, 2);
      expect(
        identical(tester.exportPreviewImage, first),
        isTrue,
        reason: 'it went blank between frames',
      );

      await tester.settleExportPreview();
      expect(identical(tester.exportPreviewImage, first), isFalse);
      // A frame already drawn is there the moment it is turned back to.
      at.value = 0;
      await tester.pump();
      expect(identical(tester.exportPreviewImage, first), isTrue);
    });

    testWidgets('🚨a setting that changes the LOOK keeps the picture up until '
        'the new one lands — through a second change too', (tester) async {
      final asks = <(int, CanvasSize)>[];
      await pump(tester, document(look: 'a', asks: asks));
      final first = await landed(tester, 0);
      asks.clear();

      await pump(tester, document(look: 'b', asks: asks));
      expect(identical(tester.exportPreviewImage, first), isTrue);
      expect(asks, hasLength(1), reason: 'the page is owed a new render');

      await pump(tester, document(look: 'c', asks: asks));
      expect(identical(tester.exportPreviewImage, first), isTrue);

      await tester.settleExportPreview();
      expect(identical(tester.exportPreviewImage, first), isFalse);
      expect(tester.exportPreviewImage, isNotNull);
    });

    testWidgets('a look kept is nothing asked again', (tester) async {
      final asks = <(int, CanvasSize)>[];
      await pump(tester, document(look: ('a', 1), asks: asks));
      await landed(tester, 0);
      asks.clear();
      await pump(tester, document(look: ('a', 1), asks: asks));
      expect(asks, isEmpty);
    });

    testWidgets('another SUBJECT is another thing to look at: nothing of the '
        'last is kept — nor of a sheet of another size', (tester) async {
      await pump(tester, document(subject: 'sequence'));
      await landed(tester, 0);

      await pump(tester, document(subject: 'image'));
      expect(tester.exportPreviewImage, isNull);
      await tester.settleExportPreview();
      expect(tester.exportPreviewImage, isNotNull);

      await pump(
        tester,
        document(
          subject: 'image',
          look: 'paper',
          size: const CanvasSize(width: 36, height: 64),
        ),
      );
      expect(
        tester.exportPreviewImage,
        isNull,
        reason: 'a picture of another shape was drawn into this page',
      );
    });
  });

  group('the run', () {
    Future<void> pressPlay(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('export-transport-play')),
      );
      await tester.pump();
    }

    const frame = Duration(milliseconds: 42);

    testWidgets('plays the frames that have landed, one a tick, and stops '
        'on the last', (tester) async {
      await pump(tester, document(pages: 3));
      for (final page in [2, 1, 0]) {
        await landed(tester, page);
      }

      await pressPlay(tester);
      expect(tester.exportTransport.playing, isTrue);
      await tester.pump(frame);
      expect(at.value, 1);
      await tester.pump(frame);
      expect(at.value, 2);
      await tester.pump(frame);
      expect(tester.exportTransport.playing, isFalse);
      expect(at.value, 2);
    });

    testWidgets('🚨the playhead WAITS for a frame that has not landed', (
      tester,
    ) async {
      await pump(tester, document(pages: 3));
      await landed(tester, 0);

      await pressPlay(tester);
      for (var tick = 0; tick < 5; tick += 1) {
        await tester.pump(frame);
      }
      expect(tester.exportTransport.playing, isTrue);
      expect(at.value, 0, reason: 'it walked past a frame that is not there');
      await pressPlay(tester);
      expect(tester.exportTransport.playing, isFalse);
    });

    testWidgets('a step on the transport is reported to the window', (
      tester,
    ) async {
      await pump(tester, document());
      await tester.tap(
        find.byKey(const ValueKey<String>('export-transport-step-forward')),
      );
      await tester.pump();
      expect(at.value, 1);
      expect(tester.exportTransport.currentFrame, 1);
    });

    testWidgets('a book\'s page is turned on its cluster', (tester) async {
      await pump(tester, document(shape: ExportPreviewShape.book, pages: 3));
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preview-next-page-button')),
      );
      await tester.pump();
      expect(at.value, 1);
    });

    testWidgets('while an export runs nothing here turns the picture: the '
        'transport takes no press, and a run under way stops', (tester) async {
      await pump(tester, document(pages: 3));
      for (final page in [1, 0]) {
        await landed(tester, page);
      }
      await pressPlay(tester);
      expect(tester.exportTransport.playing, isTrue);

      await pump(tester, document(pages: 3), enabled: false);
      expect(tester.exportTransport.playing, isFalse);
      expect(tester.exportTransport.onPlayPause, isNull);
      await tester.tap(
        find.byKey(const ValueKey<String>('export-transport-step-forward')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(at.value, 0);

      await pump(
        tester,
        document(shape: ExportPreviewShape.book, pages: 3),
        enabled: false,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('export-preview-next-page-button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(at.value, 0);
    });
  });
}
