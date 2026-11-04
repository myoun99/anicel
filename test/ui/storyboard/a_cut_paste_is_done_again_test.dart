import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/home_page_probes.dart';

/// 🗣️F-559 (유저 2026-11-04): 「컷블록 링크붙여넣기로 타임라인 같은
/// 겸용컷만들때, 언두하고 리두하면 다시 생겨야하는데 안생김.
/// 독립붙여넣기도 동일」 — pressed as the user presses it: the conte
/// panel's pill, then the app's undo and redo.
void main() {
  const v = TrackId('v');

  Project twoCuts({bool conte = false}) => Project(
    id: const ProjectId('paste-redo'),
    name: 'Cuts',
    createdAt: DateTime.utc(2026, 11, 4),
    tracks: [
      Track(
        id: v,
        name: 'V',
        cuts: [
          for (final (name, length) in [('10', 6), ('11', 4)])
            Cut(
              id: CutId('cut-$name'),
              name: name,
              duration: length,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [
                Layer(
                  id: LayerId('cut-$name-a'),
                  name: 'A',
                  frames: [
                    Frame(
                      id: FrameId('cut-$name-cel'),
                      duration: 1,
                      strokes: const [],
                      name: '1',
                    ),
                  ],
                  timeline: {
                    0: TimelineExposure.drawing(
                      FrameId('cut-$name-cel'),
                      length: length,
                    ),
                  },
                ),
                if (conte)
                  for (final (row, rides) in [
                    ('conte', null),
                    ('over', 'conte'),
                  ])
                    Layer(
                      id: LayerId('cut-$name-$row'),
                      name: row,
                      kind: LayerKind.storyboard,
                      attachedToLayerId: rides == null
                          ? null
                          : LayerId('cut-$name-$rides'),
                      attachedPlacement: AttachedPlacement.above,
                      attachedMode: AttachedMode.free,
                      frames: [
                        Frame(
                          id: FrameId('cut-$name-$row-0'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: {
                        0: TimelineExposure.drawing(
                          FrameId('cut-$name-$row-0'),
                          length: length,
                        ),
                      },
                    ),
              ],
            ),
        ],
      ),
    ],
  );

  for (final (linked, band, keys) in [
    for (final linked in [true, false])
      for (final band in [false, true])
        for (final keys in [false, true]) (linked, band, keys),
  ]) {
    final paste = linked ? 'linked' : 'independent';
    final picked = band ? 'a band of it' : 'standing in it';
    final by = keys ? 'the keys' : 'the buttons';
    testWidgets('an $paste paste of a cut copied $picked, undone, is done '
        'again — by $by', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: twoCuts())),
      );
      await tester.pumpAndSettle();
      await showStoryboardPanel(tester);
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      List<String> names() => [
        for (final cut
            in session.repository.requireProject().tracks.single.cuts)
          cut.name,
      ];

      session.selectGlobalFrame(1);
      session.selectTrackRow(v);
      if (band) {
        session.updateStoryboardCutSelectionByFrame(
          anchorGlobalFrame: 1,
          headGlobalFrame: 2,
        );
      }
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      if (!band) {
        session.selectGlobalFrame(7);
        session.selectTrackRow(v);
      }
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        ValueKey<String>(
          linked
              ? 'shared-paste-linked-button'
              : 'shared-paste-independent-button',
        ),
      );
      final pasted = names();
      expect(pasted, hasLength(3), reason: '⛔전제: the paste made a cut');

      Future<void> press({required bool undo}) async {
        if (!keys) {
          await tapToolbarButton(
            tester,
            ValueKey<String>(undo ? 'undo-button' : 'redo-button'),
          );
          return;
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (!undo) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        if (!undo) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await press(undo: true);
      expect(names(), ['10', '11'], reason: '⛔전제: undone');
      expect(session.canRedo, isTrue, reason: 'the paste is there to redo');

      await press(undo: false);
      expect(names(), pasted, reason: '「다시 생겨야하는데」');
    });
  }

  // 🗣️F-559-Q1 (유저 2026-11-04): 「이미 겸용컷인 컷을 복사해서 붙여넣는
  // 동작」 — the cut copied is one of a 겸용 pair already.
  for (final linked in [true, false]) {
    final paste = linked ? 'linked' : 'independent';
    testWidgets('a cut 겸용 already, copied and pasted $paste: undone and '
        'done again', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: twoCuts())),
      );
      await tester.pumpAndSettle();
      await showStoryboardPanel(tester);
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      List<String> names() => [
        for (final track in session.repository.requireProject().tracks)
          for (final cut in track.cuts) cut.name,
      ];
      session.selectCut(const CutId('cut-10'));
      session.cutVerbs.createLinkedCutFromActiveCut();
      await tester.pumpAndSettle();
      expect(names(), hasLength(3), reason: '⛔전제: 10 has its 겸용 cut');

      session.selectGlobalFrame(1);
      session.selectTrackRow(v);
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      final end = session.repository
          .requireProject()
          .tracks
          .single
          .cuts
          .fold(0, (frames, cut) => frames + cut.duration);
      session.selectGlobalFrame(end - 1);
      session.selectTrackRow(v);
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        ValueKey<String>(
          linked
              ? 'shared-paste-linked-button'
              : 'shared-paste-independent-button',
        ),
      );
      final pasted = names();
      expect(pasted, hasLength(4), reason: '⛔전제: the paste made a cut');

      await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expect(names(), hasLength(3), reason: '⛔전제: undone');
      await tapToolbarButton(tester, const ValueKey<String>('redo-button'));
      expect(names(), pasted, reason: '「다시 생겨야하는데」');
      expect(tester.takeException(), isNull);
    });
  }

  // The pair made as F-559 made it — a cut copied and pasted linked — and
  // then one of the pair copied and pasted again.
  for (final (conte, again, linked) in [
    for (final conte in [false, true])
      for (final again in ['the cut copied first', 'the cut its paste made'])
        for (final linked in [true, false]) (conte, again, linked),
  ]) {
    {
      final paste = linked ? 'linked' : 'independent';
      final rows = conte ? ', a conte on each' : '';
      testWidgets('a 겸용 pair a linked paste made$rows, $again copied and '
          'pasted $paste: undone and done again', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: HomePage(initialProject: twoCuts(conte: conte))),
        );
        await tester.pumpAndSettle();
        await showStoryboardPanel(tester);
        final session = tester
            .widget<EditorWorkspace>(find.byType(EditorWorkspace))
            .session;
        List<Cut> cuts() =>
            session.repository.requireProject().tracks.single.cuts;
        int end() => cuts().fold(0, (frames, cut) => frames + cut.duration);
        Future<void> press(String button, {required int at}) async {
          session.selectGlobalFrame(at);
          session.selectTrackRow(v);
          await tester.pumpAndSettle();
          await tapToolbarButton(tester, ValueKey<String>(button));
        }

        await press('shared-copy-button', at: 1);
        await press('shared-paste-linked-button', at: end() - 1);
        expect(cuts(), hasLength(3), reason: '⛔전제: the pair');
        final made = cuts().last;
        expect(made.name, isNot('10'), reason: '⛔전제: a cut of its own');

        await press(
          'shared-copy-button',
          at: again == 'the cut copied first' ? 1 : end() - 1,
        );
        await press(
          linked
              ? 'shared-paste-linked-button'
              : 'shared-paste-independent-button',
          at: end() - 1,
        );
        final pasted = [for (final cut in cuts()) cut.name];
        expect(pasted, hasLength(4), reason: '⛔전제: the paste made a cut');

        await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
        expect(cuts(), hasLength(3), reason: '⛔전제: undone');
        await tapToolbarButton(tester, const ValueKey<String>('redo-button'));
        expect(
          [for (final cut in cuts()) cut.name],
          pasted,
          reason: '「다시 생겨야하는데」',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  // As the app opens a project: its default cut's rows, a second cut made
  // by the cut button, and a drawing inked on the first.
  for (final linked in [true, false]) {
    final paste = linked ? 'linked' : 'independent';
    testWidgets('a new project\'s cut, inked, pasted $paste: undone and done '
        'again', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: newUntitledProject())),
      );
      await tester.pumpAndSettle();
      await showStoryboardPanel(tester);
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      final first = session.requireActiveCut;
      session.createDrawingAtCurrentFrame();
      final cel = session.selectedFrame!;
      inkCel(
        session,
        session.brushFrameKeyForCut(first, session.activeLayer!.id, cel.id),
        canvasSize: first.canvasSize,
        at: CanvasPoint(x: 20, y: 20),
        size: 6,
      );
      session.cutVerbs.createCut();
      await tester.pumpAndSettle();
      List<String> names() => [
        for (final track in session.repository.requireProject().tracks)
          for (final cut in track.cuts) cut.name,
      ];
      expect(names(), hasLength(2), reason: '⛔전제: two cuts');
      final track = session.repository.requireProject().tracks.first;

      session.selectGlobalFrame(0);
      session.selectTrackRow(track.id);
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      session.selectGlobalFrame(first.duration + 1);
      session.selectTrackRow(track.id);
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        ValueKey<String>(
          linked
              ? 'shared-paste-linked-button'
              : 'shared-paste-independent-button',
        ),
      );
      final pasted = names();
      expect(pasted, hasLength(3), reason: '⛔전제: the paste made a cut');

      await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expect(names(), hasLength(2), reason: '⛔전제: undone');
      await tapToolbarButton(tester, const ValueKey<String>('redo-button'));
      expect(names(), pasted, reason: '「다시 생겨야하는데」');
      expect(tester.takeException(), isNull);
    });
  }

  // 🗣️F-559-Q2 (유저 2026-11-04): 「새 프로젝트 → 초기 컷 블록 복사 → 컷 뒤로
  // 이동 → 붙여넣기. 언두하고 리두하면 안 생김. 컷1 에 재생헤드 있는 채로
  // 붙여넣으면 생김. 뒤에 붙여넣는다거나 하는 게 문젠 듯」.
  for (final (linked, past) in [
    for (final linked in [true, false])
      for (final past in [0, 6, -1]) (linked, past),
  ]) {
    final paste = linked ? 'linked' : 'independent';
    final at = past < 0 ? 'on the cut' : 'past the track\'s end by $past';
    testWidgets('🎯a new project\'s one cut pasted $paste $at: undone and '
        'done again', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: newUntitledProject())),
      );
      await tester.pumpAndSettle();
      await showStoryboardPanel(tester);
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      final first = session.requireActiveCut;
      List<String> names() => [
        for (final track in session.repository.requireProject().tracks)
          for (final cut in track.cuts) cut.name,
      ];
      expect(names(), hasLength(1), reason: '⛔전제: the one cut');
      final track = session.repository.requireProject().tracks.first;

      session.selectGlobalFrame(0);
      session.selectTrackRow(track.id);
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      session.selectGlobalFrame(past < 0 ? 1 : first.duration + past);
      session.selectTrackRow(track.id);
      await tester.pumpAndSettle();
      await tapToolbarButton(
        tester,
        ValueKey<String>(
          linked
              ? 'shared-paste-linked-button'
              : 'shared-paste-independent-button',
        ),
      );
      final pasted = names();
      expect(pasted, hasLength(2), reason: '⛔전제: the paste made a cut');

      await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expect(names(), hasLength(1), reason: '⛔전제: undone');
      await tapToolbarButton(tester, const ValueKey<String>('redo-button'));
      expect(names(), pasted, reason: '「다시 생겨야하는데」');
      expect(tester.takeException(), isNull);
    });
  }
}
