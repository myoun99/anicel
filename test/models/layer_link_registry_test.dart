import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  LayerLinkMember member(String cut, String layer, {String track = 't'}) =>
      LayerLinkMember(
        trackId: TrackId(track),
        cutId: CutId(cut),
        layerId: LayerId(layer),
      );

  LayerLinkRegistry registry() => LayerLinkRegistry(
    groups: [
      LayerLinkGroup(
        id: 'g1',
        members: [member('cut-a', 'layer-1'), member('cut-b', 'layer-9')],
      ),
    ],
  );

  group('LayerLinkRegistry', () {
    test('groupOf finds the group of any member; null when unlinked', () {
      final links = registry();
      expect(
        links.groupOf(cutId: CutId('cut-a'), layerId: LayerId('layer-1'))?.id,
        'g1',
      );
      expect(
        links.groupOf(cutId: CutId('cut-b'), layerId: LayerId('layer-9'))?.id,
        'g1',
      );
      expect(
        links.groupOf(cutId: CutId('cut-a'), layerId: LayerId('layer-9')),
        isNull,
      );
    });

    test('useCountOf is the member count for linked layers, 1 otherwise', () {
      final links = registry();
      expect(
        links.useCountOf(cutId: CutId('cut-b'), layerId: LayerId('layer-9')),
        2,
      );
      expect(
        links.useCountOf(cutId: CutId('cut-x'), layerId: LayerId('layer-1')),
        1,
      );
    });

    test('canonicalCelKey rewrites a member key to the canonical address, '
        'keeps the frame, and is idempotent', () {
      final links = registry();
      final memberKey = BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: const CutId('cut-b'),
        layerId: const LayerId('layer-9'),
        frameId: const FrameId('frame-7'),
      );

      final canonical = links.canonicalCelKey(memberKey);
      expect(canonical.cutId, const CutId('cut-a'));
      expect(canonical.layerId, const LayerId('layer-1'));
      expect(canonical.frameId, const FrameId('frame-7'));
      expect(links.canonicalCelKey(canonical), canonical);
    });

    test('canonicalCelKey leaves unlinked keys untouched', () {
      final key = BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: const CutId('cut-x'),
        layerId: const LayerId('layer-1'),
        frameId: const FrameId('frame-1'),
      );
      expect(registry().canonicalCelKey(key), key);
    });

    test('toJson/fromJson round-trips', () {
      final links = registry();
      expectJsonRoundTrip(links, LayerLinkRegistry.fromJson);
      expect(LayerLinkRegistry.fromJson(const {'groups': []}).isEmpty, isTrue);
    });

    test('a group must have at least one member', () {
      expect(
        () => LayerLinkGroup(id: 'empty', members: const []),
        throwsArgumentError,
      );
    });

    test('the registry round-trips through Project JSON; empty registries '
        'leave the legacy JSON untouched', () {
      final plain = createDefaultProject();
      expect(plain.toJson().containsKey('linkRegistry'), isFalse);
      expect(Project.fromJson(plain.toJson()).linkRegistry.isEmpty, isTrue);

      final linked = plain.copyWith(linkRegistry: registry());
      final reopened = Project.fromJson(linked.toJson());
      expect(reopened.linkRegistry, registry());
      expect(
        reopened.linkRegistry
            .groupOf(cutId: CutId('cut-a'), layerId: LayerId('layer-1'))
            ?.id,
        'g1',
      );
    });
  });
}
