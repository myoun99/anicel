import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show offsetAlong, partAcross, partAlong;
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-556 (유저 2026-11-04): 「프레임영역. 빈공간에서 시작한 선택범위는
/// 블록에 닿아도 잘라내기 동작등이 작동안됨. 순서를 반대로해서 블록에서
/// 시작해서 빈공간까지 선택범위하면 잘라내기 잘 동작하는데. 뭘 어떻게
/// 선택하든 선택범위로 선택하면 동작하도록 하는게 규칙이니 해결」.
///
/// ★The band is what is selected, wherever the hand began it: every button
/// of the shared pill answers the same over the same band, and does the same.
const _a = LayerId('sweep-a');
const _b = LayerId('sweep-b');

/// A sweep: from the cell [from] names to the one [to] names, by mouse.
typedef _Sweep = ({(LayerId, int) from, (LayerId, int) to});

/// Every button of the shared pill, as it reads.
typedef _Pill = ({
  bool cut,
  bool copy,
  bool pasteIndependent,
  bool pasteLinked,
  PillSubject delete,
  bool unlink,
  bool duplicate,
  PillSubject merge,
  bool autoName,
});

/// A row holding one three-frame drawing named [name] from [at].
Layer _row(LayerId id, {required int at, required String name}) => Layer(
  id: id,
  name: id.value,
  frames: [
    Frame(
      id: FrameId('${id.value}-cel'),
      duration: 3,
      name: name,
      strokes: const [],
    ),
  ],
  timeline: {
    at: TimelineExposure.drawing(FrameId('${id.value}-cel'), length: 3),
  },
);

/// A: empty 0..2, its drawing 3..5. B: empty 0..5, its drawing 6..8.
Project _project() => Project(
  id: const ProjectId('sweep'),
  name: 'Sweep',
  createdAt: DateTime.utc(2026, 11, 4),
  tracks: [
    Track(
      id: const TrackId('sweep-track'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('sweep-cut'),
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 32, height: 32),
          layers: [_row(_a, at: 3, name: '1'), _row(_b, at: 6, name: '2')],
        ),
      ],
    ),
  ],
);

