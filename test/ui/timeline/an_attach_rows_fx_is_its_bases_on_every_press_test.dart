import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';

import '../../helpers/named_finders.dart';

/// R9: an attach row and its 공정 organizer folder wear their BASE's
/// composite — 「어태치폴더는 우선 fx를 갖지않음... 주인레이어 따라가야
/// 하기때문」 — so neither row mounts an fx switch
/// (`r9_attach_composite_test`). A press that reaches them another way
/// passes them by as their rows do: a sweep down the fx column, and a
/// press spread across the row selection. ↩️Both flipped the row's own
/// switch — a flag nothing reads, on a row with no switch to show it.
void main() {
  const a = LayerId('a');
  const base = LayerId('base');
  const rider = LayerId('rider');
  const organizer = LayerId('organizer');
  const top = LayerId('top');

  Layer plain(LayerId id) => Layer(id: id, name: id.value, frames: const []);

  // An attach row riding [base] above it, in the organizer folder — the
  // shape `r9_attach_composite_test` reads the predicate off.
  Project project() => Project(
    id: const ProjectId('attach-fx'),
    name: 'Attach fx',
    createdAt: DateTime.utc(2026, 10, 17),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              plain(a),
              plain(base),
              Layer(
                id: rider,
                name: 'base+1',
                frames: const [],
                attachedToLayerId: base,
                attachedPlacement: AttachedPlacement.above,
                folderId: organizer,
              ),
              createFolderLayer(id: organizer, name: '[연출]'),
              plain(top),
            ],
          ),
        ],
      ),
    ],
  );

  bool switchOf(EditorSessionManager s, LayerId id) =>
      requireLayerAnywhere(s.repository.requireProject(), id).transformEnabled;

  Map<LayerId, bool> switches(EditorSessionManager s) => {
    for (final id in [a, base, rider, organizer, top]) id: switchOf(s, id),
  };

  test('a press spread across the selection passes them by', () {
    final s = EditorSessionManager(initialProject: project());
    addTearDown(s.dispose);
    s.rowSelection.value = [
      for (final id in [top, organizer, rider, base]) LayerRowAddress(id),
    ];

    SessionRowButtonPresses(s).toggleFx(top);

    expect(switches(s), {
      a: true,
      base: false,
      rider: true,
      organizer: true,
      top: false,
    }, reason: 'the selected rows with a switch went off with the pressed one');
  });

  group('a sweep down the fx column', () {
    // A sweep that ends without its release leaves its pointer claimed.
    tearDown(debugClearValueControlPointers);

    testWidgets('passes them by', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: project())),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      final s = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      for (final id in [rider, organizer]) {
        expect(
          find.named('timeline-layer-fx-${id.value}'),
          findsNothing,
          reason: 'the premise: $id mounts no fx switch',
        );
      }
      double rowY(LayerId id) =>
          tester.getCenter(find.named('timeline-layer-row-${id.value}')).dy;
      final ys = [for (final id in [a, base, rider, organizer, top]) rowY(id)];
      final first = ys.reduce((p, q) => p < q ? p : q);
      final last = ys.reduce((p, q) => p > q ? p : q);
      final topRow = ys.indexOf(first);
      final from = [a, base, rider, organizer, top][topRow];
      expect(
        find.named('timeline-layer-fx-${from.value}'),
        findsOneWidget,
        reason: 'the premise: the sweep starts on a switch',
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.named('timeline-layer-fx-${from.value}')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      const steps = 8;
      for (var step = 1; step <= steps; step += 1) {
        await gesture.moveBy(Offset(0, (last - first) / steps));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(switches(s), {
        a: false,
        base: false,
        rider: true,
        organizer: true,
        top: false,
      }, reason: 'the rows with a switch went off, the two without kept it');
    });
  });
}
