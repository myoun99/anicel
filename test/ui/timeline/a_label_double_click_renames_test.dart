import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🚨I-48 (유저 2026-09-26): 「레이어 라벨 더블클릭시 해당 레이어 이름변경
/// 로직 발동. 버튼이랑 마찬가지로 여러레이어 선택한채로 해당 레이어
/// 발동했을때 선택범위 안이면 다른레이어도 변경, 아니면 해당레이어만. … 동작
/// 발동은 프레임블록이랑 똑같이 … 해당 레이어 안에서 두번의 클릭이
/// 이루어지면. 시간간격같은거 프레임블록 로직 그대로 재사용/법통일, 이런
/// 더블클릭 로직은 공용화할것」.
void main() {
  const a = LayerId('layer-a');
  const b = LayerId('layer-b');
  const c = LayerId('layer-c');

  setUp(TimelineDoubleTapGate.reset);

  group('the gate — the cells\' one, a row as the target', () {
    test('two presses on one row\'s label fire what the first one armed', () {
      final fired = <LayerId>[];
      VoidCallback arm(LayerId pressed) => () => fired.add(pressed);

      timelineLabelDoubleTapRecord(a, arm)(Offset.zero);
      timelineLabelDoubleTapActivation(b)(TapDownDetails());
      expect(fired, isEmpty, reason: 'two rows are two labels');

      timelineLabelDoubleTapRecord(a, arm)(Offset.zero);
      timelineLabelDoubleTapActivation(a)(TapDownDetails());
      expect(fired, [a]);
    });

    test('what fires is what the FIRST press read — the selection the '
        'first click then clears is still the one it acts on', () {
      var selection = 'A and B';
      final fired = <String>[];
      VoidCallback arm(LayerId pressed) {
        final seen = selection;
        return () => fired.add(seen);
      }

      timelineLabelDoubleTapRecord(a, arm)(Offset.zero);
      selection = 'nothing';
      timelineLabelDoubleTapActivation(a)(TapDownDetails());

      expect(fired, ['A and B']);
    });

    test('a cell pressed between is another target', () {
      var fired = 0;
      timelineLabelDoubleTapRecord(a, (_) => () => fired += 1)(Offset.zero);
      timelineCellDoubleTapRecord(
        layerId: a,
        cells: (
          frameAt: (_) => 0,
          axis: Axis.horizontal,
          cellExtent: () => 10.0,
        ),
      )(Offset.zero);
      timelineLabelDoubleTapActivation(a)(TapDownDetails());

      expect(fired, 0);
    });
  });

  for (final orientation in TimelineOrientation.values) {
    final prefix = orientation == TimelineOrientation.vertical
        ? 'xsheet'
        : 'timeline';
    group('$prefix: the label\'s double click', () {
      late List<LayerId> fired;
      late List<LayerId> eyes;

      Future<void> pumpPanel(WidgetTester tester) async {
        fired = [];
        eyes = [];
        await tester.binding.setSurfaceSize(const Size(1400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cursor = ValueNotifier<int>(0);
        addTearDown(cursor.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TimelinePanel(
                layers: [_drawing(a, 'A'), _drawing(b, 'B')],
                activeLayerId: a,
                frameCursor: cursor,
                playbackFrameCount: 12,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.uncovered,
                onSelectLayer: (_) {},
                labelDoubleClick: (pressed) => () => fired.add(pressed),
                onSelectFrame: (_) {},
                onAddLayer: () {},
                onToggleLayerVisibility: eyes.add,
                onLayerOpacityChanged: (_, _) {},
                onToggleLayerTimesheet: (_) {},
                onLayerMarkSelected: (_, _) {},
                orientation: orientation,
                onOrientationChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Offset label(WidgetTester tester, LayerId id) => tester.getCenter(
        find.byKey(ValueKey<String>('$prefix-layer-name-${id.value}')),
      );
      Offset eye(WidgetTester tester, LayerId id) => tester.getCenter(
        find.byKey(ValueKey<String>('$prefix-layer-visibility-${id.value}')),
      );

      Future<void> twoPresses(
        WidgetTester tester,
        Offset first,
        Offset second, {
        Duration between = const Duration(milliseconds: 60),
      }) async {
        await tester.tapAt(first, kind: PointerDeviceKind.stylus);
        await tester.pump(between);
        await tester.tapAt(second, kind: PointerDeviceKind.stylus);
        await tester.pump(const Duration(milliseconds: 700));
      }

      testWidgets('two presses on one label fire it', (tester) async {
        await pumpPanel(tester);

        await twoPresses(tester, label(tester, a), label(tester, a));

        expect(fired, [a]);
      });

      testWidgets('anywhere on the label is the label — a press on the '
          'name\'s letters and one on the empty ground past them are one '
          'row', (tester) async {
        await pumpPanel(tester);
        // The name is written from the area's start — along a row, or
        // stood up down a column.
        final name = tester.getRect(
          find.byKey(ValueKey<String>('$prefix-layer-name-${a.value}')),
        );
        final letters = orientation == TimelineOrientation.vertical
            ? Offset(name.center.dx, name.top + 3)
            : Offset(name.left + 3, name.center.dy);
        final ground = label(tester, a);
        expect(
          (ground - letters).distance,
          greaterThan(4),
          reason: 'CONTROL: two different points',
        );

        await twoPresses(tester, letters, ground);

        expect(fired, [a]);
      });

      testWidgets('two labels are two presses', (tester) async {
        await pumpPanel(tester);

        await twoPresses(tester, label(tester, a), label(tester, b));

        expect(fired, isEmpty);
      });

      testWidgets('outside the window it is two clicks', (tester) async {
        await pumpPanel(tester);

        await twoPresses(
          tester,
          label(tester, a),
          label(tester, a),
          between: const Duration(milliseconds: 700),
        );

        expect(fired, isEmpty);
      });

      testWidgets('a double press on a BUTTON is the button\'s — twice — '
          'and no rename', (tester) async {
        await pumpPanel(tester);

        await twoPresses(tester, eye(tester, a), eye(tester, a));

        expect(eyes, [a, a], reason: 'CONTROL: the eye took both presses');
        expect(fired, isEmpty);
      });

      testWidgets('a label clicked once, then its eye twice, is no rename — '
          'the eye\'s presses are no part of it', (tester) async {
        await pumpPanel(tester);

        await tester.tapAt(label(tester, a), kind: PointerDeviceKind.stylus);
        await tester.pump(const Duration(milliseconds: 60));
        await twoPresses(tester, eye(tester, a), eye(tester, a));

        expect(eyes, [a, a]);
        expect(fired, isEmpty);
      });

      testWidgets('an eye pressed between two label presses breaks them', (
        tester,
      ) async {
        await pumpPanel(tester);

        await tester.tapAt(label(tester, a), kind: PointerDeviceKind.stylus);
        await tester.pump(const Duration(milliseconds: 60));
        await twoPresses(tester, eye(tester, a), label(tester, a));

        expect(eyes, [a]);
        expect(fired, isEmpty);
      });
    });
  }

  group('the rename it opens — on the rows the first press acted on', () {
    late ProjectRepository repository;
    late EditorSessionManager session;

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: _project(),
            onRepositoryCreated: (repo) => repository = repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
    }

    Future<void> select(WidgetTester tester, List<LayerId> ids) async {
      session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(ids.first));
      session.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];
      await tester.pumpAndSettle();
    }

    Future<void> doubleClick(WidgetTester tester, LayerId id) async {
      final at = tester.getCenter(
        find.byKey(ValueKey<String>('timeline-layer-name-${id.value}')),
      );
      await tester.tapAt(at, kind: PointerDeviceKind.stylus);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at, kind: PointerDeviceKind.stylus);
      await tester.pumpAndSettle();
    }

    String seeded(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(_textField))
        .controller!
        .text;

    Future<void> answer(WidgetTester tester, String name) async {
      await tester.enterText(find.byKey(_textField), name);
      await tester.tap(find.byKey(_okButton));
      await tester.pumpAndSettle();
    }

    String nameOf(LayerId id) => repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .singleWhere((layer) => layer.id == id)
        .name;

    testWidgets('inside the selection: every selected row, one undo', (
      tester,
    ) async {
      await pumpHome(tester);
      await select(tester, [a, b]);

      await doubleClick(tester, b);

      expect(seeded(tester), '', reason: 'several rows share no one name');
      await answer(tester, 'X');
      expect([nameOf(a), nameOf(b), nameOf(c)], ['X', 'X', 'C']);

      session.undo();
      await tester.pumpAndSettle();
      expect([nameOf(a), nameOf(b)], ['A', 'B'], reason: 'one step');
    });

    testWidgets('outside the selection: that row alone', (tester) async {
      await pumpHome(tester);
      await select(tester, [a, b]);

      await doubleClick(tester, c);

      expect(seeded(tester), 'C');
      await answer(tester, 'Y');
      expect([nameOf(a), nameOf(b), nameOf(c)], ['A', 'B', 'Y']);
    });

    testWidgets('no selection at all: that row', (tester) async {
      await pumpHome(tester);

      await doubleClick(tester, a);

      expect(seeded(tester), 'A');
      await answer(tester, 'Z');
      expect([nameOf(a), nameOf(b), nameOf(c)], ['Z', 'B', 'C']);
    });
  });
}

const _textField = ValueKey<String>('rename-layer-text-field');
const _okButton = ValueKey<String>('rename-layer-ok-button');


Layer _drawing(LayerId id, String name) => Layer(
  id: id,
  name: name,
  kind: LayerKind.animation,
  frames: [Frame(id: FrameId('$name-cel'), duration: 1, strokes: const [])],
  timeline: const {},
);

Project _project() => Project(
  id: const ProjectId('label-double-click'),
  name: 'Label double click',
  createdAt: DateTime.utc(2026, 9, 26),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Track',
      cuts: [
        Cut(
          id: const CutId('cut'),
          name: 'Cut',
          duration: 1,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          layers: [
            _drawing(const LayerId('layer-a'), 'A'),
            _drawing(const LayerId('layer-b'), 'B'),
            _drawing(const LayerId('layer-c'), 'C'),
          ],
        ),
      ],
    ),
  ],
);
