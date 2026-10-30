import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart' show offsetAlong;
import 'package:anicel/src/ui/timeline/berth_row.dart';
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show laneGraphHeadedBy;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerVisibilityToggleButton;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show PropertyLaneRow;
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowDragState, LayerRowSubject, TimelineRowDragHooks;
import 'package:anicel/src/ui/timeline/rail_eyes.dart' show RailEyeBuilder;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/named.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/reference_to.dart';

/// 🚨I-57 ㉣ (10-13): a cut switch hands each berth's row to the next cut's
/// layer at its place, and a row whose FACE is the face it showed comes
/// back WHOLE — the very widget built for the old cut's layer ([BerthRow]).
/// Every verb such a row carries must act on the layer it stands for NOW:
/// this switches between two cuts of the same faces, holds that the rows
/// came back whole, then presses every control of a row on both grids and
/// reads which layer each verb gave the host — and what the row SHOWS of
/// the layer that is not its face (the eye, a drag's preview) is the new
/// layer's too.
///
/// The session-wired half (every control's EFFECT, on both grids, across a
/// cut) is `non_active_layer_controls_test.dart`'s; this is every verb.
void main() {
  for (final orientation in TimelineOrientation.values) {
    final rail = orientation == TimelineOrientation.horizontal
        ? 'timeline'
        : 'xsheet';
    group('$rail: after a switch onto a cut of the same faces', () {
      late List<String> heard;
      late TimelineRowDragHooks drags;

      /// Pumps the first cut, switches to the second — with [listening]
      /// hearing what the switch builds — and holds that every row came
      /// back whole.
      Future<void> crossed(
        WidgetTester tester, {
        _RowRebuilds? listening,
      }) async {
        heard = [];
        drags = _dragsHeardBy(heard);
        await tester.binding.setSurfaceSize(const Size(1600, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_panel(_one, orientation, heard, drags));
        await tester.pumpAndSettle();
        List<Widget> rows() =>
            tester.widgetList(find.byType(TimelineLayerControlsRow)).toList();
        final before = rows();
        expect(
          before,
          hasLength(_layersOf(_one).length),
          reason: 'LIVENESS: every row stands',
        );

        listening?.listen();
        try {
          await tester.pumpWidget(_panel(_two, orientation, heard, drags));
          await tester.pumpAndSettle();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }

        expect(
          find.named('$rail-layer-row-${_two.draw}'),
          findsOneWidget,
          reason: 'LIVENESS: the rows stand for the second cut',
        );
        expect(
          rows(),
          orderedEquals(before),
          reason: 'every row of the second cut has the face the first cut\'s '
              'row had — a berth hands it back whole',
        );
        heard.clear();
      }

      Future<void> tapNamed(WidgetTester tester, String name) async {
        await tester.tap(find.named(name));
        await tester.pumpAndSettle();
      }

      Future<void> pick(WidgetTester tester, String opener, String key) async {
        await tapNamed(tester, opener);
        await tester.tap(find.byKey(ValueKey<String>(key)));
        await tester.pumpAndSettle();
      }

      final presses = <String, (Future<void> Function(WidgetTester), String)>{
        'the row itself': (
          (tester) async {
            await tester.tap(find.named('$rail-layer-name-${_two.draw}'));
            await tester.pump(const Duration(milliseconds: 700));
          },
          'select ${_two.draw}',
        ),
        'the type button': (
          (tester) => tapNamed(tester, '$rail-layer-type-button-${_two.draw}'),
          'select ${_two.draw}',
        ),
        // The row's drag is put on it by a wrapper of its own, kept apart
        // from the row ([KeptLayerControlsRows]).
        'the row\'s drag': (
          (tester) async {
            await tester.drag(
              find.named('$rail-layer-name-${_two.draw}'),
              offsetAlong(orientation.axis, along: 0, across: -40),
            );
            await tester.pumpAndSettle();
          },
          'drag ${_two.draw}',
        ),
        'the label\'s double click': (
          (tester) async {
            final label = tester.getCenter(
              find.named('$rail-layer-name-${_two.draw}'),
            );
            await tester.tapAt(label, kind: PointerDeviceKind.stylus);
            await tester.pump(const Duration(milliseconds: 60));
            await tester.tapAt(label, kind: PointerDeviceKind.stylus);
            await tester.pump(const Duration(milliseconds: 700));
          },
          'rename ${_two.draw}',
        ),
        'the eye': (
          (tester) => tapNamed(tester, '$rail-layer-visibility-${_two.draw}'),
          'eye ${_two.draw}',
        ),
        'the opacity slider': (
          (tester) async {
            await tester.drag(
              find.named('$rail-layer-opacity-${_two.draw}'),
              // Toward empty: the rail's runs along the row; the sheet's,
              // turned with its header, up the column — two ways, not one
              // turned.
              const {
                TimelineOrientation.horizontal: Offset(-30, 0),
                TimelineOrientation.vertical: Offset(0, 30),
              }[orientation]!,
            );
            await tester.pumpAndSettle();
          },
          'opacity-end ${_two.draw}',
        ),
        'the timesheet toggle': (
          (tester) => tapNamed(tester, '$rail-layer-timesheet-${_two.draw}'),
          'sheet ${_two.draw}',
        ),
        'the colour mark': (
          (tester) => pick(
            tester,
            '$rail-layer-mark-${_two.draw}',
            'layer-mark-option-paper',
          ),
          'mark ${_two.draw}',
        ),
        'the take': (
          (tester) => pick(
            tester,
            '$rail-layer-take-${_two.draw}',
            'layer-take-option-2',
          ),
          'mark ${_two.draw}',
        ),
        'the fx switch': (
          (tester) => tapNamed(tester, '$rail-layer-fx-${_two.draw}'),
          'fx ${_two.draw}',
        ),
        'the onion toggle': (
          (tester) => tapNamed(tester, '$rail-layer-onion-${_two.draw}'),
          'onion ${_two.draw}',
        ),
        'the clip toggle': (
          (tester) =>
              tapNamed(tester, '$rail-layer-clip-${_two.draw}'),
          'fill ${_two.draw}',
        ),
        'the blend chip': (
          (tester) => pick(
            tester,
            '$rail-layer-blend-${_two.draw}',
            '$rail-layer-blend-option-multiply',
          ),
          'blend ${_two.draw}',
        ),
        'the link badge': (
          (tester) => tapNamed(tester, '$rail-layer-link-badge-${_two.draw}'),
          'links ${_two.draw}',
        ),
        'the reference button': (
          (tester) => tapNamed(tester, '$rail-layer-reference-${_two.ref}'),
          'reference ${_two.ref}',
        ),
        'the speaker': (
          (tester) => tapNamed(tester, '$rail-layer-mute-${_two.sound}'),
          'mixer ${_two.sound}',
        ),
        'the camera\'s graph button': (
          (tester) => tapNamed(tester, '$rail-layer-graph-${_two.camera}'),
          'graph ${laneGraphHeadedBy(_layerNamed(_two, 'Camera'), null)}',
        ),
        'the folder\'s twirl': (
          (tester) => tapNamed(tester, '$rail-folder-twirl-${_two.folder}'),
          'fold ${_two.folder}',
        ),
        'the attach base\'s twirl': (
          (tester) => tapNamed(tester, '$rail-attach-twirl-${_two.base}'),
          'attach ${_two.base}',
        ),
        'the lane twirl': (
          (tester) => tapNamed(tester, '$rail-lane-toggle-${_two.draw}'),
          'lanes ${_two.draw}',
        ),
      };

      for (final MapEntry(key: control, value: (press, expected))
          in presses.entries) {
        testWidgets('$control acts on the layer the row stands for now', (
          tester,
        ) async {
          await crossed(tester);

          await press(tester);

          expect(
            heard,
            contains(expected),
            reason: 'a kept row\'s verb went to the layer it was BUILT for',
          );
          expect(
            heard.where((verb) => verb.endsWith('-1')),
            isEmpty,
            reason: 'nothing reached the first cut\'s layers',
          );
        });
      }

      testWidgets('every name a row spells with its layer ENDS with the '
          'layer\'s id — how a finder reads a kept row\'s names', (
        tester,
      ) async {
        await crossed(tester);

        var spelled = 0;
        for (final row in find.byType(TimelineLayerControlsRow).evaluate()) {
          final builtFor =
              (row.widget as TimelineLayerControlsRow).layer.id.value;
          void visit(Element element) {
            // Both ways a widget wears a name, as the finder reads them
            // ([nameOf]): a [Named] over it, or its own ([NamesItself]).
            final name = switch (element.widget) {
              Named(:final name) => name,
              NamesItself(:final name) => name,
              _ => null,
            };
            if (name != null && name.contains(builtFor)) {
              spelled += 1;
              expect(
                name,
                endsWith('-$builtFor'),
                reason: 'a kept row\'s name is read as the row stands by '
                    'the id that ENDS it; one spelled with the id inside '
                    'names the old cut\'s layer once a switch keeps the row',
              );
            }
            element.visitChildren(visit);
          }

          row.visitChildren(visit);
        }
        expect(
          spelled,
          greaterThan(_layersOf(_one).length * 3),
          reason: 'LIVENESS: the rows\' names were read',
        );
      });

      testWidgets('the eye shows the layer the row stands for now', (
        tester,
      ) async {
        await crossed(tester);

        bool eyeOn() => tester
            .widget<LayerVisibilityToggleButton>(
              find.ancestor(
                of: find.named('$rail-layer-visibility-${_two.draw}'),
                matching: find.byType(LayerVisibilityToggleButton),
              ),
            )
            .isVisible;
        expect(
          eyeOn(),
          isFalse,
          reason: 'the second cut\'s drawing is hidden, the first\'s was not',
        );
      });

      testWidgets('two rows of one face that trade layers across a switch '
          'each show the eye of the layer they stand for now', (
        tester,
      ) async {
        heard = [];
        drags = _dragsHeardBy(heard);
        await tester.binding.setSurfaceSize(const Size(1600, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        // One face — the eye is not part of it — the first shown, the
        // second hidden, in both cuts (linked cuts share their layers).
        // Trading places changes no layer's eye, so nothing but the berths
        // says which eye a row shows now. Across worlds a row takes the
        // berth at its place; within one it would follow its layer.
        final shown = _row('twin-a', 'Twin', LayerKind.animation);
        final hidden = _row(
          'twin-b',
          'Twin',
          LayerKind.animation,
        ).copyWith(isVisible: false);
        List<Widget> rows() =>
            tester.widgetList(find.byType(TimelineLayerControlsRow)).toList();
        List<bool> eyes() => [
          for (final eye in tester.widgetList<LayerVisibilityToggleButton>(
            find.byType(LayerVisibilityToggleButton),
          ))
            eye.isVisible,
        ];
        await tester.pumpWidget(
          _panel(_one, orientation, heard, drags, layers: [shown, hidden]),
        );
        await tester.pumpAndSettle();
        final before = rows();
        final eyesBefore = eyes();
        expect(
          eyesBefore,
          unorderedEquals([true, false]),
          reason: 'LIVENESS: each row shows its own layer\'s eye',
        );

        await tester.pumpWidget(
          _panel(_two, orientation, heard, drags, layers: [hidden, shown]),
        );
        await tester.pumpAndSettle();

        expect(
          rows(),
          orderedEquals(before),
          reason: 'premise: one face, so each berth hands its row back whole',
        );
        expect(
          eyes(),
          eyesBefore.reversed,
          reason: 'each place now stands for the other layer',
        );
      });

      testWidgets('a drag\'s opacity preview shows on the row standing for '
          'the layer it drags', (tester) async {
        await crossed(tester);
        _preview.value = (layerIds: {LayerId(_two.draw)}, opacity: 0.25);
        addTearDown(() => _preview.value = null);
        await tester.pump();

        expect(
          tester
              .widget<FieldSlider>(
                find.named('$rail-layer-opacity-${_two.draw}'),
              )
              .value,
          0.25,
        );
      });

      // What the hand-back saves, measured on the user's project: 1576 →
      // 855 widgets built per crossing (I-57 ㉣) — held here by the rows'
      // own count, not by the clock.
      testWidgets('the switch builds nothing again inside a kept row but '
          'an eye the new layer changed', (tester) async {
        final rebuilt = _RowRebuilds();
        await crossed(tester, listening: rebuilt);

        expect(
          rebuilt.berths,
          greaterThanOrEqualTo(_layersOf(_one).length),
          reason: 'LIVENESS: every berth was handed the next cut\'s layer',
        );
        expect(
          rebuilt.inRows[_two.draw],
          contains(LayerVisibilityToggleButton),
          reason: 'the drawing\'s eye changed, and shows it',
        );
        for (final MapEntry(key: row, value: types)
            in rebuilt.inRows.entries) {
          if (row != _two.draw) {
            expect(
              types.difference({RailEyeBuilder}),
              isEmpty,
              reason: '$row shows what the row it was built for showed',
            );
          }
        }
      });

      testWidgets('a pass that changes no row builds nothing in the rows', (
        tester,
      ) async {
        await crossed(tester);
        final rebuilt = _RowRebuilds()..listen();
        try {
          await tester.pumpWidget(_panel(_two, orientation, heard, drags));
          await tester.pump();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }

        expect(
          rebuilt.berths,
          greaterThanOrEqualTo(_layersOf(_two).length),
          reason: 'LIVENESS: the berths were handed their rows again',
        );
        expect(rebuilt.inRows, isEmpty);
      });
    });
  }
}

/// One cut's rows: the same faces in both cuts, other layers.
typedef _Cut = ({
  String world,
  String draw,
  String ref,
  String base,
  String rider,
  String folder,
  String inside,
  String sound,
  String camera,
});

const _one = (
  world: 'world-1',
  draw: 'draw-1',
  ref: 'ref-1',
  base: 'base-1',
  rider: 'rider-1',
  folder: 'folder-1',
  inside: 'inside-1',
  sound: 'sound-1',
  camera: 'camera-1',
);

const _two = (
  world: 'world-2',
  draw: 'draw-2',
  ref: 'ref-2',
  base: 'base-2',
  rider: 'rider-2',
  folder: 'folder-2',
  inside: 'inside-2',
  sound: 'sound-2',
  camera: 'camera-2',
);

List<Layer> _layersOf(_Cut cut) => [
  _row(cut.camera, 'Camera', LayerKind.camera),
  _row(cut.sound, 'Sound', LayerKind.se),
  _row(cut.folder, 'Folder', LayerKind.folder),
  _row(
    cut.inside,
    'Inside',
    LayerKind.animation,
  ).copyWith(folderId: LayerId(cut.folder)),
  _row(cut.base, 'Base', LayerKind.animation),
  _row(cut.rider, 'Rider', LayerKind.animation).copyWith(
    attachedToLayerId: LayerId(cut.base),
    attachedPlacement: AttachedPlacement.above,
  ),
  _row(
    cut.ref,
    'Ref',
    LayerKind.animation,
  ).copyWith(mediaReference: referenceTo('/clips/a.mp4')),
  // The second cut's drawing is hidden: the eye is not the row's face, so
  // the row comes back whole and its eye must read the new layer's.
  _row(
    cut.draw,
    'Draw',
    LayerKind.animation,
  ).copyWith(isVisible: cut == _one),
];

Layer _row(String id, String name, LayerKind kind) =>
    Layer(id: LayerId(id), name: name, frames: const [], kind: kind);

Layer _layerNamed(_Cut cut, String name) =>
    _layersOf(cut).firstWhere((layer) => layer.name == name);

const _drawLanes = [
  PropertyLaneRow(laneId: 'position', label: 'Position', keyMarks: {}),
];

final _cursor = ValueNotifier<int>(0);
final _preview =
    ValueNotifier<({Set<LayerId> layerIds, double opacity})?>(null);

/// Row drags that say which layer a drag picked up — ONE set for both
/// cuts, as a host binds its own once (F-244): a drag wrapper is kept
/// while its hooks are the same.
TimelineRowDragHooks _dragsHeardBy(List<String> heard) => TimelineRowDragHooks(
  drag: ValueNotifier<LayerRowDragState?>(null),
  onBegin: (subject) {
    if (subject case LayerRowSubject(:final layerId)) {
      heard.add('drag ${layerId.value}');
    }
  },
  onUpdate: (_, _, {pointerInRow}) {},
  onRowTarget: (_, _, _) {},
  onEffectUpdate: (_, _, _) {},
  onEnd: () {},
  onCancel: () {},
  isInRowSelection: (_) => true,
);

/// What a pass built again as the rows see it: the widget types built
/// INSIDE each controls row, by the layer the row stands for — and how
/// many berths ([BerthRow]) were handed a row, so that nothing built is a
/// count that looked.
final class _RowRebuilds {
  final Map<String, Set<Type>> inRows = {};
  int berths = 0;

  void listen() {
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is BerthRow) {
        berths += 1;
      }
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget case TimelineLayerControlsRow(:final layer)) {
          final standsFor = BerthRow.at(ancestor)?.id ?? layer.id;
          inRows
              .putIfAbsent(standsFor.value, () => {})
              .add(element.widget.runtimeType);
          return false;
        }
        return true;
      });
    };
  }
}

