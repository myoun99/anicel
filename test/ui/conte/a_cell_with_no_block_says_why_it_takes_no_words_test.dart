import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// 🗣️유저 2026-10-30: 「콘티레이어 없을때 콘티용지의 내용칸쪽 누르면
/// 반응없는데 제대로 콘티레이어 있어야한다는 메시지? 이미 다른데서 같은방식으로
/// 쓰는문장있을텐데 그거 뜨도록」 — a cell with no block has nowhere to keep
/// its words, and the tap says so in the words the pen is refused with.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const drawn = CutId('38');
  const noRow = CutId('39');
  const hollow = CutId('40');

  Project project() => Project(
    id: const ProjectId('no-block'),
    name: 'No block',
    createdAt: DateTime.utc(2026, 10, 30),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: drawn,
            name: '38',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('sb-38'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: [
                  Frame(
                    id: const FrameId('sb-38-0'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('sb-38-0'), length: 10),
                },
              ),
            ],
          ),
          // A cut drawn on its animation row alone.
          Cut(
            id: noRow,
            name: '39',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('anim-39'),
                name: 'A',
                frames: [
                  Frame(
                    id: const FrameId('anim-39-0'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('anim-39-0'), length: 10),
                },
              ),
            ],
          ),
          // A cut whose conte row lost every block.
          Cut(
            id: hollow,
            name: '40',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('sb-40'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// The panel with its brush off, 「프레임 자동 생성」 set to [autoCreates]:
  /// the session and the words of [cut]'s cell, tapped.
  Future<EditorSessionManager> tapWordsOf(
    WidgetTester tester,
    CutId cut, {
    required bool autoCreates,
  }) async {
    final input = AppInput.settings.value;
    AppInput.settings.value = input.copyWith(
      autoCreateFrameOnDraw: autoCreates,
    );
    addTearDown(() => AppInput.settings.value = input);
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConteTabHost(session: session, thumbnails: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = find.byWidgetPredicate(
      (widget) =>
          widget is ConteBookPage && widget.page.kind == ContePageKind.body,
    );
    final cell = tester
        .widget<ConteBookPage>(body.first)
        .page
        .cells
        .singleWhere((cell) => cell.cutId == cut.value);
    await tester.tap(
      find.descendant(
        of: body.first,
        matching: find.byKey(
          ValueKey<String>('conte-action-edit-${cut.value}-${cell.cellIndex}'),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  String wordsOf(EditorSessionManager session) => AppStrings.of(
    session.languageSettings.value.programLanguage,
  ).noticeNoConteLayer;

  for (final autoCreates in [true, false]) {
    testWidgets('🎯a tap on the words of a cut with no conte row says so, and '
        'opens no field — 「프레임 자동 생성」 ${autoCreates ? 'on' : 'off'}', (
      tester,
    ) async {
      final session = await tapWordsOf(
        tester,
        noRow,
        autoCreates: autoCreates,
      );

      expect(cursorNotices.message, wordsOf(session));
      expect(find.byKey(const ValueKey('conte-action-field')), findsNothing);
      expect(
        session.cutById(noRow)!.layers,
        hasLength(1),
        reason: 'a tap makes nothing',
      );
      // The notice goes of itself.
      await tester.pump(CursorNoticeController.defaultDuration);
    });
  }

  testWidgets('a conte row with no block there says what it lacks: a frame', (
    tester,
  ) async {
    final session = await tapWordsOf(tester, hollow, autoCreates: false);

    expect(
      cursorNotices.message,
      AppStrings.of(
        session.languageSettings.value.programLanguage,
      ).noticeNoFrameHere,
    );
    expect(find.byKey(const ValueKey('conte-action-field')), findsNothing);
    await tester.pump(CursorNoticeController.defaultDuration);
  });

  testWidgets('a cell with a block opens its field and says nothing', (
    tester,
  ) async {
    await tapWordsOf(tester, drawn, autoCreates: false);

    expect(cursorNotices.message, isNull);
    expect(find.byKey(const ValueKey('conte-action-field')), findsOneWidget);
  });
}