void main() {
  const cell = TimelineZoomLimits.referencePixelsPerFrame;

  /// The ways one band is swept: begun on the empty cells and begun on the
  /// drawing, along one row and across two.
  final ways = <String, (_Sweep, _Sweep)>{
    'along a row': (
      (from: (_a, 0), to: (_a, 4)),
      (from: (_a, 4), to: (_a, 0)),
    ),
    'across two rows': (
      (from: (_a, 7), to: (_b, 7)),
      (from: (_b, 7), to: (_a, 7)),
    ),
  };

  for (final vertical in [false, true]) {
    final where = vertical ? 'the X-sheet' : 'the timeline';
    final axis = vertical ? Axis.vertical : Axis.horizontal;

    Future<EditorSessionManager> open(WidgetTester tester) async {
      final session = await pumpTimelineHost(
        tester,
        _project(),
        // Tall enough that the X-sheet shows every frame of the cut.
        surface: const Size(1200, 1000),
      );
      if (vertical) {
        await tester.tap(
          find.byKey(
            const ValueKey<String>('timeline-orientation-toggle-button'),
          ),
        );
        await tester.pumpAndSettle();
      }
      return session;
    }

    Future<void> sweep(WidgetTester tester, _Sweep how) async {
      Finder cells(LayerId row) => find.named(
        vertical ? 'xsheet-column-$row-cells' : 'timeline-row-$row-cells',
      );
      Offset at((LayerId, int) place) {
        final (row, frame) = place;
        return offsetAlong(
          axis,
          along:
              partAlong(axis, tester.getTopLeft(cells(row))) +
              cell * frame +
              cell / 2,
          across: partAcross(axis, tester.getCenter(cells(row))),
        );
      }

      final finger = await tester.startGesture(
        at(how.from),
        kind: PointerDeviceKind.mouse,
      );
      final step = how.to.$2 >= how.from.$2 ? cell : -cell;
      await finger.moveBy(offsetAlong(axis, along: step, across: 0));
      await tester.pump();
      await finger.moveTo(at(how.to));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();
    }

    /// Every button of the shared pill, as it reads over the band.
    _Pill pill(EditorSessionManager session) {
      final panel = TimelineToolbarPanelContext(session);
      return (
        cut: panel.canCutRun,
        copy: panel.canCopyFrame,
        pasteIndependent: panel.canPasteIndependentFrame,
        pasteLinked: panel.canPasteLinkedFrame,
        delete: panel.deleteSubject,
        unlink: panel.canUnlink,
        duplicate: panel.canDuplicate,
        merge: panel.mergeSubject,
        autoName: panel.canAutoName,
      );
    }

    /// The band, and what each row holds — written out, so two are compared
    /// by what they say.
    String state(EditorSessionManager session) {
      final band = session.frameRangeSelection.value;
      return '${(
        band: band == null
            ? null
            : (band.startIndex, band.endIndexExclusive, band.spanLayerIds),
        rows: [
          for (final row in session.requireActiveCut.layers)
            row.timeline.map((at, block) => MapEntry(at, block.frameId)),
        ],
      )}';
    }

    /// What each row holds, by the drawings' names and lengths — a paste's
    /// new drawings are minted ids of their own each time.
    String sheet(EditorSessionManager session) => [
      for (final row in session.requireActiveCut.layers)
        {
          for (final MapEntry(key: at, value: block) in row.timeline.entries)
            at: (row.frameById(block.frameId!)?.name, block.length),
        },
    ].toString();

    for (final MapEntry(key: how, value: (fromEmpty, fromDrawing))
        in ways.entries) {
      testWidgets('$where, $how: the pill answers a band begun on the empty '
          'cells as it answers one begun on the drawing', (tester) async {
        final session = await open(tester);
        await sweep(tester, fromDrawing);
        final band = state(session);
        expect(
          session.frameRangeSelection.value,
          isNotNull,
          reason: '⛔전제: the sweep drew a band',
        );
        final lit = pill(session);
        expect(
          lit.cut,
          isTrue,
          reason: '⛔전제: begun on the drawing, the cut is lit',
        );

        session.frameRangeSelection.value = null;
        await tester.pumpAndSettle();
        await sweep(tester, fromEmpty);

        expect(state(session), band, reason: 'the same band');
        expect(pill(session), lit, reason: '「뭘 어떻게 선택하든」');
      });

      for (final verb in ['cut', 'copy']) {
        testWidgets('$where, $how: a $verb of a band begun on the empty '
            'cells does what one begun on the drawing does', (tester) async {
          Future<({String state, String banked, String board})> after(
            _Sweep sweptSo,
          ) async {
            final session = await open(tester);
            await sweep(tester, sweptSo);
            final panel = TimelineToolbarPanelContext(session);
            verb == 'cut' ? panel.cutRun() : panel.copyFrame();
            await tester.pumpAndSettle();
            final result = (
              state: state(session),
              banked: ([
                for (final row in session.clipboard.bankedRowLayerIds)
                  row.value,
              ]..sort()).join(', '),
              board: session.clipboard.copiedFrameStatusText,
            );
            await tester.pumpWidget(const SizedBox());
            return result;
          }

          final fromTheDrawing = await after(fromDrawing);
          expect(
            fromTheDrawing.banked,
            isNotEmpty,
            reason: '⛔전제: begun on the drawing, the $verb banks the band',
          );
          final fromTheEmpty = await after(fromEmpty);
          expect(
            (fromTheEmpty.state, fromTheEmpty.banked, fromTheEmpty.board),
            (fromTheDrawing.state, fromTheDrawing.banked, fromTheDrawing.board),
          );
        });
      }

      // 결정 14 ②ⓐ×③ⓐ: the board pairs its rows with the band a paste
      // lands on, in order — so the copy's order is the band's, not the
      // order the hand happened to begin in.
      testWidgets('$where, $how: a band copied from either end pastes the '
          'same rows onto the same rows', (tester) async {
        Future<String> after(_Sweep copied) async {
          final session = await open(tester);
          await sweep(tester, copied);
          TimelineToolbarPanelContext(session).copyFrame();
          session.frameRangeSelection.value = null;
          await tester.pumpAndSettle();
          // Another band to paste on, both rows from frame 9, swept the
          // same way both times.
          await sweep(tester, (from: (_a, 9), to: (_b, 10)));
          expect(
            session.frameRangeSelection.value?.startIndex,
            9,
            reason: '⛔전제: a band to paste on',
          );
          TimelineToolbarPanelContext(session).pasteIndependentFrame();
          await tester.pumpAndSettle();
          final rows = [
            for (final row in session.requireActiveCut.layers)
              {
                for (final MapEntry(key: at, value: block)
                    in row.timeline.entries)
                  if (at >= 9) at: block.length,
              },
          ];
          await tester.pumpWidget(const SizedBox());
          return '$rows';
        }

        expect(await after(fromEmpty), await after(fromDrawing));
      });
    }

    // ★Every row the band holds, from either end — and a SYNCED attach row
    // among them (F-545: it makes no cel, and takes pictures in the blocks
    // it shows), with a board banked so the pastes have something to say.
    for (final synced in [false, true]) {
      final family = synced ? 'a synced row and a cel row' : 'two cel rows';
      for (final board in ['one stood cel', 'a band of every row']) {
        testWidgets('$where, $family, $board banked: the pastes answer a '
            'band from either end alike, and do the same', (tester) async {
          /// The rows the band runs across — [_b] and the one under it.
          Future<(EditorSessionManager, LayerId)> setUp() async {
            final session = await open(tester);
            var under = _a;
            if (synced) {
              session.selectLayer(_a);
              session.folders.addAttachedLayer(AttachedPlacement.above);
              under = session.activeLayerId!;
              await tester.pumpAndSettle();
            }
            if (board == 'one stood cel') {
              session.selectLayer(_b);
              session.selectFrameIndex(7);
            } else {
              await sweep(tester, (from: (_a, 4), to: (_b, 7)));
            }
            TimelineToolbarPanelContext(session).copyFrame();
            session.frameRangeSelection.value = null;
            await tester.pumpAndSettle();
            expect(
              session.clipboard.bankedRowLayerIds,
              isNotEmpty,
              reason: '⛔전제: a board',
            );
            return (session, under);
          }

          Future<({_Pill pill, String independent, String linked})> from(
            bool theTop,
          ) async {
            final results = <String>[];
            late _Pill lit;
            for (final linked in [false, true]) {
              final (session, under) = await setUp();
              // Clear of the blocks' edges, which a press takes hold of.
              final ends = [(_b, 10), (under, 9)];
              await sweep(
                tester,
                theTop
                    ? (from: ends.first, to: ends.last)
                    : (from: ends.last, to: ends.first),
              );
              expect(
                session.frameRangeSelection.value?.spanLayerIds.length,
                2,
                reason: '⛔전제: a band of two rows',
              );
              lit = pill(session);
              final panel = TimelineToolbarPanelContext(session);
              linked ? panel.pasteLinkedFrame() : panel.pasteIndependentFrame();
              await tester.pumpAndSettle();
              results.add(sheet(session));
              await tester.pumpWidget(const SizedBox());
            }
            return (pill: lit, independent: results[0], linked: results[1]);
          }

          final fromTheTop = await from(true);
          expect(
            fromTheTop.pill.pasteIndependent || fromTheTop.pill.pasteLinked,
            isTrue,
            reason: '⛔전제: a paste is lit',
          );
          final fromTheBottom = await from(false);
          // ⛔But 복제: a ROW's verb — 「복제는 현재 액티브인 대상」 (유저
          // 2026-08-13) — and a synced row is no row of its own to copy.
          _Pill banded(_Pill pill) => (
            cut: pill.cut,
            copy: pill.copy,
            pasteIndependent: pill.pasteIndependent,
            pasteLinked: pill.pasteLinked,
            delete: pill.delete,
            unlink: pill.unlink,
            duplicate: false,
            merge: pill.merge,
            autoName: pill.autoName,
          );
          expect(
            banded(fromTheBottom.pill),
            banded(fromTheTop.pill),
            reason: '「뭘 어떻게」',
          );
          expect(fromTheBottom.independent, fromTheTop.independent);
          expect(fromTheBottom.linked, fromTheTop.linked);
        });
      }
    }
  }
}
