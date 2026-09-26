import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// The sheet culls to what the panel can actually show. The contract is
/// not "fewer draw calls" — it is that culling may only ever drop work
/// the clip would have thrown away anyway, so:
///
/// > **The same pixels, with culling on and off.**
///
/// Asserting that on the RENDERED BYTES is the only oracle worth having
/// here. A test about row indices would pass while the arithmetic was a
/// row out at the edges, which is exactly the bug this could have.
///
/// The finding behind it: OpenToonz keeps no offscreen cache for its
/// xsheet grid at all — it turns the damage rect into a cell index range
/// and iterates only those. So a sheet grid is not expensive; ours only
/// looked expensive because it drew a whole B4 document to fill a dock a
/// few hundred pixels tall.
Future<ByteData> _render(
  TimesheetDocumentPainter painter,
  Size size, {
  required bool culling,
}) async {
  TimesheetDocumentPainter.debugDisableCulling = !culling;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  final bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

int _differingBytes(ByteData a, ByteData b) {
  final x = a.buffer.asUint8List();
  final y = b.buffer.asUint8List();
  if (x.length != y.length) {
    return -1;
  }
  var differing = 0;
  for (var i = 0; i < x.length; i += 1) {
    if (x[i] != y[i]) {
      differing += 1;
    }
  }
  return differing;
}

void main() {
  tearDown(() => TimesheetDocumentPainter.debugDisableCulling = false);

  // A long sheet with real content in it: 240 frames of exposure across
  // several columns, so the row loops have something to skip.
  Layer animationLayer(String id) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: <Frame>[
      Frame(id: FrameId('$id-f1'), duration: 1, strokes: const []),
    ],
    timeline: <int, TimelineExposure>{
      for (var frame = 0; frame < 240; frame += 6)
        frame: TimelineExposure.drawing(FrameId('$id-f1'), length: 6),
    },
  );

  // 🗣️F-78 (유저 2026-09-11): 「타임시트의 se행. se블록의 이름란이 뷰포트에서
  // 안보이면 대사 텍스트가 사라짐」. Every kind whose START writes across its
  // whole span rides the sheet too: an SE entry (its name and dialogue), a
  // hold chain (its word) and a repeat chain (its word) — each running the
  // length of the cut, so the probes below land on rows whose start is
  // culled.
  Layer chainedFromTheEnd(String id, TimelineRunEdgeMode mode) =>
      rederiveRunBehaviors(
        Layer(
          id: LayerId(id),
          name: id.toUpperCase(),
          frames: <Frame>[
            Frame(id: FrameId('$id-f1'), duration: 1, strokes: const []),
          ],
          timeline: <int, TimelineExposure>{
            0: TimelineExposure.drawing(
              FrameId('$id-f1'),
              length: 2,
              endEdge: TimelineRunEdgeMark(mode: mode),
            ),
          },
        ),
        cutFrameCount: 240,
      );
  Layer seEntry(String dialogue) => Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: <Frame>[
      Frame(
        id: const FrameId('se-f1'),
        duration: 1,
        name: dialogue,
        seName: 'SE',
        strokes: const [],
      ),
    ],
    timeline: <int, TimelineExposure>{
      0: const TimelineExposure.drawing(FrameId('se-f1'), length: 240),
    },
  );

  TimesheetDocument sheetWith(Layer se) => TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: '1',
      duration: 240,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: <Layer>[
        animationLayer('a'),
        animationLayer('b'),
        animationLayer('c'),
        chainedFromTheEnd('h', TimelineRunEdgeMode.hold),
        chainedFromTheEnd('r', TimelineRunEdgeMode.repeat),
      ],
    ),
    projectName: 'P',
    fps: 24,
    trackSeLayers: [se],
  );

  final document = sheetWith(
    seEntry('あいうえおかきくけこさしすせそたちつてとなにぬねの'),
  );

  TimesheetDocumentPainter painterAt(CanvasViewport viewport) =>
      TimesheetDocumentPainter(
        words: timesheetWordsIn(AppLanguage.en),
        face: const TextStyle(),
        document: document,
        layout: TimesheetDocumentLayout(document: document, continuous: true),
        viewport: viewport,
      );

  for (final probe in <(String, CanvasViewport)>[
    ('the top of a long sheet', CanvasViewport()),
    (
      'scrolled deep into it',
      CanvasViewport(panX: -40, panY: -4200, zoom: 1),
    ),
    ('zoomed in', CanvasViewport(panX: -120, panY: -900, zoom: 2.5)),
    (
      'zoomed out past the text threshold',
      CanvasViewport(panX: 0, panY: 0, zoom: 0.3),
    ),
    (
      'a fractional pan, so the row boundary lands mid-pixel',
      CanvasViewport(panX: -13.37, panY: -1111.9, zoom: 1.15),
    ),
  ]) {
    final (name, viewport) = probe;
    testWidgets('culling changes no pixel — $name', (tester) async {
      const size = Size(360, 520);
      late ByteData culled;
      late ByteData whole;
      await tester.runAsync(() async {
        culled = await _render(painterAt(viewport), size, culling: true);
        whole = await _render(painterAt(viewport), size, culling: false);
      });
      expect(
        _differingBytes(culled, whole),
        0,
        reason:
            'culling may only drop what the clip discards; anything else '
            'is a row of the sheet that stopped being drawn',
      );
    });
  }

  // F-78: each span-writing kind, its column in view and its START row
  // just above the view's top (row 5: past the one row of slack), so the
  // rows in view are the ones its start writes down.
  final layout = TimesheetDocumentLayout(document: document, continuous: true);
  for (final (name, which, page, topRow)
      in <(String, bool Function(TimesheetColumn), int, int)>[
        (
          'an SE entry — its name and dialogue',
          (column) => column.kind == TimesheetColumnKind.se,
          0,
          5,
        ),
        // HOLD stacks down rows 1-4 from its start at row 1, and a word's
        // rows read as EMPTY cells: from row 3 its tail is in view while
        // the walk has to step over those empty rows to reach the start.
        ('a hold chain — its word', (column) => column.label == 'H', 0, 3),
        ('a repeat chain — its word', (column) => column.label == 'R', 0, 5),
        // The span runs on into the next page, where its start is not: the
        // walk-back stops at that page's top.
        (
          'an SE entry on the page it runs on into',
          (column) => column.kind == TimesheetColumnKind.se,
          1,
          5,
        ),
      ]) {
    testWidgets('culling changes no pixel — $name, its start row scrolled '
        'off the top', (tester) async {
      final column = document.columns.indexWhere(which);
      expect(column, isNonNegative, reason: 'fixture: the column is there');
      final left =
          layout.halfLeft(page, 0) + layout.columnLeftInHalf(column);
      final top =
          layout.halfRowsTop(page) +
          topRow * TimesheetDocumentLayout.rowHeight;
      final viewport = CanvasViewport(panX: 40 - left, panY: -top, zoom: 1);
      const size = Size(360, 520);
      late ByteData culled;
      late ByteData whole;
      await tester.runAsync(() async {
        culled = await _render(painterAt(viewport), size, culling: true);
        whole = await _render(painterAt(viewport), size, culling: false);
      });
      expect(
        _differingBytes(culled, whole),
        0,
        reason:
            'a start cell writes down its whole span; culling its row may '
            'not take that writing with it',
      );
    });
  }

  // 🗣️F-165 (유저 2026-09-18): 「왼쪽영역에서 시작한 블록이면 대사가 다 왼쪽
  // 시작한곳의 영역에 몰아서 써져있음. 오른쪽 영역에 나눠서 들어가야」. On the
  // PRINTED page, where the halves sit side by side, the words are laid over
  // the WHOLE span and each half writes the ones that land on its rows.
  //
  // ↩️These pins said the opposite on 09-11 — 「the half a span runs on
  // into keeps NONE of its writing」 — set to kill a mutant of F-78's culling
  // walk, not as a decision about the page. F-165 is that decision.
  //
  // Judged against a dialogue-less entry of the same span: the test font
  // draws every glyph as the same box, so what tells words from none is
  // only whether a box is there.
  final silent = sheetWith(seEntry(''));
  final seColumn = document.columns.indexWhere(
    (column) => column.kind == TimesheetColumnKind.se,
  );
  final printed = TimesheetDocumentLayout(document: document);
  TimesheetDocumentPainter printedAt(
    TimesheetDocument sheet,
    CanvasViewport viewport,
  ) => TimesheetDocumentPainter(
    words: timesheetWordsIn(AppLanguage.en),
    face: const TextStyle(),
    document: sheet,
    layout: TimesheetDocumentLayout(document: sheet),
    viewport: viewport,
  );

  testWidgets('the half an SE entry runs on into writes its share of the '
      'words — and culling keeps it', (tester) async {
    final left = printed.halfLeft(0, 1) + printed.columnLeftInHalf(seColumn);
    final top =
        printed.halfRowsTop(0) + 5 * TimesheetDocumentLayout.rowHeight;
    final viewport = CanvasViewport(panX: 40 - left, panY: -top, zoom: 1);
    const size = Size(360, 520);
    late ByteData words;
    late ByteData none;
    late ByteData whole;
    await tester.runAsync(() async {
      words = await _render(printedAt(document, viewport), size, culling: true);
      none = await _render(printedAt(silent, viewport), size, culling: true);
      whole = await _render(
        printedAt(document, viewport),
        size,
        culling: false,
      );
    });
    expect(
      _differingBytes(words, none),
      greaterThan(0),
      reason: 'the rows the entry runs on into carry its words',
    );
    expect(
      _differingBytes(words, whole),
      0,
      reason: 'culling may not take the share away: the walk reaches the '
          'half\'s top, where the entry comes in',
    );
  });

  testWidgets('…and writes nothing above its first row — the column '
      'header over the half stays as it was', (tester) async {
    final rowsTop = printed.halfRowsTop(0);
    final left = printed.halfLeft(0, 1) + printed.columnLeftInHalf(seColumn);
    final viewport = CanvasViewport(
      panX: 40 - left,
      panY: -(rowsTop - 60),
      zoom: 1,
    );
    const size = Size(360, 200);
    late ByteData words;
    late ByteData none;
    await tester.runAsync(() async {
      words = await _render(printedAt(document, viewport), size, culling: true);
      none = await _render(printedAt(silent, viewport), size, culling: true);
    });
    final a = words.buffer.asUint8List();
    final b = none.buffer.asUint8List();
    final width = size.width.toInt();
    var above = 0;
    // The band right over the half's first row line (two pixels of slack).
    for (var y = 60 - 16; y < 60 - 2; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final i = (y * width + x) * 4;
        if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
          above += 1;
        }
      }
    }
    expect(
      _differingBytes(words, none),
      greaterThan(0),
      reason: 'fixture: the half\'s first rows carry words',
    );
    expect(above, 0, reason: 'the words start on the half\'s own rows');
  });

  testWidgets('the half an SE entry starts in writes only its own rows — '
      'nothing spills past the half\'s last row', (tester) async {
    final rowsBottom =
        printed.halfRowsTop(0) +
        printed.halfStrips.first.rowCount * TimesheetDocumentLayout.rowHeight;
    final left = printed.halfLeft(0, 0) + printed.columnLeftInHalf(seColumn);
    // The half's last rows at the top of the view, what lies under it below.
    final viewport = CanvasViewport(
      panX: 40 - left,
      panY: -(rowsBottom - 60),
      zoom: 1,
    );
    const size = Size(360, 520);
    late ByteData words;
    late ByteData none;
    await tester.runAsync(() async {
      words = await _render(printedAt(document, viewport), size, culling: true);
      none = await _render(printedAt(silent, viewport), size, culling: true);
    });
    final a = words.buffer.asUint8List();
    final b = none.buffer.asUint8List();
    final width = size.width.toInt();
    var spilled = 0;
    // The band right under the half's last row line (two pixels of slack):
    // a glyph written past the half would reach into it. Further down is
    // the next page, whose own share of the words is meant to be there.
    for (var y = 62; y < 62 + 16; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final i = (y * width + x) * 4;
        if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
          spilled += 1;
        }
      }
    }
    expect(
      _differingBytes(words, none),
      greaterThan(0),
      reason: 'fixture: the start half\'s last rows carry words',
    );
    expect(spilled, 0, reason: 'the words below the half belong to the next');
  });

  testWidgets('each half writes its SHARE of the words, not all of them — '
      'the start half used to take every one', (tester) async {
    const glyphCount = 25; // 'あいう…の' above
    final strip = printed.halfStrips.first;
    final halfHeight = strip.rowCount * TimesheetDocumentLayout.rowHeight;
    final size = Size(120, halfHeight + 40);

    /// The glyph boxes down the SE column's centre line in [half] of page 0:
    /// the test font draws each glyph as a solid box, the column has no
    /// interior rules, and the red bars are red — so a dark run is a glyph.
    Future<int> glyphsIn(int half) async {
      final left =
          printed.halfLeft(0, half) + printed.columnLeftInHalf(seColumn);
      final width = printed.columnWidthFor(TimesheetColumnKind.se);
      final top = printed.halfRowsTop(0);
      final viewport = CanvasViewport(
        panX: 40 - left,
        panY: -(top - 20),
        zoom: 1,
      );
      late ByteData bytes;
      await tester.runAsync(() async {
        bytes = await _render(printedAt(document, viewport), size, culling: true);
      });
      final rgba = bytes.buffer.asUint8List();
      final x = (40 + width / 2).round();
      var runs = 0;
      var inRun = false;
      // Below the name box, down to the half's last row.
      for (var y = 20 + 18; y < 20 + halfHeight.toInt(); y += 1) {
        final i = (y * size.width.toInt() + x) * 4;
        final dark = rgba[i] < 100 && rgba[i + 1] < 100 && rgba[i + 2] < 100;
        if (dark && !inRun) {
          runs += 1;
        }
        inRun = dark;
      }
      return runs;
    }

    final first = await glyphsIn(0);
    final next = await glyphsIn(1);
    expect(first, greaterThan(0), reason: 'the start half writes its share');
    expect(next, greaterThan(0), reason: 'and so does the half after it');
    expect(
      first,
      lessThan(glyphCount),
      reason: 'the entry runs on for three more halves: the start half '
          'cannot be holding every word',
    );
  });
}
