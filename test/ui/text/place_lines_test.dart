import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';
import 'package:anicel/src/services/persistence/cel_places.dart';
import 'package:anicel/src/ui/text/place_lines.dart';

/// A use of a pool file reads as the line a person finds it by (F-118): a
/// row by its cut and its name, a frame the way the save's lost-picture list
/// names a drawing — one line for a frame on a row, in both lists.
void main() {
  test('a row placed from the file reads as its cut and its name', () {
    expect(
      mediaAssetUseLine(
        const RowMediaUse(
          cutId: CutId('c1'),
          layerId: LayerId('walk'),
          ownerName: 'C1',
          layerName: 'walk',
        ),
      ),
      'C1 · walk',
    );
  });

  test('a frame that carries the file reads the way the lost-picture list '
      'names a drawing', () {
    const place = DrawingCelPlace(
      ownerName: 'Video',
      layerName: 'S1',
      celName: 'walk.mp4',
    );
    expect(
      mediaAssetUseLine(
        const FrameMediaUse(
          trackId: TrackId('t1'),
          cutId: null,
          layerId: LayerId('s1'),
          frameId: FrameId('step'),
          place: place,
        ),
      ),
      'Video · S1 · walk.mp4',
    );
    expect(celPlaceLine(place), 'Video · S1 · walk.mp4');
  });

  test('an image row\'s unnamed cel reads as its cut and its row — the '
      'row\'s name is the picture\'s, and no empty third part trails it', () {
    expect(
      celPlaceLine(
        const DrawingCelPlace(ownerName: 'C1', layerName: 'BG', celName: ''),
      ),
      'C1 · BG',
    );
  });

  group('linkPartnerLines — where a linked row\'s pictures are shared', () {
    // 🗣️유저 2026-09-25: 「링크버튼통해서 어디랑 링크되고있는지만 제대로
    // 표시하게」.
    Layer row(String id, String name) =>
        Layer(id: LayerId(id), name: name, frames: const []);
    Cut cut(String id, List<Layer> layers) => Cut(
      id: CutId(id),
      name: id.toUpperCase(),
      layers: layers,
      duration: 4,
      canvasSize: const CanvasSize(width: 8, height: 8),
    );
    LayerLinkMember member(String cutId, String layerId) => LayerLinkMember(
      trackId: const TrackId('t1'),
      cutId: CutId(cutId),
      layerId: LayerId(layerId),
    );
    final project = Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('t1'),
          name: 'V',
          cuts: [
            cut('c1', [row('bg', 'BG'), row('a', 'A')]),
            cut('c2', [row('bg2', 'BG')]),
            cut('c3', [row('book', 'BOOK')]),
          ],
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'g',
            members: [
              member('c1', 'bg'),
              member('c2', 'bg2'),
              member('c3', 'book'),
              member('c3', 'gone'),
            ],
          ),
        ],
      ),
    );

    test('every OTHER member, as a row reads — the row itself is not its '
        'own partner, and a member whose row is gone is not listed', () {
      expect(
        linkPartnerLines(
          project,
          cutId: const CutId('c1'),
          layerId: const LayerId('bg'),
        ),
        ['C2 · BG', 'C3 · BOOK'],
      );
      expect(
        linkPartnerLines(
          project,
          cutId: const CutId('c3'),
          layerId: const LayerId('book'),
        ),
        ['C1 · BG', 'C2 · BG'],
      );
    });

    test('an unlinked row has no partners — and no badge', () {
      expect(
        linkPartnerLines(
          project,
          cutId: const CutId('c1'),
          layerId: const LayerId('a'),
        ),
        isEmpty,
      );
    });
  });
}
