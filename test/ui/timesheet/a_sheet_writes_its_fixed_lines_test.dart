import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/sheet_memo_side.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/cut_sheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

/// 🗣️F-542 (유저 2026-11-02): 「콘티용지패널에서 고정텍스트 보여주듯이. 똑같이
/// 법 재사용/통일하면서 타임시트 용지패널에서도 메모란에 표시. 고정텍스트를
/// 위한 공간 만드는거 똑같이. 그리고 고정텍스트 적용/미적용 설정 똑같이 만들어서
/// 법 통일. 그리고 타임시트용지나 콘티용지든 고정텍스트를 카메라 움직임처럼
/// 전체설정이랑 현재컷 설정 두개로 나눔.」 · 「콘티용지패널엔 시간정보가 없어서
/// PAN (6+6) 이렇게 지시명뒤에 시간 써두지만 타임시트엔 안쓰도록. 즉 A-B PAN
/// 이렇게 되도록. 대신 A랑 B 이렇게 처음이랑 끝 대상이 컷 처음/끝에 위치해
/// 있을때만 끝에 괄호로 (全尺)라고 쓰도록」 · F-542-Q1: 「둘 다 동일한 메모고,
/// 고정텍스트는 왼쪽 메모란부터 위에서 공간 쓰다가 부족하면 오른쪽 메모란
/// 위에서부터 쓰기시작」.
void main() {
  const olWord = 'カットO.L';
  const track = TrackId('t');
  const pageFrames = 24;
  final ja = conteWordsIn(AppLanguage.ja);

  CameraPose at(double x) => CameraPose(
    center: CanvasPoint(x: x, y: 0),
    zoom: 1,
    rotationDegrees: 0,
  );

  /// A cut [name] whose conte is a block to each of [cells].
  Cut cutNamed(
    String name, {
    List<int> cells = const [24],
    CutCamera? camera,
    CutMetadata metadata = const CutMetadata(),
  }) {
    final frames = <Frame>[];
    final timeline = <int, TimelineExposure>{};
    var start = 0;
    for (final (index, length) in cells.indexed) {
      final id = FrameId('$name-$index');
      frames.add(Frame(id: id, duration: 1, strokes: const []));
      timeline[start] = TimelineExposure.drawing(id, length: length);
      start += length;
    }
    return Cut(
      id: CutId(name),
      name: name,
      duration: start,
      canvasSize: const CanvasSize(width: 640, height: 360),
      camera: camera ?? CutCamera(),
      metadata: metadata,
      layers: [
        Layer(
          id: LayerId('$name-sb'),
          name: 'SB',
          kind: LayerKind.storyboard,
          frames: frames,
          timeline: timeline,
        ),
        Layer(
          id: LayerId('$name-camera'),
          name: 'Camera',
          kind: LayerKind.camera,
          frames: const [],
          timeline: const {},
        ),
      ],
    );
  }

  /// Cuts 1 (60 frames, in conte blocks of [cells]), 2 and 3 (24 each), 1
  /// 겸용 with 3 and moving on frames 6–16 and 30–40: a fade in on the head
  /// of 1, a fade out on its tail, an O.L from 2 into 3.
  Project project({
    List<int> cells = const [24, 24, 12],
    TimesheetInfo info = TimesheetInfo.empty,
    CutMetadata first = const CutMetadata(),
  }) {
    final bare = Track(
      id: track,
      name: 'Video',
      cuts: [
        cutNamed(
          '1',
          cells: cells,
          metadata: first,
          camera: CutCamera(
            keyframes: {6: at(0), 16: at(40), 30: at(40), 40: at(0)},
          ),
        ),
        cutNamed('2'),
        cutNamed('3'),
      ],
    );
    return Project(
      id: const ProjectId('sheet-lines'),
      name: 'Sheet lines',
      createdAt: DateTime.utc(2026, 11, 2),
      timesheetInfo: info,
      tracks: [
        bare.copyWith(
          transitionLayer: bare.transitionLayer.copyWith(
            instructions: {
              0: const InstructionEvent(instructionId: 'fi', length: 6),
              52: const InstructionEvent(instructionId: 'fo', length: 8),
              78: const InstructionEvent(instructionId: 'ol', length: 12),
            },
          ),
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'g',
            members: [
              for (final name in ['1', '3'])
                LayerLinkMember(
                  trackId: track,
                  cutId: CutId(name),
                  layerId: LayerId('$name-sb'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// What each of [cut]'s [pageCount] pages writes, as the paper writes it.
  List<List<String>> pagesOfCut(Project work, Cut cut, int pageCount) => [
    for (final page in sheetPageFixedLines(
      work,
      cut,
      pages: (
        count: pageCount,
        frames: pageFrames,
        drawnFrames: cut.duration,
      ),
      words: (ol: olWord, wholeCut: ja.wholeCut),
    ))
      page.writtenIn(ja),
  ];

  /// What each of the pages of cut [index] writes.
  List<List<String>> pagesOf(Project work, int index, int pageCount) =>
      pagesOfCut(work, work.tracks.single.cuts[index], pageCount);

  /// A work of one cut of [duration] frames, its camera [camera].
  Project workOf(CutCamera camera, {int duration = 24}) => Project(
    id: const ProjectId('sheet-camera'),
    name: 'Sheet camera',
    createdAt: DateTime.utc(2026, 11, 2),
    tracks: [
      Track(
        id: track,
        name: 'Video',
        cuts: [
          cutNamed('1', cells: [duration], camera: camera),
        ],
      ),
    ],
  );

  group('🎯a page writes what a conte cell of its frames writes', () {
    test('the same lines in the same order, with no time and no FIX: a '
        'sheet\'s rows are its time — and no 겸용, its header\'s (F-558)', () {
      final work = project();
      expect(pagesOf(work, 0, 3), [
        ['カット頭 FI', '7f-17f PAN', '31f-41f PAN'],
        <String>[],
        ['カット尻 FO'],
      ]);
      expect(pagesOf(work, 1, 1), [
        ['c2 × c3 カットO.L'],
      ]);

      final source = buildConteSheetSource(work, olWord: olWord);
      final conte = [
        for (final line in source.cuts.first.cells.first.fixedLines.writtenIn(
          ja,
        ))
          line,
      ];
      expect(conte, contains('カット頭 FI (0+6)'));
      expect(
        conte.where((line) => line.startsWith('7f-17f PAN (')),
        hasLength(1),
        reason: 'the conte keeps its time',
      );
      expect(conte, contains('${ja.linked} c3'), reason: 'the cell keeps it');
    });

    test('its fade on the first page and the last, its 겸용 on none — the '
        'header prints them (F-558) — an O.L on the last of the cut it '
        'leaves', () {
      final work = project();
      final [first, middle, last] = pagesOf(work, 0, 3);
      expect(first.first, 'カット頭 FI');
      expect(last.last, 'カット尻 FO');
      expect(middle.where((line) => line.startsWith('カット')), isEmpty);
      for (final page in [first, middle, last]) {
        expect(page.where((line) => line.startsWith(ja.linked)), isEmpty);
      }
      final [before, leaving] = pagesOf(work, 1, 2);
      expect(before, isEmpty, reason: 'the O.L is not there');
      expect(leaving, ['c2 × c3 カットO.L']);
    });

    test('🎯the camera on the first page alone, however the conte is cut', () {
      expect(
        pagesOf(project(cells: const [60]), 0, 3),
        pagesOf(project(), 0, 3),
      );
      final [first, middle, last] = pagesOf(project(), 0, 3);
      expect(first.where((line) => line.contains('PAN')), hasLength(2));
      expect(middle.where((line) => line.contains('PAN')), isEmpty);
      expect(last.where((line) => line.contains('PAN')), isEmpty);
    });

    test('⚠️Mine: a move that starts on a later page with it', () {
      final work = workOf(
        CutCamera(keyframes: {30: at(0), 40: at(40)}),
        duration: 60,
      );
      expect(pagesOf(work, 0, 3), [
        ['31f-41f PAN'],
        <String>[],
        <String>[],
      ]);
    });

    test('⛔a conte cell keeps what it holds of a move two cells share', () {
      final work = Project(
        id: const ProjectId('sheet-camera'),
        name: 'Sheet camera',
        createdAt: DateTime.utc(2026, 11, 2),
        tracks: [
          Track(
            id: track,
            name: 'Video',
            cuts: [
              cutNamed(
                '1',
                cells: const [30, 30],
                camera: CutCamera(keyframes: {20: at(0), 40: at(40)}),
              ),
            ],
          ),
        ],
      );
      final [first, second] = [
        for (final cell in buildConteSheetSource(work).cuts.single.cells)
          cell.fixedLines.camera.where((line) => line.contains('PAN')),
      ];
      expect(first, ['21f-41f PAN (0+10)']);
      expect(second, ['21f-41f PAN (0+11)']);
    });

    test('a cut on no track writes none', () {
      expect(pagesOfCut(project(), cutNamed('elsewhere'), 1), isEmpty);
    });
  });

  group('🎯(全尺): a move from the cut\'s first frame to its last', () {
    List<String> written(Map<int, CameraPose> keys) =>
        pagesOf(workOf(CutCamera(keyframes: keys)), 0, 1).single;

    test('says so', () {
      expect(written({0: at(0), 23: at(40)}), ['1f-24f PAN (全尺)']);
    });

    test('⛔short of either end does not', () {
      expect(written({1: at(0), 23: at(40)}), ['2f-24f PAN']);
      expect(written({0: at(0), 22: at(40)}), ['1f-23f PAN']);
    });

    test('two moves that meet are not one', () {
      expect(written({0: at(0), 12: at(40), 23: at(0)}), [
        '1f-13f PAN',
        '13f-24f PAN',
      ]);
    });

    test('its keys\' names are what it runs between', () {
      final named = CutCamera.fromTrack(
        TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>(
            keys: {
              0: PropertyKey(CanvasPoint(x: 0, y: 0), name: 'A'),
              23: PropertyKey(CanvasPoint(x: 40, y: 0), name: 'B'),
            },
          ),
        ),
      );
      expect(pagesOf(workOf(named), 0, 1).single, ['A-B PAN (全尺)']);
    });

    test('🎯once, however many pages it crosses', () {
      final work = workOf(
        CutCamera(keyframes: {0: at(0), 59: at(40)}),
        duration: 60,
      );
      expect(pagesOf(work, 0, 3), [
        ['1f-60f PAN (全尺)'],
        <String>[],
        <String>[],
      ]);
    });
  });

  group('🎯written or left out, the whole work\'s and the cut\'s', () {
    final sheetOff = TimesheetInfo.empty.copyWith(sheetFixedText: false);
    final conteOff = TimesheetInfo.empty.copyWith(conteFixedText: false);

    bool sheetWrites(Project work) => pagesOf(work, 0, 3).isNotEmpty;
    bool conteWrites(Project work) => buildConteSheetSource(
      work,
    ).cuts.first.cells.first.fixedLines.writtenIn(ja).isNotEmpty;

    test('the sheet: the cut says where it says, the work everywhere else', () {
      expect(sheetWrites(project()), isTrue);
      expect(sheetWrites(project(info: sheetOff)), isFalse);
      expect(
        sheetWrites(project(first: const CutMetadata(sheetFixedText: false))),
        isFalse,
      );
      expect(
        sheetWrites(
          project(
            info: sheetOff,
            first: const CutMetadata(sheetFixedText: true),
          ),
        ),
        isTrue,
      );
    });

    test('the conte, the same law', () {
      expect(conteWrites(project()), isTrue);
      expect(conteWrites(project(info: conteOff)), isFalse);
      expect(
        conteWrites(project(first: const CutMetadata(conteFixedText: false))),
        isFalse,
      );
      expect(
        conteWrites(
          project(
            info: conteOff,
            first: const CutMetadata(conteFixedText: true),
          ),
        ),
        isTrue,
      );
    });

    test('⛔each paper answers for itself', () {
      expect(conteWrites(project(info: sheetOff)), isTrue);
      expect(sheetWrites(project(info: conteOff)), isTrue);
      expect(
        conteWrites(project(first: const CutMetadata(sheetFixedText: false))),
        isTrue,
      );
      expect(
        sheetWrites(project(first: const CutMetadata(conteFixedText: false))),
        isTrue,
      );
    });
  });

  group('the document holds them by page', () {
    test('asked as its pages stand; none past them', () {
      SheetPages? asked;
      final document = TimesheetDocument.fromCut(
        cut: cutNamed('c', cells: const [200]),
        projectName: 'P',
        fps: 24,
        fixedLinesOfPages: (pages) {
          asked = pages;
          return const [
            ['a'],
            ['b'],
          ];
        },
      );
      expect(asked, (
        count: document.pages.length,
        frames: document.pageFrameCount,
        drawnFrames: document.drawnFrameCount,
      ));
      expect(document.pages, hasLength(2), reason: '⛔전제');
      expect(document.fixedLinesOf(1), ['b']);
      expect(document.fixedLinesOf(2), isEmpty);
      expect(document.fixedLinesOf(-1), isEmpty);
    });

    test('a cut\'s sheet writes them in the sheet\'s language', () {
      final session = EditorSessionManager(initialProject: project());
      addTearDown(session.dispose);
      void writeIn(AppLanguage language) => session.languageSettings.value =
          session.languageSettings.value.copyWith(
            notationLanguage: language,
          );

      List<String> printed() => cutSheetDocument(
        session,
        cut: session.repository.requireProject().tracks.single.cuts.first,
        cutStartFrame: 0,
      ).fixedLinesOf(0);

      writeIn(AppLanguage.ja);
      expect(printed().first, 'カット頭 FI');
      expect(printed().last, 'カット尻 FO');
      writeIn(AppLanguage.ko);
      expect(printed().first, '컷 앞 FI');
    });

    test('and its (全尺)', () {
      final session = EditorSessionManager(
        initialProject: workOf(CutCamera(keyframes: {0: at(0), 23: at(40)})),
      );
      addTearDown(session.dispose);
      session.languageSettings.value = session.languageSettings.value.copyWith(
        notationLanguage: AppLanguage.ko,
      );
      expect(
        cutSheetDocument(
          session,
          cut: session.repository.requireProject().tracks.single.cuts.first,
          cutStartFrame: 0,
        ).fixedLinesOf(0),
        ['1f-24f PAN (컷 전체)'],
      );
    });

    // 🗣️F-558 (유저 2026-11-04): 「고정텍스트 on이든 off이든 연관없음. 항상
    // 보여줌. 위치는 헤더의 컷 번호 아래」.
    test('🎯a cut\'s sheet names its 겸용 cuts for its header, whether it '
        'writes its lines or not', () {
      for (final writes in [true, false]) {
        final session = EditorSessionManager(
          initialProject: project(
            info: TimesheetInfo.empty.copyWith(sheetFixedText: writes),
          ),
        );
        addTearDown(session.dispose);
        TimesheetDocument sheetOf(int index) => cutSheetDocument(
          session,
          cut: session.repository.requireProject().tracks.single.cuts[index],
          cutStartFrame: 0,
        );

        expect(sheetOf(0).fixedLinesOf(0), writes ? isNotEmpty : isEmpty);
        expect(sheetOf(0).linkedCuts, ['3'], reason: 'writes: $writes');
        expect(sheetOf(2).linkedCuts, ['1']);
        expect(sheetOf(1).linkedCuts, isEmpty, reason: 'a cut of its own');
      }
    });
  });

  group('the memo band', () {
    const line = TimesheetDocumentPainter.memoLine;
    const left = SheetMemoSide.left;
    const right = SheetMemoSide.right;

    TimesheetDocumentLayout layoutWith(
      List<List<String>> lines, {
      List<String> notes = const [],
      List<String> rightNotes = const [],
    }) => TimesheetDocumentLayout(
      document: TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('c'),
          name: '1',
          layers: const [],
          duration: 200,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          metadata: CutMetadata(pageNotes: notes, rightPageNotes: rightNotes),
        ),
        projectName: 'P',
        fps: 24,
        fixedLinesOfPages: (_) => lines,
      ),
    );

    /// [count] lines, each its own, from line [from].
    List<String> lines(int count, {int from = 0}) => [
      for (var at = from; at < from + count; at += 1) 'L$at',
    ];

    test('🎯two memos side by side, the band\'s text space halved, each '
        'field its half of the band', () {
      final layout = layoutWith(const [[]]);
      final band = layout.memoBandRect(0);
      final room = TimesheetDocumentPainter.memoTextRect(band);
      final (l, r) = (
        layout.memoSideRect(0, left),
        layout.memoSideRect(0, right),
      );
      expect((l.left, l.top, l.bottom), (room.left, room.top, room.bottom));
      expect((r.right, r.top, r.bottom), (room.right, room.top, room.bottom));
      expect(
        r.left - l.right,
        closeTo(TimesheetDocumentPainter.memoColumnGap, 1e-9),
      );
      expect(l.width, closeTo(r.width, 1e-9));
      expect(layout.memoWordsRect(0, left), l);
      expect(layout.memoWordsRect(0, right), r);
      expect(
        layout.memoEditBox(0, left),
        Rect.fromLTRB(band.left, band.top, band.center.dx, band.bottom),
      );
      expect(
        layout.memoEditBox(0, right),
        Rect.fromLTRB(band.center.dx, band.top, band.right, band.bottom),
      );
    });

    test('🎯the lines run down the left and go on from the top of the '
        'right: 「부족하면 오른쪽 메모란 위에서부터」', () {
      expect(
        layoutWith(const [[]]).memoSideRect(0, left).height ~/ line,
        8,
        reason: '⚠️Mine: seven for the lines, one kept for each memo',
      );
      void flows(int count, List<String> onLeft, List<String> onRight) {
        final layout = layoutWith([lines(count)]);
        expect(layout.fixedLinesOn(0, left), onLeft, reason: '$count left');
        expect(layout.fixedLinesOn(0, right), onRight, reason: '$count right');
      }

      flows(3, lines(3), const []);
      flows(7, lines(7), const []);
      flows(8, lines(7), ['L7']);
      flows(14, lines(7), lines(7, from: 7));
      flows(20, lines(7), lines(7, from: 7));
    });

    test('🎯a memo stands under the lines over it, and its field opens '
        'there: 「고정텍스트를 위한 공간 만드는거 똑같이」', () {
      final layout = layoutWith([lines(9)]);
      for (final (side, count) in [(left, 7), (right, 2)]) {
        final room = layout.memoSideRect(0, side);
        final memo = layout.memoWordsRect(0, side);
        expect(
          memo,
          Rect.fromLTRB(
            room.left,
            room.top + count * line,
            room.right,
            room.bottom,
          ),
        );
        final box = layout.memoEditBox(0, side);
        expect(box.top, memo.top, reason: 'no one types into the lines');
        expect(box.bottom, layout.memoBandRect(0).bottom);
      }
    });

    test('each page by its own lines', () {
      final layout = layoutWith(const [
        ['a'],
        [],
      ]);
      expect(
        layout.memoWordsRect(1, left),
        layout.memoSideRect(1, left),
      );
      expect(
        layout.memoWordsRect(0, left),
        isNot(layout.memoSideRect(0, left)),
      );
    });

    /// What [layout]'s sheet paints inside [rectOf] of its page [page], by
    /// row, top to bottom.
    Future<List<Uint8List>> rowsOf(
      WidgetTester tester,
      TimesheetDocumentLayout layout, {
      int page = 0,
      Rect Function(TimesheetDocumentLayout layout, int page)? rectOf,
    }) async {
      final size = layout.documentSize;
      final width = size.width.ceil();
      final recorder = ui.PictureRecorder();
      TimesheetDocumentPainter(
        words: timesheetWordsIn(AppLanguage.en),
        document: layout.document,
        layout: layout,
        face: const TextStyle(),
      ).paint(ui.Canvas(recorder), size);
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() async {
        final image = await picture.toImage(width, size.height.ceil());
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!;
      }))!;
      picture.dispose();
      final rect =
          rectOf?.call(layout, page) ?? layout.memoBandRect(page);
      return [
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y += 1)
          Uint8List.fromList(
            pixels.buffer.asUint8List(
              (y * width + rect.left.ceil()) * 4,
              (rect.right.floor() - rect.left.ceil()) * 4,
            ),
          ),
      ];
    }

    Rect leftSide(TimesheetDocumentLayout layout, int page) {
      final band = layout.memoBandRect(page);
      return Rect.fromLTRB(band.left, band.top, band.center.dx, band.bottom);
    }

    Rect rightSide(TimesheetDocumentLayout layout, int page) {
      final band = layout.memoBandRect(page);
      return Rect.fromLTRB(band.center.dx, band.top, band.right, band.bottom);
    }

    testWidgets('the lines print in their own page\'s band alone', (
      tester,
    ) async {
      final blank = layoutWith(const []);
      final written = layoutWith(const [
        ['LINE'],
        [],
      ]);
      expect(
        await rowsOf(tester, written),
        isNot(await rowsOf(tester, blank)),
        reason: '⛔CONTROL',
      );
      expect(
        await rowsOf(tester, written, page: 1),
        await rowsOf(tester, blank, page: 1),
      );
    });

    testWidgets('each line stands in a line of its own', (tester) async {
      final one = await rowsOf(tester, layoutWith(const [['LINE']]));
      final two = await rowsOf(tester, layoutWith(const [['LINE', 'LINE']]));
      final layout = layoutWith(const [[]]);
      final top = (layout.memoSideRect(0, left).top -
              layout.memoBandRect(0).top)
          .ceil();
      final height = line.toInt();
      // A line's last row is left out: the fallback font differs by platform,
      // and on Linux (CI, PR #1491) the next line's antialiasing reaches up
      // into it.
      expect(
        two.sublist(top, top + height - 1),
        one.sublist(top, top + height - 1),
      );
      expect(
        two.sublist(top + height, top + 2 * height),
        isNot(one.sublist(top + height, top + 2 * height)),
      );
    });

    testWidgets('🎯each memo prints on its own side, as it prints without the '
        'other: 「둘 다 동일한 메모」', (tester) async {
      final blank = layoutWith(const [[]]);
      final leftAlone = layoutWith(const [[]], notes: const ['MEMO']);
      final rightAlone = layoutWith(const [[]], rightNotes: const ['MEMO']);
      final both = layoutWith(
        const [[]],
        notes: const ['MEMO'],
        rightNotes: const ['MEMO'],
      );

      expect(
        await rowsOf(tester, both, rectOf: leftSide),
        await rowsOf(tester, leftAlone, rectOf: leftSide),
      );
      expect(
        await rowsOf(tester, both, rectOf: rightSide),
        await rowsOf(tester, rightAlone, rectOf: rightSide),
      );
      expect(
        await rowsOf(tester, leftAlone, rectOf: leftSide),
        isNot(await rowsOf(tester, blank, rectOf: leftSide)),
        reason: '⛔CONTROL',
      );
      expect(
        await rowsOf(tester, rightAlone, rectOf: rightSide),
        isNot(await rowsOf(tester, blank, rectOf: rightSide)),
        reason: '⛔CONTROL',
      );
    });

    testWidgets('🎯the lines stand over a memo, which prints under them as it '
        'prints alone', (tester) async {
      const written = [
        ['LINE', 'LINE'],
      ];
      final both = layoutWith(written, notes: const ['MEMO']);
      final linesAlone = layoutWith(written);
      final memoAlone = layoutWith(const [[]], notes: const ['MEMO']);

      Rect overTheMemo(TimesheetDocumentLayout layout, int page) {
        final room = layout.memoSideRect(page, left);
        return Rect.fromLTRB(
          room.left,
          room.top,
          room.right,
          // One row short, as in 'each line stands in a line of its own'.
          layout.memoWordsRect(page, left).top - 1,
        );
      }

      Rect theMemo(TimesheetDocumentLayout layout, int page) =>
          layout.memoWordsRect(page, left);

      expect(
        await rowsOf(tester, both, rectOf: overTheMemo),
        await rowsOf(tester, linesAlone, rectOf: overTheMemo),
      );
      expect(
        (await rowsOf(tester, both, rectOf: theMemo)).take(line.toInt()),
        (await rowsOf(tester, memoAlone, rectOf: theMemo)).take(line.toInt()),
      );
      expect(
        await rowsOf(tester, both, rectOf: theMemo),
        isNot(await rowsOf(tester, linesAlone, rectOf: theMemo)),
        reason: '⛔CONTROL',
      );
    });

    testWidgets('the lines the left has no room for print from the top of the '
        'right', (tester) async {
      expect(
        await rowsOf(tester, layoutWith([lines(8)]), rectOf: rightSide),
        isNot(await rowsOf(tester, layoutWith([lines(7)]), rectOf: rightSide)),
      );
    });

    testWidgets('a long memo keeps to its side, and stops where its room '
        'does', (tester) async {
      final blank = layoutWith(const [[]]);
      final long = 'MEMO ' * 600;
      final wide = layoutWith(const [[]], notes: [long]);
      expect(
        await rowsOf(tester, wide, rectOf: rightSide),
        await rowsOf(tester, blank, rectOf: rightSide),
      );
      expect(
        await rowsOf(tester, wide, rectOf: leftSide),
        isNot(await rowsOf(tester, blank, rectOf: leftSide)),
        reason: '⛔CONTROL',
      );

      final under = layoutWith([lines(7)], notes: [long]);
      final memo = under.memoWordsRect(0, left);
      expect(memo.height ~/ line, 1, reason: 'the line kept for it');
      final foot = (memo.top + line - under.memoBandRect(0).top).ceil();
      expect(
        (await rowsOf(tester, under)).sublist(foot),
        (await rowsOf(tester, layoutWith([lines(7)]))).sublist(foot),
      );
    });

    testWidgets('the lines stop where the two sides do', (tester) async {
      final blank = await rowsOf(tester, layoutWith(const []));
      final layout = layoutWith([lines(20)]);
      final foot =
          (layout.memoSideRect(0, left).top +
                  7 * line -
                  layout.memoBandRect(0).top)
              .toInt();
      expect((await rowsOf(tester, layout)).sublist(foot), blank.sublist(foot));
    });

    testWidgets('a long line is shrunk to its side, as the conte\'s', (
      tester,
    ) async {
      final blank = await rowsOf(tester, layoutWith(const [[]]));
      Future<int> inked(String text) async {
        final rows = await rowsOf(tester, layoutWith([[text]]));
        return [
          for (final (row, pixels) in rows.indexed)
            if (!_sameBytes(pixels, blank[row])) row,
        ].length;
      }

      final long = 'LINE ' * 60;
      expect(await inked(long), lessThan(await inked('LINE')));
      expect(
        await rowsOf(tester, layoutWith([[long]]), rectOf: rightSide),
        await rowsOf(tester, layoutWith(const [[]]), rectOf: rightSide),
        reason: 'it stays on its side',
      );
    });
  });
}

bool _sameBytes(Uint8List a, Uint8List b) {
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
