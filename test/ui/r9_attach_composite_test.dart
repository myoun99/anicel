import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

/// R9 — the attach family authors no composite of its own.
///
/// An attach ROW already wore its base's fx. The 공정 ORGANIZER folder did
/// not, and its fx switch WORKED: the folder's own pose gated the group and
/// its effects forced a composite buffer. That is a second answer competing
/// with the base's, on a row whose entire job is to follow it — so the user
/// took it away ("어태치폴더는 우선 fx를 갖지않음... 주인레이어 따라가야
/// 하기때문"), lanes included.
///
/// The blend stays. That was the user's own second thought once they saw
/// the whole picture ("그냥 블렌드 두는게 나을수도있단생각 들기시작했어").
void main() {
  Layer base() => Layer(
    id: const LayerId('base'),
    name: 'A',
    frames: const [],
  );

  Layer attachRow({LayerId? folderId}) => Layer(
    id: const LayerId('attach'),
    name: 'A+1',
    frames: const [],
    attachedToLayerId: const LayerId('base'),
    attachedPlacement: AttachedPlacement.above,
    folderId: folderId,
  );

  group('the predicate is a LAYER question, not a kind one', () {
    test('an attach ROW and its organizer FOLDER both wear the base', () {
      final organizer = createFolderLayer(
        id: const LayerId('proc'),
        name: '[연출]',
      );
      final layers = [base(), attachRow(folderId: organizer.id), organizer];

      expect(attachRowWearsBaseComposite(layers[1], layers), isTrue);
      expect(
        attachRowWearsBaseComposite(organizer, layers),
        isTrue,
        reason: 'the folder holds attach rows of ONE base — it follows it too',
      );
      expect(
        attachRowWearsBaseComposite(layers.first, layers),
        isFalse,
        reason: 'the base itself authors its own composite',
      );
    });

    test('an ORDINARY folder is untouched — the kind cannot tell them apart',
        () {
      final folder = createFolderLayer(
        id: const LayerId('plain'),
        name: 'Folder',
      );
      final member = Layer(
        id: const LayerId('m'),
        name: 'M',
        frames: const [],
        folderId: folder.id,
      );

      expect(
        attachRowWearsBaseComposite(folder, [folder, member]),
        isFalse,
        reason: 'this is exactly why the question could not live on the kind',
      );
    });

    test('an EMPTY folder is not an organizer', () {
      final folder = createFolderLayer(
        id: const LayerId('empty'),
        name: 'Folder',
      );
      expect(attachRowWearsBaseComposite(folder, [folder]), isFalse);
    });
  });

  group('the rail row hides the fx switch for them', () {
    Widget row({required Layer layer, required bool wears}) => MaterialApp(
      home: Material(
        child: TimelineLayerControlsRow(
          layer: layer,
          wearsBaseComposite: wears,
          active: false,
          metrics: TimelineGridMetrics.defaults,
          onSelectLayer: (_) {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          onToggleLayerFx: (_) {},
          onLayerBlendModeSelected: (_, _) {},
        ),
      ),
    );

    testWidgets('no fx button, but the BLEND control stays', (tester) async {
      final organizer = createFolderLayer(
        id: const LayerId('proc'),
        name: '[연출]',
      );

      await tester.pumpWidget(row(layer: organizer, wears: false));
      expect(
        find.byKey(const ValueKey<String>('timeline-layer-fx-proc')),
        findsOneWidget,
        reason: 'the premise: an ordinary folder still has one',
      );

      await tester.pumpWidget(row(layer: organizer, wears: true));
      expect(
        find.byKey(const ValueKey<String>('timeline-layer-fx-proc')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-layer-blend-proc')),
        findsOneWidget,
        reason: 'blend is display control, and the organizer keeps it',
      );
      expect(
        layerKindShowsBlendControl(LayerKind.folder),
        isTrue,
        reason: 'the kind-level answer is unchanged — only the fx narrowed',
      );
    });
  });
}
