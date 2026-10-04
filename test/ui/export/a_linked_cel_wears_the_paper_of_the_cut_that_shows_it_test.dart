import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// 🚨F-300 (유저 2026-10-05): 「겸용컷에서 BG 이미지레이어가 2장있는데 … 현재
/// 컷에 BG1이면 용지 적용되고 현재컷이아닌 BG2쪽은 용지가 빠짐 … 렌더에
/// 현재컷 관련 로직 있는건 이상하니 근본/구조적으로 해결」 · 「애니메이션
/// 레이어도 현재컷이 아니면 용지가 빠짐」.
///
/// The PIXELS, end to end — the plan and the render together: a cel only a
/// 겸용 sibling shows is exported over that sibling's paper, whichever cut
/// the export stands on. The plan's own arithmetic is pinned beside it
/// (`export_cel_group_plan_test.dart`).
void main() {
  const size = CanvasSize(width: 8, height: 8);
  const red = (255, 0, 0, 255);
  const blue = (0, 0, 255, 255);
  const black = (0, 0, 0, 255);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  /// Two 겸용 cuts sharing a paper row and a cel row A. Both banks are the
  /// link group's, and each cut shows its own cel of each — C1 the first
  /// paper and A 1, C2 the second paper and A 2.
  Cut cutOf(String id) => Cut(
    id: CutId(id),
    name: id.toUpperCase(),
    duration: 4,
    canvasSize: size,
    layers: [
      Layer(
        id: LayerId('$id-paper'),
        name: 'Paper',
        frames: [frame('p1', '1'), frame('p2', '2')],
        mark: const LayerMark(process: LayerProcess.paper),
        timeline: {
          0: TimelineExposure.drawing(
            FrameId(id == 'c1' ? 'p1' : 'p2'),
            length: 4,
          ),
        },
      ),
      Layer(
        id: LayerId('$id-a'),
        name: 'A',
        frames: [frame('a1', '1'), frame('a2', '2')],
        mark: const LayerMark(process: LayerProcess.key),
        timeline: {
          0: TimelineExposure.drawing(
            FrameId(id == 'c1' ? 'a1' : 'a2'),
            length: 4,
          ),
        },
      ),
      createCameraLayer(cutId: CutId(id)),
    ],
  );

  Project linked() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [cutOf('c1'), cutOf('c2')],
      ),
    ],
    linkRegistry: LayerLinkRegistry(
      groups: [
        for (final row in ['paper', 'a'])
          LayerLinkGroup(
            id: 'group-$row',
            members: [
              for (final cut in ['c1', 'c2'])
                LayerLinkMember(
                  trackId: const TrackId('track'),
                  cutId: CutId(cut),
                  layerId: LayerId('$cut-$row'),
                ),
            ],
          ),
      ],
    ),
    createdAt: DateTime.utc(2026),
  );

  /// The whole canvas [colour], or one pixel of it at ([x], [y]).
  BitmapSurface surface((int, int, int, int) colour, {int? x, int? y}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var py = 0; py < 8; py += 1) {
      for (var px = 0; px < 8; px += 1) {
        if ((x != null && px != x) || (y != null && py != y)) {
          continue;
        }
        final i = (py * 8 + px) * 4;
        pixels[i] = colour.$1;
        pixels[i + 1] = colour.$2;
        pixels[i + 2] = colour.$3;
        pixels[i + 3] = colour.$4;
      }
    }
    return BitmapSurface(
      canvasSize: size,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  for (final standingOn in ['c1', 'c2']) {
    testWidgets('exported standing on ${standingOn.toUpperCase()}: A2 — the '
        'cel only C2 shows — lies over C2\'s paper, and A1 over C1\'s', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final session = EditorSessionManager(initialProject: linked());
        addTearDown(session.dispose);
        final store = session.renderCaches.brushFrameStore;
        void put(String cut, String row, String cel, BitmapSurface pixels) =>
            store.storeBakedSurface(
              session.brushFrameKeyForCut(
                session.cutById(CutId(cut))!,
                LayerId('$cut-$row'),
                FrameId(cel),
              ),
              pixels,
            );
        // Each cut shows a paper of its own colour, so the picture says
        // WHICH cut's stack a cel was composited in.
        put('c1', 'paper', 'p1', surface(red));
        put('c2', 'paper', 'p2', surface(blue));
        put('c1', 'a', 'a1', surface(black, x: 1, y: 1));
        put('c2', 'a', 'a2', surface(black, x: 1, y: 1));

        final plan = buildExportCelGroupPlan(
          project: session.repository.requireProject(),
          activeCutId: CutId(standingOn),
          spec: const CelsExportSpec(),
        );
        Future<((int, int, int, int), (int, int, int, int))> shot(
          String file,
        ) async {
          final image = await ExportFrameRenderer(
            session: session,
            background: const ui.Color(0x00000000),
          ).renderCelGroup(
            plan.cels.singleWhere((task) => task.fileName == file),
            ExportSizeMode.canvas,
          );
          final bytes = (await image!.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          (int, int, int, int) at(int x, int y) {
            final i = (y * size.width + x) * 4;
            return (
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
              bytes.getUint8(i + 3),
            );
          }

          return (at(5, 5), at(1, 1));
        }

        expect(
          await shot('A2.png'),
          (blue, black),
          reason: 'A2 over the paper of C2, the cut that shows it',
        );
        expect(
          await shot('A1.png'),
          (red, black),
          reason: 'A1 over the paper of C1, the cut that shows it',
        );
      });
      await tester.pumpAndSettle();
    });
  }
}
