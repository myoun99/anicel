import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cels_selection.dart';

/// HIDING A FOLDER HIDES WHAT IS INSIDE IT — EVERYWHERE, NOT JUST WHERE THE
/// COMPOSITE LOOKS.
///
/// The composite plan always knew this: it walks the folder chain and a
/// hidden ancestor drops the subtree. Nothing else did. Seven other places
/// asked `layer.isVisible` — the row's OWN eye — and got a different answer
/// from the one on screen, so a row inside a folder the user had switched
/// off went on ghosting in onion skin, went on being counted by the bulk
/// sweep, and went on being written out by cel export.
///
/// The predicate for the whole question existed the entire time
/// ([LayerFolderQueries.rowVisible]'s neighbour `subtreeVisible`) and had
/// tests — and zero callers in `lib`. That is the failure this file is
/// really about: a law nobody can reach is not a law, so these tests drive
/// the SESSION and the EXPORT rather than the predicate.
void main() {
  /// A session whose active row sits inside a folder, with a cel drawn.
  (EditorSessionManager, LayerId member, LayerId folder) sessionWithFolder() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final member = s.activeLayer!.id;
    s.groupActiveLayerIntoFolder();
    final folder = s.activeCutOrNull!.layers.folderLayers.single.id;
    s.selectLayer(member);
    return (s, member, folder);
  }

  void hideFolder(EditorSessionManager s, LayerId folder) {
    if (s.activeCutOrNull!.layers.byId(folder)!.isVisible) {
      s.toggleLayerVisibility(folder);
    }
    expect(
      s.activeCutOrNull!.layers.byId(folder)!.isVisible,
      isFalse,
      reason: 'the fixture needs the folder actually off',
    );
  }

  group('the onion skin', () {
    test('a ghost stops when its FOLDER is hidden, not only when its own eye '
        'is', () {
      final (s, member, folder) = sessionWithFolder();
      s.toggleLayerOnionSkin(member);
      // Something to ghost: a second drawing so the plan has a neighbour.
      s.selectFrameIndex(1);
      s.createDrawingAtCurrentFrame();
      s.selectFrameIndex(2);

      expect(
        s.onionSkinCanvasRequests(),
        isNotEmpty,
        reason: 'the CONTROL — with everything visible there ARE ghosts',
      );

      hideFolder(s, folder);

      expect(
        s.onionSkinCanvasRequests(),
        isEmpty,
        reason:
            'A ghost is that row\'s artwork. Hiding the folder used to leave '
            'its members\' onion skins floating on screen with nothing under '
            'them, because this asked the row\'s own eye and the composite '
            'asked the folder chain.',
      );
    });

    test('the bulk sweep does not count a row inside a hidden folder', () {
      final (s, member, folder) = sessionWithFolder();
      s.toggleLayerOnionSkin(member);
      expect(
        s.displayedLayersOnionSkinEnabled,
        isTrue,
        reason: 'the CONTROL — the only displayed drawing row is ghosting',
      );

      hideFolder(s, folder);

      expect(
        s.displayedLayersOnionSkinEnabled,
        isFalse,
        reason:
            '"every DISPLAYED layer" cannot include one the user cannot see. '
            'The button read ON because of a row inside a folder that was off.',
      );
    });
  });

  group('visibility solo', () {
    test('soloing a row inside a folder leaves its folder ON — otherwise it '
        'hides the very row it is soloing', () {
      final (s, member, folder) = sessionWithFolder();

      s.toggleLayerVisibilitySolo();

      final stack = s.activeCutOrNull!.layers;
      expect(
        stack.byId(member)!.isVisible,
        isTrue,
        reason: 'the soloed row itself, obviously',
      );
      expect(
        stack.byId(folder)!.isVisible,
        isTrue,
        reason:
            'Solo turned every OTHER row off, and the row\'s own folder is an '
            '"other row". On the editing canvas that read as "nothing '
            'happened"; through the composite it came out EMPTY.',
      );
      expect(
        stack.rowVisible(stack.byId(member)!),
        isTrue,
        reason: 'and this is the question the composite actually asks',
      );
    });

    test('leaving solo restores the folder too', () {
      final (s, member, folder) = sessionWithFolder();
      s.toggleLayerVisibilitySolo();
      s.toggleLayerVisibilitySolo();

      final stack = s.activeCutOrNull!.layers;
      expect(stack.byId(folder)!.isVisible, isTrue);
      expect(stack.byId(member)!.isVisible, isTrue);
    });
  });

  group('the row you are standing on', () {
    test('takes no strokes when its FOLDER is hidden', () {
      final (s, member, folder) = sessionWithFolder();
      expect(
        s.activeBrushEditorSelection,
        isNotNull,
        reason: 'the CONTROL — a visible row is drawable',
      );

      hideFolder(s, folder);

      expect(
        s.activeBrushEditorSelection,
        isNull,
        reason:
            'R4 #1 refuses a hidden row because you would be drawing into '
            'something the canvas does not show. That reason is the same one '
            'folder up (유저 2026-08-13: 「숨긴 폴더는 안에 있는 레이어들도 '
            '숨김상태인거일거잖아. 그러면 브러시 막는거지」).',
      );
    });

    test('is not drawn on the editing canvas either — even with nothing '
        'exposed at this frame', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      // A row with NO cel at this frame is the one that takes the hand-built
      // fallback path instead of the composite tree — the path that skipped
      // the folder walk.
      s.addLayer();
      s.groupActiveLayerIntoFolder();
      final folder = s.activeCutOrNull!.layers.folderLayers.single.id;

      bool holdsActive(List<CanvasLayerStackNode> nodes) => nodes.any(
        (node) =>
            node is CanvasActiveLayerNode ||
            (node is CanvasLayerGroupNode && holdsActive(node.children)),
      );

      expect(
        holdsActive(s.editingCanvasStack.nodes),
        isTrue,
        reason: 'the CONTROL — the live surface needs a slot to draw into',
      );

      if (s.activeCutOrNull!.layers.byId(folder)!.isVisible) {
        s.toggleLayerVisibility(folder);
      }

      expect(
        holdsActive(s.editingCanvasStack.nodes),
        isFalse,
        reason:
            'A row WITH a cel is dropped by the tree walk, which honours the '
            'folder chain. A row with nothing exposed was appended by hand '
            'AFTER that walk, so it went on painting out of a folder the user '
            'had switched off — visible on the editing canvas and nowhere '
            'else, which is the worst shape a difference can take.',
      );
    });
  });

  group('the standalone draw (ruler scrub)', () {
    test('the active row carries its FOLDER\'s opacity too', () {
      final (s, member, folder) = sessionWithFolder();
      s.setLayerOpacity(layerId: folder, opacity: 0.5);

      expect(
        s.editingCanvasStack.activeLayerOpacity,
        closeTo(0.5, 1e-9),
        reason:
            'During a ruler scrub the interactive view draws the active row '
            'ALONE — no folder node stands above it — so this value has to '
            'be the whole chain. It stopped at the row\'s own opacity, so a '
            'row inside a half-opacity folder scrubbed at full strength '
            'while every other row honoured the folder.',
      );
    });

    test('and still multiplies its own', () {
      final (s, member, folder) = sessionWithFolder();
      s.setLayerOpacity(layerId: folder, opacity: 0.5);
      s.setLayerOpacity(layerId: member, opacity: 0.4);

      expect(s.editingCanvasStack.activeLayerOpacity, closeTo(0.2, 1e-9));
    });
  });

  group('cel export', () {
    test('a row inside a hidden folder does not export', () {
      final (s, member, folder) = sessionWithFolder();
      const spec = CelsExportSpec();

      final before = resolveExportCelsSelection(
        cut: s.activeCutOrNull!,
        spec: spec,
      );
      expect(
        before.celLayers.map((layer) => layer.id),
        contains(member),
        reason: 'the CONTROL — a visible drawing row exports',
      );

      hideFolder(s, folder);

      final after = resolveExportCelsSelection(
        cut: s.activeCutOrNull!,
        spec: spec,
      );
      expect(
        after.celLayers.map((layer) => layer.id),
        isNot(contains(member)),
        reason:
            'The eye means "not in this render" everywhere else. Cel export '
            'wrote files for rows the user had switched off by hiding the '
            'folder they live in.',
      );
    });
  });

  group('the law itself', () {
    test('"is this row shown" is asked in ONE place, and the number of '
        'places that re-derive it only goes down', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = entity.path.replaceAll(r'\', '/');
        if (_mayAnswerVisibilityItself.containsKey(path)) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          final line = lines[i];
          // A WRITE (`isVisible:` in a copyWith, `isVisible ==` in a guard)
          // is not the offence — re-deriving the ANSWER is.
          if (!line.contains('.isVisible') ||
              line.contains('isVisible:') ||
              line.contains('isVisible ==') ||
              line.contains('isVisible !=') ||
              line.contains('this.isVisible')) {
            continue;
          }
          offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }

      // A RATCHET, in the shape `app_shapes_coverage_test` already uses here.
      // The remaining reads are known and listed in the round's plan; each
      // one is a place that answers "is this row shown" for itself and can
      // therefore disagree with the composite. The number may only go DOWN —
      // a new one fails immediately, and every batch that converts a few
      // lowers the bound. At zero this becomes `expect(offenders, isEmpty)`.
      expect(
        offenders.length,
        lessThanOrEqualTo(_knownOffenders),
        reason:
            'Something new answers "is this row shown" for itself. Ask '
            '`layers.rowVisible(layer)` instead — the row\'s own eye is only '
            'half the question, and the half that was missing is how a '
            'hidden folder kept drawing, ghosting and exporting its members.\n'
            '${offenders.join('\n')}',
      );
    });
  });
}

/// Files that are ALLOWED to read the raw flag, with the reason.
const _mayAnswerVisibilityItself = <String, String>{
  'lib/src/models/layer.dart': 'the stored field itself',
  'lib/src/models/layer_folder.dart': 'the predicate\'s implementation',
  'lib/src/services/cut_frame_composite_plan.dart':
      'THE definition — the composite walk is what "shown" means, and every '
      'other caller is supposed to agree with this file',
  'lib/src/controllers/layer_controller.dart': 'the WRITE side (the toggle)',
};

/// How many raw reads remained when this contract was written.
///
/// The round that added it converted six: the onion ghosts, the onion sweep,
/// the solo, cel export, the brush gate, and the editing canvas's own
/// hand-built node for a row with nothing exposed.
///
/// What is left, and why each is still here rather than fixed: the SE
/// name-tag plan, the stroke painter, the colour sampler, the thumbnail
/// store's cache key, the timeline grid, a dead export function, the camera
/// backdrop, `activeLayerOpacity`'s pair (being deleted), and the visibility
/// solo's SNAPSHOT — that last one reads the raw flag on purpose, because
/// what it saves and restores IS the raw flag.
///
/// ⚠️Only ever lower this. Raising it is the change this test exists to stop.
const _knownOffenders = 11;
