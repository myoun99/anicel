import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/update_layer_timeline_command.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/clipboard/layer_copy_payload.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('CutCommandCoordinator', () {
    test('createCut plans first-available IDs and records undo/redo', () {
      final existingCut = _cut(
        id: 'cut-2',
        name: 'Existing',
        layers: [_layer(id: 'layer-2')],
      );
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [existingCut]),
          ],
        ),
        activeCutId: existingCut.id,
      );

      fixture.coordinator.createCut(
        trackId: const TrackId('track-1'),
        name: 'Created',
      );

      var cuts = fixture.cutsFor(const TrackId('track-1'));
      expect(cuts.map((cut) => cut.id), [
        const CutId('cut-2'),
        const CutId('cut-1'),
      ]);
      expect(cuts.last.name, 'Created');
      expect(cuts.last.layers.first.id, const LayerId('layer-1'));
      expect(fixture.editingSession.activeCutId, const CutId('cut-1'));
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);

      fixture.historyManager.undo();

      cuts = fixture.cutsFor(const TrackId('track-1'));
      expect(cuts, [existingCut]);
      expect(fixture.editingSession.activeCutId, existingCut.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      cuts = fixture.cutsFor(const TrackId('track-1'));
      expect(cuts.map((cut) => cut.id), [
        const CutId('cut-2'),
        const CutId('cut-1'),
      ]);
      expect(fixture.editingSession.activeCutId, const CutId('cut-1'));
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);
    });

    group('linkDuplicateLayer (L2)', () {
      Cut linkFixtureCut() => _cut(
        id: 'cut-1',
        layers: [
          _layer(id: 'base', frames: [_frame(id: 'frame-a')]).copyWith(
            timeline: {
              0: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
            },
          ),
          _layer(id: 'color').copyWith(
            attachedToLayerId: const LayerId('base'),
          ),
          _layer(id: 'unrelated'),
        ],
      );

      test('duplicates the WHOLE attach group as a FREE group with the '
          'same FrameIds and names, and registers link pairs', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );

        fixture.coordinator.linkDuplicateLayer(
          cutId: const CutId('cut-1'),
          // Selecting the ATTACH member resolves to the whole group.
          layerId: const LayerId('color'),
        );

        final cut = requireCut(fixture.project, const CutId('cut-1'));
        expect(cut.layers.map((layer) => layer.id.value), [
          'base',
          'color',
          'layer-1',
          'layer-2',
          'unrelated',
        ]);
        final baseCopy = cut.layers[2];
        final colorCopy = cut.layers[3];
        // Free group: the copy attaches internally, never to the source.
        expect(baseCopy.attachedToLayerId, isNull);
        expect(colorCopy.attachedToLayerId, baseCopy.id);
        // Linked ⇒ same name, same FrameIds (the link mechanism).
        expect(baseCopy.name, 'base');
        expect(baseCopy.frames.single.id, const FrameId('frame-a'));
        expect(
          baseCopy.timeline[0]!.frameId,
          const FrameId('frame-a'),
          reason: 'the copied timeline exposes the SHARED cel',
        );
        // Registry: one pair per member.
        final registry = fixture.project.linkRegistry;
        expect(registry.groups, hasLength(2));
        expect(
          registry.useCountOf(
            cutId: const CutId('cut-1'),
            layerId: const LayerId('base'),
          ),
          2,
        );
        expect(
          registry
              .groupOf(cutId: const CutId('cut-1'), layerId: baseCopy.id)
              ?.canonical
              .layerId,
          const LayerId('base'),
          reason: 'the source stays canonical',
        );

        fixture.historyManager.undo();
        expect(
          requireCut(fixture.project, const CutId('cut-1')).layers.length,
          3,
        );
        expect(fixture.project.linkRegistry.isEmpty, isTrue);

        fixture.historyManager.redo();
        expect(
          requireCut(fixture.project, const CutId('cut-1')).layers.length,
          5,
        );
        expect(fixture.project.linkRegistry.groups, hasLength(2));
      });

      test('createLinkedCut: the new cut links the drawing layers with '
          'EMPTY timelines, fresh fixture rows, and registry pairs', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );

        fixture.coordinator.createLinkedCut(
          sourceCutId: const CutId('cut-1'),
          name: 'reuse',
        );

        final track = fixture.project.tracks.single;
        expect(track.cuts.map((cut) => cut.name), ['Cut', 'reuse']);
        final linkedCut = track.cuts[1];
        expect(fixture.editingSession.activeCutId, linkedCut.id);

        // Drawing layers linked (same FrameIds, same names), timelines
        // EMPTY — the bank re-exposes to a new rhythm.
        final animationCopies = linkedCut.layers
            .where((layer) => layer.kind == LayerKind.animation)
            .toList();
        // EVERY drawing layer links — 겸용컷 = the whole picture stack.
        expect(animationCopies.map((layer) => layer.name), [
          'base',
          'color',
          'unrelated',
        ]);
        expect(
          animationCopies.first.frames.single.id,
          const FrameId('frame-a'),
        );
        expect(animationCopies.first.timeline, isEmpty);
        expect(
          animationCopies[1].attachedToLayerId,
          animationCopies.first.id,
          reason: 'the attach glue re-targets inside the linked cut',
        );
        // Fresh fixture rows exist (per-use SE/instruction floors).
        expect(
          linkedCut.layers.any(
            (layer) => layer.kind == LayerKind.instruction,
          ),
          isTrue,
        );

        final registry = fixture.project.linkRegistry;
        expect(registry.groups, hasLength(3));
        expect(
          registry
              .groupOf(
                cutId: linkedCut.id,
                layerId: animationCopies.first.id,
              )
              ?.canonical
              .cutId,
          const CutId('cut-1'),
          reason: 'the source cut stays canonical',
        );

        fixture.historyManager.undo();
        expect(fixture.project.tracks.single.cuts, hasLength(1));
        expect(fixture.project.linkRegistry.isEmpty, isTrue);
        expect(
          fixture.editingSession.activeCutId,
          const CutId('cut-1'),
        );

        fixture.historyManager.redo();
        expect(fixture.project.tracks.single.cuts, hasLength(2));
        expect(fixture.project.linkRegistry.groups, hasLength(3));
      });

      test('unlinkLayer FORKS the pixels and leaves the group; undo '
          're-links back to the shared cel', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        final store = BrushFrameStore()
          ..setLinkResolver(
            (key) =>
                fixture.repository.currentProject?.linkRegistry
                    .canonicalCelKey(key) ??
                key,
          );
        final coordinator = CutCommandCoordinator(
          repository: fixture.repository,
          editingSession: fixture.editingSession,
          historyManager: fixture.historyManager,
          brushFrameStore: store,
        );

        coordinator.linkDuplicateLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
        );
        final copyId = fixture.project.linkRegistry.groups
            .firstWhere(
              (group) => group.contains(
                cutId: const CutId('cut-1'),
                layerId: const LayerId('base'),
              ),
            )
            .members
            .last
            .layerId;

        BrushFrameKey celKey(LayerId layerId) => BrushFrameKey(
          projectId: const ProjectId('project-1'),
          trackId: const TrackId('track-1'),
          cutId: const CutId('cut-1'),
          layerId: layerId,
          frameId: const FrameId('frame-a'),
        );
        final ink = BitmapSurface(
          canvasSize: const CanvasSize(width: 1280, height: 720),
        ).putTile(
          BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256),
        );
        // Draw through the COPY: lands under the canonical (base) key.
        store.storeBakedSurface(celKey(copyId), ink);
        expect(
          identical(
            store.bakedSurfaceOrNull(celKey(const LayerId('base'))),
            store.bakedSurfaceOrNull(celKey(copyId)),
          ),
          isTrue,
        );

        coordinator.unlinkLayer(
          cutId: const CutId('cut-1'),
          layerId: copyId,
        );

        // Group dissolved (singleton leftovers are meaningless).
        expect(
          fixture.project.linkRegistry.groupOf(
            cutId: const CutId('cut-1'),
            layerId: const LayerId('base'),
          ),
          isNull,
        );
        // The copy owns its cel now: editing the ORIGINAL no longer
        // touches it.
        final repainted = BitmapSurface(
          canvasSize: const CanvasSize(width: 1280, height: 720),
        ).putTile(
          BitmapTile.blank(coord: TileCoord(x: 1, y: 0), size: 256),
        );
        store.storeBakedSurface(celKey(const LayerId('base')), repainted);
        expect(
          identical(store.bakedSurfaceOrNull(celKey(copyId)), ink),
          isTrue,
          reason: 'the fork keeps the shared picture as its own',
        );

        // Undo (of the unlink, after undoing the base repaint is out of
        // scope here — the store edit above is not a history command):
        fixture.historyManager.undo();
        // BOTH pairs restore — the unlink unit is the whole attach group
        // (base pair AND color pair).
        expect(fixture.project.linkRegistry.groups, hasLength(2));
        expect(
          identical(
            store.bakedSurfaceOrNull(celKey(copyId)),
            store.bakedSurfaceOrNull(celKey(const LayerId('base'))),
          ),
          isTrue,
          reason: 're-linked: the member reads the canonical cel again',
        );
      });

      test('renaming a linked layer PROPAGATES to every member — the link '
          'survives and "linked means same name" stays true', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );

        fixture.coordinator.linkDuplicateLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
        );
        fixture.coordinator.renameLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
          name: 'flower',
        );

        final cut = requireCut(fixture.project, const CutId('cut-1'));
        final baseNames = [
          for (final layer in cut.layers)
            if (layer.id == const LayerId('base') ||
                layer.id == const LayerId('layer-1'))
              layer.name,
        ];
        expect(baseNames, ['flower', 'flower']);
        expect(
          fixture.project.linkRegistry.useCountOf(
            cutId: const CutId('cut-1'),
            layerId: const LayerId('base'),
          ),
          2,
          reason: 'renaming never breaks the link',
        );

        fixture.historyManager.undo();
        final reverted = requireCut(fixture.project, const CutId('cut-1'));
        expect(
          [
            for (final layer in reverted.layers)
              if (layer.id == const LayerId('base') ||
                  layer.id == const LayerId('layer-1'))
                layer.name,
          ],
          ['base', 'base'],
          reason: 'one undo restores every member',
        );
      });

      test('a frame-bank edit MIRRORS onto linked members (adopt the '
          'bank, sweep dead exposures); lane edits stay local', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        fixture.coordinator.createLinkedCut(
          sourceCutId: const CutId('cut-1'),
          name: 'reuse',
        );
        final linkedCut = fixture.project.tracks.single.cuts[1];
        final memberId = fixture.project.linkRegistry
            .groupOf(cutId: const CutId('cut-1'), layerId: const LayerId('base'))!
            .members
            .last
            .layerId;

        // The member exposes the shared cel on ITS own lane.
        final member = fixture.project.tracks.single.cuts[1].layers
            .firstWhere((layer) => layer.id == memberId);
        fixture.repository.replaceLayer(
          layer: member.copyWith(
            timeline: {
              0: TimelineExposure.drawing(const FrameId('frame-a'), length: 2),
            },
          ),
        );

        // 1. RENAME the cel in the SOURCE bank → the member's bank
        //    follows; its lane stays untouched.
        final source = requireCut(
          fixture.project,
          const CutId('cut-1'),
        ).layers.firstWhere((layer) => layer.id == const LayerId('base'));
        fixture.historyManager.execute(
          UpdateLayerTimelineCommand(
            repository: fixture.repository,
            before: source,
            after: source.copyWith(
              frames: [source.frames.single.copyWith(name: 'mouth-A')],
            ),
          ),
        );

        Layer memberNow() => requireCut(fixture.project, linkedCut.id).layers
            .firstWhere((layer) => layer.id == memberId);
        expect(memberNow().frames.single.name, 'mouth-A');
        expect(memberNow().timeline[0]!.frameId, const FrameId('frame-a'));

        // 2. REMOVE the cel from the source bank → it ceases to exist
        //    everywhere; the member's dead exposure sweeps.
        final renamedSource = requireCut(
          fixture.project,
          const CutId('cut-1'),
        ).layers.firstWhere((layer) => layer.id == const LayerId('base'));
        fixture.historyManager.execute(
          UpdateLayerTimelineCommand(
            repository: fixture.repository,
            before: renamedSource,
            after: renamedSource.copyWith(frames: [], timeline: const {}),
          ),
        );
        expect(memberNow().frames, isEmpty);
        expect(memberNow().timeline, isEmpty);

        // One undo per step restores every member exactly.
        fixture.historyManager.undo();
        expect(memberNow().frames.single.name, 'mouth-A');
        expect(memberNow().timeline[0]!.frameId, const FrameId('frame-a'));
        fixture.historyManager.undo();
        expect(memberNow().frames.single.name, isNull);
      });

      test('deleting a linked layer deletes EVERY member and dissolves '
          'the group; one undo reinserts them all', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        fixture.coordinator.createLinkedCut(
          sourceCutId: const CutId('cut-1'),
          name: 'reuse',
        );
        final linkedCutId = fixture.project.tracks.single.cuts[1].id;
        final memberId = fixture.project.linkRegistry
            .groupOf(
              cutId: const CutId('cut-1'),
              layerId: const LayerId('unrelated'),
            )!
            .members
            .last
            .layerId;

        fixture.coordinator.deleteLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('unrelated'),
        );

        expect(
          requireCut(fixture.project, const CutId('cut-1')).layers.any(
            (layer) => layer.id == const LayerId('unrelated'),
          ),
          isFalse,
        );
        expect(
          requireCut(fixture.project, linkedCutId).layers.any(
            (layer) => layer.id == memberId,
          ),
          isFalse,
          reason: 'the deletion propagates to the linked cut',
        );
        expect(
          fixture.project.linkRegistry.groupOf(
            cutId: linkedCutId,
            layerId: memberId,
          ),
          isNull,
          reason: 'the emptied group dissolves',
        );

        fixture.historyManager.undo();
        expect(
          requireCut(fixture.project, const CutId('cut-1')).layers.any(
            (layer) => layer.id == const LayerId('unrelated'),
          ),
          isTrue,
        );
        expect(
          requireCut(fixture.project, linkedCutId).layers.any(
            (layer) => layer.id == memberId,
          ),
          isTrue,
        );
        expect(
          fixture.project.linkRegistry.useCountOf(
            cutId: const CutId('cut-1'),
            layerId: const LayerId('unrelated'),
          ),
          2,
        );
      });

      test('convertCutToLinked (겸용 변경): name-matches, links, 원본 승리 '
          'retargets conflicts, unions one-side-only layers; one undo', () {
        // Origin cel "cel" has frame "1" = f-o1; target's "cel" has
        // frame "1" = f-t1 (CONFLICT → origin wins) and "2" = f-t2
        // (JOINS). Origin also has "only-o"; target has "only-t".
        Cut originCut() => _cut(
          id: 'origin',
          layers: [
            _layer(id: 'o-cel', frames: [_frame(id: 'f-o1', name: '1')])
                .copyWith(
                  name: 'cel',
                  timeline: {
                    0: TimelineExposure.drawing(
                      const FrameId('f-o1'),
                      length: 1,
                    ),
                  },
                ),
            _layer(id: 'o-only').copyWith(name: 'only-o'),
          ],
        );
        Cut targetCut() => _cut(
          id: 'target',
          layers: [
            _layer(
              id: 't-cel',
              frames: [
                _frame(id: 'f-t1', name: '1'),
                _frame(id: 'f-t2', name: '2'),
              ],
            ).copyWith(
              name: 'cel',
              timeline: {
                0: TimelineExposure.drawing(const FrameId('f-t1'), length: 1),
                3: TimelineExposure.drawing(const FrameId('f-t2'), length: 1),
              },
            ),
            _layer(id: 't-only').copyWith(name: 'only-t'),
          ],
        );
        final fixture = _fixture(
          _project(
            tracks: [
              _track(
                id: 'track-1',
                name: 'V',
                cuts: [originCut(), targetCut()],
              ),
            ],
          ),
          activeCutId: const CutId('origin'),
        );
        final store = BrushFrameStore()
          ..setLinkResolver(
            (key) =>
                fixture.repository.currentProject?.linkRegistry
                    .canonicalCelKey(key) ??
                key,
          );
        final coordinator = CutCommandCoordinator(
          repository: fixture.repository,
          editingSession: fixture.editingSession,
          historyManager: fixture.historyManager,
          brushFrameStore: store,
        );

        // Preview (dialog data) reports the effect before executing.
        final preview = coordinator.convertToLinkedCutPreview(
          originCutId: const CutId('origin'),
          targetCutId: const CutId('target'),
        );
        expect(preview.replacedFrameCount, 1, reason: 'name "1" conflicts');
        expect(preview.joiningFrameCount, 1, reason: 'name "2" joins');
        expect(preview.originOnlyLayerIds, [const LayerId('o-only')]);
        expect(preview.targetOnlyLayerIds, [const LayerId('t-only')]);

        coordinator.convertCutToLinked(
          originCutId: const CutId('origin'),
          targetCutId: const CutId('target'),
        );

        // The target's "cel" now shares the origin's bank; its conflicting
        // exposure retargets to the origin's frame, timing untouched.
        final target = requireCut(fixture.project, const CutId('target'));
        final targetCel = target.layers.firstWhere(
          (layer) => layer.id == const LayerId('t-cel'),
        );
        expect(targetCel.frames.map((frame) => frame.id.value), [
          'f-o1',
          'f-t2',
        ], reason: 'merged bank = origin frames + joiners');
        expect(targetCel.timeline[0]!.frameId, const FrameId('f-o1'));
        expect(targetCel.timeline[3]!.frameId, const FrameId('f-t2'));

        // Union: the origin gained a linked copy of "only-t", the target a
        // copy of "only-o" — both with empty timelines.
        expect(
          target.layers.any((layer) => layer.name == 'only-o'),
          isTrue,
        );
        expect(
          requireCut(fixture.project, const CutId('origin')).layers.any(
            (layer) => layer.name == 'only-t',
          ),
          isTrue,
        );

        // The registry links every drawing layer.
        expect(
          fixture.project.linkRegistry.useCountOf(
            cutId: const CutId('origin'),
            layerId: const LayerId('o-cel'),
          ),
          2,
        );

        // One undo restores both cuts exactly.
        fixture.historyManager.undo();
        expect(fixture.project.linkRegistry.isEmpty, isTrue);
        expect(
          requireCut(fixture.project, const CutId('origin')).layers,
          originCut().layers,
        );
        expect(
          requireCut(fixture.project, const CutId('target')).layers,
          targetCut().layers,
        );
      });

      test('convertCutToLinked RE-RUN is a no-op: already-linked pairs are '
          'neither pairs nor one-side-only (no duplicate copies)', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(
                id: 'track-1',
                name: 'V',
                cuts: [
                  _cut(
                    id: 'origin',
                    layers: [
                      _layer(
                        id: 'o-cel',
                        frames: [_frame(id: 'f-o1', name: '1')],
                      ).copyWith(name: 'cel'),
                    ],
                  ),
                  _cut(
                    id: 'target',
                    layers: [
                      _layer(
                        id: 't-cel',
                        frames: [_frame(id: 'f-t1', name: '1')],
                      ).copyWith(name: 'cel'),
                    ],
                  ),
                ],
              ),
            ],
          ),
          activeCutId: const CutId('origin'),
        );
        final store = BrushFrameStore()
          ..setLinkResolver(
            (key) =>
                fixture.repository.currentProject?.linkRegistry
                    .canonicalCelKey(key) ??
                key,
          );
        final coordinator = CutCommandCoordinator(
          repository: fixture.repository,
          editingSession: fixture.editingSession,
          historyManager: fixture.historyManager,
          brushFrameStore: store,
        );
        coordinator.convertCutToLinked(
          originCutId: const CutId('origin'),
          targetCutId: const CutId('target'),
        );
        final layerCountAfterFirst = requireCut(
          fixture.project,
          const CutId('target'),
        ).layers.length;

        final rerunPreview = coordinator.convertToLinkedCutPreview(
          originCutId: const CutId('origin'),
          targetCutId: const CutId('target'),
        );
        expect(rerunPreview.linksAnything, isFalse);
        expect(rerunPreview.originOnlyLayerIds, isEmpty,
            reason: 'already-linked layers must not leak into "only"');

        coordinator.convertCutToLinked(
          originCutId: const CutId('origin'),
          targetCutId: const CutId('target'),
        );
        expect(
          requireCut(fixture.project, const CutId('target')).layers.length,
          layerCountAfterFirst,
          reason: 're-running must not insert duplicate linked copies',
        );
      });

      test('updateLayerKind MIRRORS over the link group (shared property '
          'like name/mark); one undo restores every member', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        fixture.coordinator.linkDuplicateLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
        );
        final cut = requireCut(fixture.project, const CutId('cut-1'));
        final baseCopyId = cut.layers[2].id;

        fixture.coordinator.updateLayerKind(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
          kind: LayerKind.image,
        );

        Layer layerOf(LayerId id) => requireCut(
          fixture.project,
          const CutId('cut-1'),
        ).layers.firstWhere((layer) => layer.id == id);
        expect(layerOf(const LayerId('base')).kind, LayerKind.image);
        expect(layerOf(baseCopyId).kind, LayerKind.image,
            reason: 'kind mirrors to every link member');
        expect(layerOf(const LayerId('unrelated')).kind, LayerKind.animation);

        fixture.historyManager.undo();
        expect(layerOf(const LayerId('base')).kind, LayerKind.animation);
        expect(layerOf(baseCopyId).kind, LayerKind.animation);
      });

      test('createFolderFromLayer folds the WHOLE attach group into a new '
          'folder (contiguity free); dissolve releases; both undo', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );

        final folderId = fixture.coordinator.createFolderFromLayer(
          cutId: const CutId('cut-1'),
          // The attach member folds its whole group.
          layerId: const LayerId('color'),
        )!;

        Cut cut() => requireCut(fixture.project, const CutId('cut-1'));
        Layer layerOf(String id) =>
            cut().layers.firstWhere((layer) => layer.id.value == id);
        expect(cut().layers.folderLayers.single.id, folderId);
        expect(cut().layers.folderLayers.single.name, 'Folder 1');
        expect(layerOf('base').folderId, folderId);
        expect(layerOf('color').folderId, folderId);
        expect(layerOf('unrelated').folderId, isNull);
        // The folder ROW sits directly above its member run — the stack
        // position the group buffer walks.
        expect(folderStructureProblem(cut().layers), isNull);

        fixture.coordinator.dissolveFolder(
          cutId: const CutId('cut-1'),
          folderId: folderId,
        );
        expect(cut().layers.folderLayers, isEmpty);
        expect(layerOf('base').folderId, isNull);

        fixture.historyManager.undo();
        expect(cut().layers.folderLayers.single.id, folderId);
        expect(layerOf('base').folderId, folderId);
        expect(folderStructureProblem(cut().layers), isNull);

        fixture.historyManager.undo();
        expect(cut().layers.folderLayers, isEmpty);
        expect(layerOf('base').folderId, isNull);
      });

      test('folder structure MIRRORS over 겸용 cuts: create appears around '
          'the counterparts, rename follows, dissolve follows — each one '
          'undo', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        fixture.coordinator.createLinkedCut(
          sourceCutId: const CutId('cut-1'),
          name: 'linked',
        );
        final linkedCutId = fixture
            .cutsFor(const TrackId('track-1'))
            .firstWhere((cut) => cut.name == 'linked')
            .id;

        final folderId = fixture.coordinator.createFolderFromLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
        )!;

        Cut origin() => requireCut(fixture.project, const CutId('cut-1'));
        Cut linked() => requireCut(fixture.project, linkedCutId);
        Layer linkedBase() =>
            linked().layers.firstWhere((layer) => layer.name == 'base');
        expect(origin().layers.folderLayers.single.id, folderId);
        final mirrored = linked().layers.folderLayers.single;
        expect(mirrored.id, isNot(folderId), reason: 'folder ids are per-cut');
        expect(mirrored.name, 'Folder 1');
        expect(linkedBase().folderId, mirrored.id,
            reason: 'the counterpart member sits in the mirrored folder');
        expect(folderStructureProblem(linked().layers), isNull);

        // Renaming a folder is renaming a LAYER — no folder-shaped command
        // survives, and the mirror rides the folder rows' link group.
        fixture.coordinator.renameLayer(
          cutId: const CutId('cut-1'),
          layerId: folderId,
          name: 'Cel A',
        );
        expect(origin().layers.folderLayers.single.name, 'Cel A');
        expect(linked().layers.folderLayers.single.name, 'Cel A');
        fixture.historyManager.undo();
        expect(linked().layers.folderLayers.single.name, 'Folder 1');
        fixture.historyManager.redo();

        fixture.coordinator.dissolveFolder(
          cutId: const CutId('cut-1'),
          folderId: folderId,
        );
        expect(origin().layers.folderLayers, isEmpty);
        expect(linked().layers.folderLayers, isEmpty);
        expect(linkedBase().folderId, isNull);

        fixture.historyManager.undo();
        expect(origin().layers.folderLayers.single.name, 'Cel A');
        expect(linked().layers.folderLayers.single.name, 'Cel A');
        expect(
          linkedBase().folderId,
          linked().layers.folderLayers.single.id,
        );
      });

      test('a folder FX track rides updateLayerTransformTrack in one undo '
          '(per-use — the 겸용 counterpart keeps its own)', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        fixture.coordinator.createLinkedCut(
          sourceCutId: const CutId('cut-1'),
          name: 'linked',
        );
        final linkedCutId = fixture
            .cutsFor(const TrackId('track-1'))
            .firstWhere((cut) => cut.name == 'linked')
            .id;
        final folderId = fixture.coordinator.createFolderFromLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
        )!;

        final track = TransformTrack(
          keyframes: {
            0: TransformPose(center: CanvasPoint(x: 5, y: 5), zoom: 2),
          },
        );
        fixture.coordinator.updateLayerTransformTrack(
          cutId: const CutId('cut-1'),
          layerId: folderId,
          transformTrack: track,
        );

        Layer folderOf(CutId cutId) =>
            requireCut(fixture.project, cutId).layers.folderLayers.single;
        expect(folderOf(const CutId('cut-1')).transformTrack, track);
        expect(
          folderOf(linkedCutId).transformTrack.isNotEmpty,
          isFalse,
          reason: 'FX lanes are per-use ("레인만 각자") — never mirrored',
        );

        fixture.historyManager.undo();
        expect(
          folderOf(const CutId('cut-1')).transformTrack.isNotEmpty,
          isFalse,
        );
      });

      test('deleting the CANONICAL cut promotes the survivor: registry '
          'sweeps, cels re-key onto it, and undo restores everything', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );
        final store = BrushFrameStore()
          ..setLinkResolver(
            (key) =>
                fixture.repository.currentProject?.linkRegistry
                    .canonicalCelKey(key) ??
                key,
          );
        final coordinator = CutCommandCoordinator(
          repository: fixture.repository,
          editingSession: fixture.editingSession,
          historyManager: fixture.historyManager,
          brushFrameStore: store,
        );
        coordinator.createLinkedCut(
          sourceCutId: const CutId('cut-1'),
          name: 'reuse',
        );
        final linkedCut = fixture.project.tracks.single.cuts[1];
        final survivorId = fixture.project.linkRegistry
            .groupOf(cutId: const CutId('cut-1'), layerId: const LayerId('base'))!
            .members
            .last
            .layerId;

        // Ink lives under the CANONICAL (cut-1/base) key.
        final ink = BitmapSurface(
          canvasSize: const CanvasSize(width: 1280, height: 720),
        ).putTile(
          BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256),
        );
        BrushFrameKey survivorKey() => BrushFrameKey(
          projectId: const ProjectId('project-1'),
          trackId: const TrackId('track-1'),
          cutId: linkedCut.id,
          layerId: survivorId,
          frameId: const FrameId('frame-a'),
        );
        store.storeBakedSurface(survivorKey(), ink); // → canonical (cut-1)

        coordinator.deleteCut(cutId: const CutId('cut-1'));

        // The group dissolved (lone survivor) and the survivor now READS
        // ITS OWN key — the cels re-keyed onto it.
        expect(fixture.project.linkRegistry.isEmpty, isTrue);
        expect(
          identical(store.bakedSurfaceOrNull(survivorKey()), ink),
          isTrue,
          reason: 'pixels keep routing after the canonical cut died',
        );

        fixture.historyManager.undo();
        expect(fixture.project.tracks.single.cuts, hasLength(2));
        expect(
          fixture.project.linkRegistry.useCountOf(
            cutId: const CutId('cut-1'),
            layerId: const LayerId('base'),
          ),
          2,
        );
        expect(
          identical(store.bakedSurfaceOrNull(survivorKey()), ink),
          isTrue,
          reason: 're-linked: the survivor resolves back to the canonical',
        );
      });

      test('link-duplicating an already-linked layer EXTENDS its group '
          'instead of nesting a new one', () {
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'V', cuts: [linkFixtureCut()]),
            ],
          ),
          activeCutId: const CutId('cut-1'),
        );

        fixture.coordinator.linkDuplicateLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('base'),
        );
        fixture.coordinator.linkDuplicateLayer(
          cutId: const CutId('cut-1'),
          layerId: const LayerId('layer-1'),
        );

        final registry = fixture.project.linkRegistry;
        expect(registry.groups, hasLength(2));
        expect(
          registry.useCountOf(
            cutId: const CutId('cut-1'),
            layerId: const LayerId('base'),
          ),
          3,
          reason: 'base, first copy and second copy share one group',
        );
      });
    });

    test(
      'renameCut renames by ID, allows duplicate names, and records history',
      () {
        final cutA = _cut(id: 'cut-1', name: 'Cut A');
        final cutB = _cut(id: 'cut-2', name: 'Cut B');
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
            ],
          ),
          activeCutId: cutA.id,
        );

        fixture.coordinator.renameCut(cutId: cutB.id, newName: 'Cut A');

        expect(requireCut(fixture.project, cutA.id).name, 'Cut A');
        expect(requireCut(fixture.project, cutB.id).name, 'Cut A');
        expect(requireCut(fixture.project, cutB.id).id, cutB.id);
        expect(fixture.historyManager.undoCount, 1);

        fixture.historyManager.undo();

        expect(requireCut(fixture.project, cutB.id).name, 'Cut B');
        expect(fixture.historyManager.redoCount, 1);

        fixture.historyManager.redo();

        expect(requireCut(fixture.project, cutB.id).name, 'Cut A');
        expect(fixture.historyManager.undoCount, 1);
      },
    );

    test('updateCutNote updates note through history with undo/redo', () {
      final cutA = _cut(id: 'cut-1', name: 'Cut A');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.updateCutNote(cutId: cutA.id, note: 'General note');

      expect(requireCut(fixture.project, cutA.id).metadata.note, 'General note');
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);

      fixture.historyManager.undo();

      expect(requireCut(fixture.project, cutA.id).metadata.note, '');
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(requireCut(fixture.project, cutA.id).metadata.note, 'General note');
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateCutNote skips unchanged note without history entry', () {
      final cutA = _cut(
        id: 'cut-1',
        name: 'Cut A',
        metadata: const CutMetadata(note: 'Same note'),
      );
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final beforeJson = fixture.project.toJson();

      fixture.coordinator.updateCutNote(cutId: cutA.id, note: 'Same note');

      expect(fixture.project.toJson(), beforeJson);
      expect(requireCut(fixture.project, cutA.id).metadata.note, 'Same note');
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateCutNote throws StateError when target cut is missing', () {
      final cutA = _cut(id: 'cut-1', name: 'Cut A');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final beforeJson = fixture.project.toJson();

      expect(
        () => fixture.coordinator.updateCutNote(
          cutId: const CutId('cut-missing'),
          note: 'General note',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Cut not found: cut-missing'),
          ),
        ),
      );

      expect(fixture.project.toJson(), beforeJson);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateExposureMemo routes through history with undo/redo', () {
      final frame = _frame(id: 'frame-1');
      final layer = _layer(
        id: 'layer-1',
        kind: LayerKind.storyboard,
        frames: [frame],
      );
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      const memo = ExposureMemo(actionMemo: 'Action', note: 'Note');

      ExposureMemo? memoAt(int index) => fixture
          .project
          .tracks
          .single
          .cuts
          .single
          .layers
          .single
          .timeline[index]
          ?.memo;

      fixture.coordinator.updateExposureMemo(
        cutId: cutA.id,
        layerId: layer.id,
        blockStartIndex: 0,
        memo: memo,
      );

      expect(memoAt(0), memo);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);

      fixture.historyManager.undo();

      expect(memoAt(0), isNull);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(memoAt(0), memo);
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateExposureMemo skips an unchanged memo', () {
      final frame = _frame(id: 'frame-1');
      final layer = _layer(
        id: 'layer-1',
        kind: LayerKind.storyboard,
        frames: [frame],
      );
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      // An EMPTY memo is what "no memo" already is, so writing one is a
      // no-op rather than an undo step over nothing.
      final beforeJson = fixture.project.toJson();

      fixture.coordinator.updateExposureMemo(
        cutId: cutA.id,
        layerId: layer.id,
        blockStartIndex: 0,
        memo: const ExposureMemo.empty(),
      );

      expect(fixture.project.toJson(), beforeJson);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateExposureMemo refuses an index that starts no block', () {
      final frame = _frame(id: 'frame-1');
      final layer = _layer(
        id: 'layer-1',
        kind: LayerKind.storyboard,
        frames: [frame],
      );
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final beforeJson = fixture.project.toJson();

      expect(
        () => fixture.coordinator.updateExposureMemo(
          cutId: cutA.id,
          layerId: layer.id,
          blockStartIndex: 7,
          memo: const ExposureMemo(note: 'New'),
        ),
        throwsStateError,
      );

      expect(fixture.project.toJson(), beforeJson);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 0);
    });

    test(
      'reorderCut executes through history without changing activeCutId',
      () {
        final cutA = _cut(id: 'cut-1', name: 'Cut A');
        final cutB = _cut(id: 'cut-2', name: 'Cut B');
        final cutC = _cut(id: 'cut-3', name: 'Cut C');
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB, cutC]),
            ],
          ),
          activeCutId: cutB.id,
        );

        fixture.coordinator.reorderCut(
          trackId: const TrackId('track-1'),
          cutId: cutA.id,
          newIndex: 2,
        );

        expect(fixture.cutsFor(const TrackId('track-1')), [cutB, cutC, cutA]);
        expect(fixture.editingSession.activeCutId, cutB.id);
        expect(fixture.historyManager.undoCount, 1);
        expect(fixture.historyManager.redoCount, 0);

        fixture.historyManager.undo();

        expect(fixture.cutsFor(const TrackId('track-1')), [cutA, cutB, cutC]);
        expect(fixture.editingSession.activeCutId, cutB.id);
        expect(fixture.historyManager.undoCount, 0);
        expect(fixture.historyManager.redoCount, 1);

        fixture.historyManager.redo();

        expect(fixture.cutsFor(const TrackId('track-1')), [cutB, cutC, cutA]);
        expect(fixture.editingSession.activeCutId, cutB.id);
        expect(fixture.historyManager.undoCount, 1);
        expect(fixture.historyManager.redoCount, 0);
      },
    );


    test(
      'deleteCut deletes an active cut and lets the command select fallback',
      () {
        final cutA = _cut(id: 'cut-1', name: 'Cut A');
        final cutB = _cut(id: 'cut-2', name: 'Cut B');
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
            ],
          ),
          activeCutId: cutA.id,
        );

        fixture.coordinator.deleteCut(cutId: cutA.id);

        expect(fixture.cutsFor(const TrackId('track-1')), [cutB]);
        expect(fixture.editingSession.activeCutId, cutB.id);
        expect(fixture.historyManager.undoCount, 1);

        fixture.historyManager.undo();

        expect(fixture.cutsFor(const TrackId('track-1')), [cutA, cutB]);
        expect(fixture.editingSession.activeCutId, cutA.id);
        expect(fixture.historyManager.redoCount, 1);

        fixture.historyManager.redo();

        expect(fixture.cutsFor(const TrackId('track-1')), [cutB]);
        expect(fixture.editingSession.activeCutId, cutB.id);
        expect(fixture.historyManager.undoCount, 1);
      },
    );

    test('deleteCut removes a non-active cut without changing activeCutId', () {
      final activeCut = _cut(id: 'cut-1', name: 'Active');
      final deletedCut = _cut(id: 'cut-2', name: 'Deleted');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [activeCut, deletedCut]),
          ],
        ),
        activeCutId: activeCut.id,
      );

      fixture.coordinator.deleteCut(cutId: deletedCut.id);

      expect(fixture.cutsFor(const TrackId('track-1')), [activeCut]);
      expect(fixture.editingSession.activeCutId, activeCut.id);
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();

      expect(fixture.cutsFor(const TrackId('track-1')), [
        activeCut,
        deletedCut,
      ]);
      expect(fixture.editingSession.activeCutId, activeCut.id);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(fixture.cutsFor(const TrackId('track-1')), [activeCut]);
      expect(fixture.editingSession.activeCutId, activeCut.id);
      expect(fixture.historyManager.undoCount, 1);
    });

    test('R28 #14: deleting the LAST cut empties the track — no replacement '
        'is conjured, and undo brings the real cut back', () {
      final onlyCut = _cut(
        id: 'cut-1',
        name: 'Only',
        layers: [_layer(id: 'layer-1')],
      );
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [onlyCut]),
          ],
        ),
        activeCutId: onlyCut.id,
      );

      fixture.coordinator.deleteCut(cutId: onlyCut.id);

      expect(
        fixture.cutsFor(const TrackId('track-1')),
        isEmpty,
        reason: 'R28 #14: "컷도 1개도 없는 상황 허용" — a delete must actually '
            'be able to clear the track',
      );
      expect(
        fixture.editingSession.activeCutId,
        isNull,
        reason: 'the empty track is the no-active-cut state the editor '
            'already shows over a storyboard gap',
      );
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();

      expect(fixture.cutsFor(const TrackId('track-1')), [onlyCut]);
      expect(fixture.editingSession.activeCutId, onlyCut.id);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(fixture.cutsFor(const TrackId('track-1')), isEmpty);
      expect(fixture.editingSession.activeCutId, isNull);
    });

    test(
      'duplicateCut plans IDs, uses default copy name, and records undo/redo',
      () {
        final sourceCut = _cut(
          id: 'cut-1',
          name: 'Source',
          layers: [
            _layer(
              id: 'layer-1',
              frames: [
                _frame(id: 'frame-1'),
                _frame(id: 'frame-3'),
              ],
            ),
          ],
        );
        final targetCut = _cut(
          id: 'cut-3',
          name: 'Target Existing',
          layers: [
            _layer(
              id: 'layer-3',
              frames: [_frame(id: 'frame-2')],
            ),
          ],
        );
        final fixture = _fixture(
          _project(
            tracks: [
              _track(
                id: 'track-source',
                name: 'Source Track',
                cuts: [sourceCut],
              ),
              _track(
                id: 'track-target',
                name: 'Target Track',
                cuts: [targetCut],
              ),
            ],
          ),
          activeCutId: sourceCut.id,
        );

        fixture.coordinator.duplicateCut(
          sourceCutId: sourceCut.id,
          targetTrackId: const TrackId('track-target'),
        );

        var targetCuts = fixture.cutsFor(const TrackId('track-target'));
        expect(targetCuts, hasLength(2));
        final duplicate = targetCuts.last;
        expect(duplicate.id, const CutId('cut-2'));
        expect(duplicate.name, 'Source Copy');
        expect(duplicate.layers.single.id, const LayerId('layer-2'));
        expect(duplicate.layers.single.frames.map((frame) => frame.id), [
          const FrameId('frame-4'),
          const FrameId('frame-5'),
        ]);
        expect(fixture.cutsFor(const TrackId('track-source')), [sourceCut]);
        expect(fixture.editingSession.activeCutId, const CutId('cut-2'));
        expect(fixture.historyManager.undoCount, 1);

        fixture.historyManager.undo();

        expect(fixture.cutsFor(const TrackId('track-target')), [targetCut]);
        expect(fixture.editingSession.activeCutId, sourceCut.id);
        expect(fixture.historyManager.redoCount, 1);

        fixture.historyManager.redo();

        targetCuts = fixture.cutsFor(const TrackId('track-target'));
        expect(targetCuts.last, duplicate);
        expect(fixture.editingSession.activeCutId, const CutId('cut-2'));
        expect(fixture.historyManager.undoCount, 1);
      },
    );

    test('updateLayerKind routes through history with undo/redo', () {
      final layer = _layer(id: 'layer-1');
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.updateLayerKind(
        cutId: cutA.id,
        layerId: layer.id,
        kind: LayerKind.storyboard,
      );

      expect(requireLayerAnywhere(fixture.project, layer.id).kind, LayerKind.storyboard);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);

      fixture.historyManager.undo();

      expect(requireLayerAnywhere(fixture.project, layer.id).kind, LayerKind.animation);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(requireLayerAnywhere(fixture.project, layer.id).kind, LayerKind.storyboard);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 1);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateLayerKind skips unchanged kind without history entry', () {
      final layer = _layer(id: 'layer-1', kind: LayerKind.storyboard);
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final beforeJson = fixture.project.toJson();

      fixture.coordinator.updateLayerKind(
        cutId: cutA.id,
        layerId: layer.id,
        kind: LayerKind.storyboard,
      );

      expect(fixture.project.toJson(), beforeJson);
      expect(fixture.editingSession.activeCutId, cutA.id);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 0);
    });

    test('updateLayerKind refuses instruction on either side', () {
      final cel = _layer(id: 'layer-1');
      final instruction = _layer(id: 'layer-2', kind: LayerKind.instruction);
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [cel, instruction]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      expect(
        () => fixture.coordinator.updateLayerKind(
          cutId: cutA.id,
          layerId: cel.id,
          kind: LayerKind.instruction,
        ),
        throwsStateError,
      );
      expect(
        () => fixture.coordinator.updateLayerKind(
          cutId: cutA.id,
          layerId: instruction.id,
          kind: LayerKind.animation,
        ),
        throwsStateError,
      );
      expect(fixture.historyManager.undoCount, 0);
    });

    test('updateLayerKind keeps the SE floor of two', () {
      final se1 = _layer(id: 'layer-1', kind: LayerKind.se);
      final se2 = _layer(id: 'layer-2', kind: LayerKind.se);
      final se3 = _layer(id: 'layer-3', kind: LayerKind.se);
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [se1, se2, se3]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      // Three SE rows: converting one away is fine.
      fixture.coordinator.updateLayerKind(
        cutId: cutA.id,
        layerId: se3.id,
        kind: LayerKind.animation,
      );
      expect(requireLayerAnywhere(fixture.project, se3.id).kind, LayerKind.animation);
      expect(fixture.historyManager.undoCount, 1);

      // Down at the floor: silently refused, no history entry.
      fixture.coordinator.updateLayerKind(
        cutId: cutA.id,
        layerId: se2.id,
        kind: LayerKind.animation,
      );
      expect(requireLayerAnywhere(fixture.project, se2.id).kind, LayerKind.se);
      expect(fixture.historyManager.undoCount, 1);
    });

    test('updateLayerInstructions edits CAM rows through history and '
        'dedupes', () {
      final instruction = _layer(id: 'layer-1', kind: LayerKind.instruction);
      final cel = _layer(id: 'layer-2');
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [instruction, cel]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final spans = {
        0: const InstructionEvent(
          instructionId: 'fi',
          length: 12,
          valueA: 'A',
          valueB: 'B',
        ),
      };

      fixture.coordinator.updateLayerInstructions(
        cutId: cutA.id,
        layerId: instruction.id,
        instructions: spans,
      );
      expect(
        requireLayerAnywhere(fixture.project, instruction.id).instructions[0],
        spans[0],
      );
      expect(fixture.historyManager.undoCount, 1);

      // Unchanged map: no new history entry.
      fixture.coordinator.updateLayerInstructions(
        cutId: cutA.id,
        layerId: instruction.id,
        instructions: spans,
      );
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();
      expect(requireLayerAnywhere(fixture.project, instruction.id).instructions, isEmpty);
      fixture.historyManager.redo();
      expect(
        requireLayerAnywhere(fixture.project, instruction.id).instructions[0],
        spans[0],
      );

      // Only instruction rows carry spans.
      expect(
        () => fixture.coordinator.updateLayerInstructions(
          cutId: cutA.id,
          layerId: cel.id,
          instructions: spans,
        ),
        throwsStateError,
      );
    });

    test('updateCameraInstructionSet edits the vocabulary through history '
        'and dedupes', () {
      final cutA = _cut(id: 'cut-1', name: 'Cut A');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final custom = CameraInstructionSet(
        defs: [
          ...CameraInstructionSet.standard.defs,
          const CameraInstructionDef(
            id: 'custom-blur',
            name: 'ブレ',
            iconKey: 'shake',
          ),
        ],
      );

      fixture.coordinator.updateCameraInstructionSet(custom);
      expect(fixture.project.cameraInstructions, custom);
      expect(fixture.historyManager.undoCount, 1);

      fixture.coordinator.updateCameraInstructionSet(custom);
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();
      expect(fixture.project.cameraInstructions, CameraInstructionSet.standard);
    });

    test('updateMediaAssets edits the pool through history and dedupes', () {
      final cutA = _cut(id: 'cut-1', name: 'Cut A');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      const pool = [MediaAsset(path: '/snd/foot.wav', name: '발소리')];

      fixture.coordinator.updateMediaAssets(pool);
      expect(fixture.project.mediaAssets, pool);
      expect(fixture.historyManager.undoCount, 1);

      // Unchanged pool is a no-op.
      fixture.coordinator.updateMediaAssets(pool);
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();
      expect(fixture.project.mediaAssets, isEmpty);
    });

    test('relinkMediaAsset rewrites the pool entry AND every referencing '
        'clip in one undo step; clip identity elsewhere survives', () {
      const oldPath = '/snd/old/foot.wav';
      const newPath = '/snd/new/foot.wav';
      final seLayer = Layer(
        id: const LayerId('se-1'),
        name: 'S1',
        kind: LayerKind.se,
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
          2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
        },
        audioClips: const [
          AudioClip(filePath: oldPath, frameId: FrameId('f1')),
          AudioClip(filePath: '/snd/other.wav', frameId: FrameId('f2')),
        ],
      );
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [seLayer]);
      final untouchedCut = _cut(id: 'cut-2', name: 'Cut B');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, untouchedCut]),
          ],
        ),
        activeCutId: cutA.id,
      );
      fixture.coordinator.updateMediaAssets(const [
        MediaAsset(path: oldPath, name: '발소리'),
        MediaAsset(path: '/snd/other.wav', name: 'other.wav'),
      ]);
      final untouchedBefore = fixture.project.tracks.single.cuts[1];

      fixture.coordinator.relinkMediaAsset(oldPath: oldPath, newPath: newPath);

      expect(fixture.project.mediaAssetByPath(newPath)?.name, '발소리');
      expect(fixture.project.mediaAssetByPath(oldPath), isNull);
      final clips =
          fixture.project.tracks.single.cuts.first.layers.single.audioClips;
      expect(clips.first.filePath, newPath);
      expect(clips.first.frameId, const FrameId('f1'));
      expect(clips.last.filePath, '/snd/other.wav');
      // Untouched subtrees keep their identity (cache warmth).
      expect(
        identical(fixture.project.tracks.single.cuts[1], untouchedBefore),
        isTrue,
      );

      fixture.historyManager.undo();
      expect(fixture.project.mediaAssetByPath(oldPath)?.name, '발소리');
      expect(
        fixture
            .project
            .tracks
            .single
            .cuts
            .first
            .layers
            .single
            .audioClips
            .first
            .filePath,
        oldPath,
      );

      // Guards: same path, unknown asset, or occupied target are no-ops.
      final undoCountBefore = fixture.historyManager.undoCount;
      fixture.coordinator.relinkMediaAsset(oldPath: oldPath, newPath: oldPath);
      fixture.coordinator.relinkMediaAsset(
        oldPath: '/missing.wav',
        newPath: newPath,
      );
      fixture.coordinator.relinkMediaAsset(
        oldPath: oldPath,
        newPath: '/snd/other.wav',
      );
      expect(fixture.historyManager.undoCount, undoCountBefore);
    });

    test('duplicateLayer carries instruction spans to the copy', () {
      final instruction = Layer(
        id: const LayerId('layer-1'),
        name: 'CAM 1',
        kind: LayerKind.instruction,
        frames: const [],
        timeline: const {},
        instructions: {
          3: const InstructionEvent(instructionId: 'pan', length: 6),
        },
      );
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [instruction]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      final copyId = fixture.coordinator.duplicateLayer(
        cutId: cutA.id,
        sourceLayerId: instruction.id,
      );

      final copy = requireLayerAnywhere(fixture.project, copyId);
      expect(copy.kind, LayerKind.instruction);
      expect(
        copy.instructions[3],
        const InstructionEvent(instructionId: 'pan', length: 6),
      );
    });

    test('updateLayerAudioClips edits SE rows through history, dedupes and '
        'guards the kind', () {
      final se = _layer(id: 'layer-1', kind: LayerKind.se);
      final cel = _layer(id: 'layer-2');
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [se, cel]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      const clips = [
        AudioClip(filePath: 'voice.wav', frameId: FrameId('se-voice')),
      ];

      fixture.coordinator.updateLayerAudioClips(
        cutId: cutA.id,
        layerId: se.id,
        audioClips: clips,
      );
      expect(requireLayerAnywhere(fixture.project, se.id).audioClips, clips);
      expect(fixture.historyManager.undoCount, 1);

      // Unchanged list: no new history entry.
      fixture.coordinator.updateLayerAudioClips(
        cutId: cutA.id,
        layerId: se.id,
        audioClips: clips,
      );
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();
      expect(requireLayerAnywhere(fixture.project, se.id).audioClips, isEmpty);
      fixture.historyManager.redo();
      expect(requireLayerAnywhere(fixture.project, se.id).audioClips, clips);

      expect(
        () => fixture.coordinator.updateLayerAudioClips(
          cutId: cutA.id,
          layerId: cel.id,
          audioClips: clips,
        ),
        throwsStateError,
      );
    });

    test('updateLayerAudioClips reaches TRACK-owned SE rows (UI-R7 #4: media '
        'drops used to dead-end in the cut-scoped lookup)', () {
      final trackSe = _layer(id: 'track-se-1', kind: LayerKind.se);
      final cutA = _cut(id: 'cut-1', name: 'Cut A');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(
              id: 'track-1',
              name: 'Video',
              cuts: [cutA],
              seLayers: [trackSe],
            ),
          ],
        ),
        activeCutId: cutA.id,
      );
      const clips = [
        AudioClip(filePath: 'foot.wav', frameId: FrameId('se-foot')),
      ];

      fixture.coordinator.updateLayerAudioClips(
        cutId: cutA.id,
        layerId: trackSe.id,
        audioClips: clips,
      );
      expect(requireLayerAnywhere(fixture.project, trackSe.id).audioClips, clips);

      fixture.historyManager.undo();
      expect(requireLayerAnywhere(fixture.project, trackSe.id).audioClips, isEmpty);
      fixture.historyManager.redo();
      expect(requireLayerAnywhere(fixture.project, trackSe.id).audioClips, clips);
    });

    test('duplicateLayer carries audio clips to the SE copy', () {
      final se = Layer(
        id: const LayerId('layer-1'),
        name: 'S1',
        kind: LayerKind.se,
        frames: const [],
        timeline: const {},
        audioClips: const [
          AudioClip(filePath: 'voice.wav', frameId: FrameId('se-voice')),
        ],
      );
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [se]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      final copyId = fixture.coordinator.duplicateLayer(
        cutId: cutA.id,
        sourceLayerId: se.id,
      );

      final copy = requireLayerAnywhere(fixture.project, copyId);
      expect(copy.kind, LayerKind.se);
      expect(copy.audioClips.single.filePath, 'voice.wav');
    });

    test('R28 #14: deleteLayer keeps the SE and instruction floors, but the '
        'DRAWING floor is gone — the action section may empty out', () {
      final cel = _layer(id: 'layer-1');
      final se1 = _layer(id: 'layer-2', kind: LayerKind.se);
      final se2 = _layer(id: 'layer-3', kind: LayerKind.se);
      final se3 = _layer(id: 'layer-4', kind: LayerKind.se);
      final instruction = _layer(id: 'layer-5', kind: LayerKind.instruction);
      final cutA = _cut(
        id: 'cut-1',
        name: 'Cut A',
        layers: [cel, se1, se2, se3, instruction],
      );
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      // The third SE row deletes; the floor pair does not.
      fixture.coordinator.deleteLayer(cutId: cutA.id, layerId: se3.id);
      expect(fixture.historyManager.undoCount, 1);
      fixture.coordinator.deleteLayer(cutId: cutA.id, layerId: se2.id);
      expect(fixture.historyManager.undoCount, 1);

      // The only instruction row does not delete.
      fixture.coordinator.deleteLayer(cutId: cutA.id, layerId: instruction.id);
      expect(fixture.historyManager.undoCount, 1);

      // R28 #14: the LAST drawing-section layer DOES delete now — "액션
      // 레이어가 1개도 없는상황 허용". The sheet fixtures (SE pair,
      // instruction row) keep their floors; the action section does not.
      fixture.coordinator.deleteLayer(cutId: cutA.id, layerId: cel.id);
      expect(fixture.historyManager.undoCount, 2);
      final remaining = fixture.project.tracks.single.cuts.single.layers;
      expect(remaining, hasLength(3));
      expect(
        remaining.where((layer) => layer.kind == LayerKind.animation),
        isEmpty,
      );

      // ...and it comes back.
      fixture.historyManager.undo();
      expect(
        fixture.project.tracks.single.cuts.single.layers.map((l) => l.id),
        contains(cel.id),
      );
    });

    test('setLayerTimesheet flips the flag through history', () {
      final layer = _layer(id: 'layer-1');
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.setLayerTimesheet(
        cutId: cutA.id,
        layerId: layer.id,
        onTimesheet: false,
      );

      expect(requireLayerAnywhere(fixture.project, layer.id).onTimesheet, isFalse);
      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();

      expect(requireLayerAnywhere(fixture.project, layer.id).onTimesheet, isTrue);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(requireLayerAnywhere(fixture.project, layer.id).onTimesheet, isFalse);
      expect(fixture.historyManager.undoCount, 1);
    });

    test('setLayerTimesheet skips unchanged flag without history entry', () {
      final layer = _layer(id: 'layer-1');
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      final beforeJson = fixture.project.toJson();

      fixture.coordinator.setLayerTimesheet(
        cutId: cutA.id,
        layerId: layer.id,
        onTimesheet: true,
      );

      expect(fixture.project.toJson(), beforeJson);
      expect(fixture.historyManager.undoCount, 0);
    });

    test('setLayerTimesheet toggles the camera layer too (unified layer '
        'controls — it gates the printed CAM column)', () {
      final cameraLayer = _layer(id: 'camera-1', kind: LayerKind.camera);
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [cameraLayer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.setLayerTimesheet(
        cutId: cutA.id,
        layerId: cameraLayer.id,
        onTimesheet: false,
      );

      expect(requireLayerAnywhere(fixture.project, cameraLayer.id).onTimesheet, isFalse);
      expect(fixture.historyManager.undoCount, 1);
      fixture.historyManager.undo();
      expect(requireLayerAnywhere(fixture.project, cameraLayer.id).onTimesheet, isTrue);
    });

    test('setTimesheetInfo updates through history and dedupes', () {
      final cutA = _cut(id: 'cut-1', name: 'Cut A');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );
      const info = TimesheetInfo(
        title: 'YOASOBI',
        episode: 'MV',
        artist: 'MYOUN',
      );

      fixture.coordinator.setTimesheetInfo(info);

      expect(fixture.project.timesheetInfo, info);
      expect(fixture.historyManager.undoCount, 1);

      fixture.coordinator.setTimesheetInfo(info);
      expect(fixture.historyManager.undoCount, 1, reason: 'no-op dedupe');

      fixture.historyManager.undo();
      expect(fixture.project.timesheetInfo, TimesheetInfo.empty);

      fixture.historyManager.redo();
      expect(fixture.project.timesheetInfo, info);
    });

    test('setLayerMark sets the mark through history and dedupes', () {
      final layer = _layer(id: 'layer-1');
      final cutA = _cut(id: 'cut-1', name: 'Cut A', layers: [layer]);
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.setLayerMark(
        cutId: cutA.id,
        layerId: layer.id,
        mark: LayerMark.orange,
      );

      expect(requireLayerAnywhere(fixture.project, layer.id).mark, LayerMark.orange);
      expect(fixture.historyManager.undoCount, 1);

      fixture.coordinator.setLayerMark(
        cutId: cutA.id,
        layerId: layer.id,
        mark: LayerMark.orange,
      );

      expect(fixture.historyManager.undoCount, 1);

      fixture.historyManager.undo();

      expect(requireLayerAnywhere(fixture.project, layer.id).mark, LayerMark.none);
      expect(fixture.historyManager.redoCount, 1);

      fixture.historyManager.redo();

      expect(requireLayerAnywhere(fixture.project, layer.id).mark, LayerMark.orange);
    });

    test(
      'updateLayerKind rejects duplicate storyboard without history entry',
      () {
        final storyboard = _layer(
          id: 'layer-storyboard',
          kind: LayerKind.storyboard,
        );
        final animation = _layer(id: 'layer-animation');
        final cutA = _cut(
          id: 'cut-1',
          name: 'Cut A',
          layers: [storyboard, animation],
        );
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [cutA]),
            ],
          ),
          activeCutId: cutA.id,
        );
        final beforeJson = fixture.project.toJson();

        expect(
          () => fixture.coordinator.updateLayerKind(
            cutId: cutA.id,
            layerId: animation.id,
            kind: LayerKind.storyboard,
          ),
          throwsStateError,
        );

        expect(fixture.project.toJson(), beforeJson);
        expect(fixture.historyManager.undoCount, 0);
        expect(fixture.historyManager.redoCount, 0);
      },
    );

    test('duplicateCut throws StateError when source cut is missing', () {
      final existingCut = _cut(id: 'cut-1', name: 'Existing');
      final project = _project(
        tracks: [
          _track(id: 'track-1', name: 'Video', cuts: [existingCut]),
        ],
      );
      final fixture = _fixture(project, activeCutId: existingCut.id);
      final beforeJson = fixture.project.toJson();

      expect(
        () => fixture.coordinator.duplicateCut(
          sourceCutId: const CutId('cut-missing'),
          targetTrackId: const TrackId('track-1'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Cut not found: cut-missing'),
          ),
        ),
      );

      expect(fixture.project.toJson(), beforeJson);
      expect(fixture.historyManager.undoCount, 0);
      expect(fixture.historyManager.redoCount, 0);
      expect(fixture.cutsFor(const TrackId('track-1')), [existingCut]);
    });

    test(
      'pasteLayer inserts payload after requested raw index and is undoable',
      () {
        final layerA = _layer(id: 'A');
        final layerB = _layer(id: 'B');
        final layerC = _layer(id: 'C');
        final cut = _cut(id: 'cut-1', layers: [layerA, layerB, layerC]);
        final fixture = _fixture(
          _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [cut]),
            ],
          ),
          activeCutId: cut.id,
        );

        final pastedLayerId = fixture.coordinator.pasteLayer(
          cutId: cut.id,
          payload: copyLayerToPayload(layerA),
          insertionIndex: 2,
        );

        expect(
          requireCut(fixture.project, cut.id).layers.map((layer) => layer.name),
          ['A', 'B', 'A', 'C'],
        );
        expect(requireLayerAnywhere(fixture.project, pastedLayerId).id, pastedLayerId);
        expect(fixture.historyManager.undoCount, 1);

        fixture.historyManager.undo();
        expect(
          requireCut(fixture.project, cut.id).layers.map((layer) => layer.name),
          ['A', 'B', 'C'],
        );

        fixture.historyManager.redo();
        expect(
          requireCut(fixture.project, cut.id).layers.map((layer) => layer.name),
          ['A', 'B', 'A', 'C'],
        );
      },
    );

    test('createCut lands to the RIGHT of the active cut and counts from it '
        '(UI-R7 #3: the cut name IS the cut number)', () {
      final cutA = _cut(id: 'cut-1', name: '1');
      final cutB = _cut(id: 'cut-2', name: 'Opening');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.createCut(trackId: const TrackId('track-1'));

      // The new cut lands to the RIGHT of the active one and counts from
      // it: '1' → '2', inserted between '1' and 'Opening'.
      expect(
        fixture.project.tracks.single.cuts.map((cut) => cut.name),
        ['1', '2', 'Opening'],
      );
    });

    test('createCut splits when the next number is spoken for', () {
      final cutA = _cut(id: 'cut-1', name: '39');
      final cutB = _cut(id: 'cut-2', name: '40');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
          ],
        ),
        activeCutId: cutA.id,
      );

      fixture.coordinator.createCut(trackId: const TrackId('track-1'));

      expect(
        fixture.project.tracks.single.cuts.map((cut) => cut.name),
        ['39', '39A', '40'],
      );
    });

    test('the default project cut is named "1" — bare numbers, no prefix '
        '(UI-R7 #3)', () {
      final project = createDefaultProject();
      expect(project.tracks.single.cuts.single.name, '1');
    });

    test('duplicateCut uses caller-provided duplicate name when supplied', () {
      final sourceCut = _cut(id: 'cut-1', name: 'Source');
      final fixture = _fixture(
        _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [sourceCut]),
          ],
        ),
        activeCutId: sourceCut.id,
      );

      fixture.coordinator.duplicateCut(
        sourceCutId: sourceCut.id,
        targetTrackId: const TrackId('track-1'),
        newName: 'Custom Duplicate',
      );

      expect(
        fixture.cutsFor(const TrackId('track-1')).last.name,
        'Custom Duplicate',
      );
    });
  });
}