Widget _panel(
  _Cut cut,
  TimelineOrientation orientation,
  List<String> heard,
  TimelineRowDragHooks drags, {
  List<Layer>? layers,
}) {
  void hear(String verb, LayerId id) => heard.add('$verb ${id.value}');
  return MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers ?? _layersOf(cut),
        rowDragHooks: drags,
        activeLayerId: LayerId(cut.base),
        substrateGeneration: cut.world,
        frameCursor: _cursor,
        playbackFrameCount: 12,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (id) => hear('select', id),
        labelDoubleClick: (id) => () => hear('rename', id),
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (id) => hear('eye', id),
        onLayerOpacityChanged: (id, _) => hear('opacity', id),
        onLayerOpacityChangeEnd: (id, _) => hear('opacity-end', id),
        opacityDragPreview: _preview,
        onToggleLayerTimesheet: (id) => hear('sheet', id),
        onLayerMarkSelected: (id, _) => hear('mark', id),
        layerFxStateOf: (_) => LayerFxState.on,
        onToggleLayerFx: (id) => hear('fx', id),
        layerOnionSkinEnabledOf: (_) => false,
        onToggleLayerOnionSkin: (id) => hear('onion', id),
        onToggleLayerClip: (id) => hear('fill', id),
        onLayerBlendModeSelected: (id, _) => hear('blend', id),
        layerLinkPartnersOf: (id) =>
            id.value.startsWith('draw') ? const ['Elsewhere'] : const [],
        onOpenLayerLinks: (_, id) async => hear('links', id),
        onOpenLayerReference: (_, id) async => hear('reference', id),
        isLayerSoloed: (_) => false,
        onOpenLayerMixer: (_, id) => hear('mixer', id),
        laneGraphVerbs: (
          toggle: (key) => heard.add('graph $key'),
          togglePin: (_) {},
          plot: (_, _) {},
          resize: (_, _) {},
          enlarge: (_) {},
          pen: (_) {},
          transformBox: (_) {},
          snap: (_) {},
        ),
        onToggleLayerCollapsed: (id) => hear('fold', id),
        onToggleAttachGroup: (id) => hear('attach', id),
        // The drawing carries a lane in both cuts, so its row wears the
        // lane twirl and still comes back whole.
        lanesForLayer: (layer) => layer.name == 'Draw' ? _drawLanes : const [],
        onToggleLayerLanes: (id) => hear('lanes', id),
        orientation: orientation,
        onOrientationChanged: (_) {},
      ),
    ),
  );
}