_Fixture _fixture(Project project, {required CutId activeCutId}) {
  final repository = ProjectRepository(initialProject: project);
  final editingSession = EditingSessionState(activeCutId: activeCutId);
  final historyManager = HistoryManager();
  return _Fixture(
    repository: repository,
    editingSession: editingSession,
    historyManager: historyManager,
    coordinator: CutCommandCoordinator(
      repository: repository,
      editingSession: editingSession,
      historyManager: historyManager,
    ),
  );
}

class _Fixture {
  const _Fixture({
    required this.repository,
    required this.editingSession,
    required this.historyManager,
    required this.coordinator,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final HistoryManager historyManager;
  final CutCommandCoordinator coordinator;

  Project get project => repository.requireProject();

  List<Cut> cutsFor(TrackId trackId) {
    for (final track in project.tracks) {
      if (track.id == trackId) {
        return track.cuts;
      }
    }

    throw StateError('Track not found: $trackId');
  }
}

Project _project({required List<Track> tracks}) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2024),
  );
}

Track _track({
  required String id,
  required String name,
  List<Cut> cuts = const [],
  List<Layer> seLayers = const [],
}) {
  return Track(id: TrackId(id), name: name, cuts: cuts, seLayers: seLayers);
}

Cut _cut({
  String id = 'cut-1',
  String name = 'Cut',
  List<Layer>? layers,
  CutMetadata metadata = const CutMetadata.empty(),
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: layers ?? [_layer(id: 'layer-$id')],
    duration: 1,
    canvasSize: const CanvasSize(width: 1280, height: 720),
    metadata: metadata,
  );
}

Layer _layer({
  required String id,
  List<Frame> frames = const [],
  LayerKind kind = LayerKind.animation,
}) {
  return Layer(id: LayerId(id), name: id, frames: frames, kind: kind);
}

Frame _frame({required String id, String? name}) {
  return Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);
}



