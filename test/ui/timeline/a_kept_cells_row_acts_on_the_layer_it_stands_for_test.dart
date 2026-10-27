import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show offsetAlong, partAcross, startAlong;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';
import 'package:anicel/src/ui/widgets/named.dart';

import '../../helpers/named_finders.dart';

/// 🚨I-57 (10-13): a cut switch hands each berth's CELLS row to the next
/// cut's layer at its place, and a row of the same SHAPE comes back whole —
/// the very widget built for the old cut's layer — with what it draws handed
/// down past it ([BerthRow.shows]). Every verb such a row carries must act
/// on the layer it stands for NOW, every picture must draw that layer in the
/// cut it stands in, and nothing but the pictures may be built again: this
/// switches between two cuts of the same shapes, holds that the rows came
/// back whole, then presses every verb of a row on both grids and reads
/// which layer each gave the host.
///
/// The rail's rows are `a_kept_row_acts_on_the_layer_it_stands_for_test`'s.
void main() {
  for (final orientation in TimelineOrientation.values) {
    final horizontal = orientation == TimelineOrientation.horizontal;
    final grid = horizontal ? 'timeline' : 'xsheet';
    final along = horizontal ? 'row' : 'column';
    group('$grid: after a switch onto a cut of the same shapes', () {
      late List<String> heard;
      late _Hooks hooks;

      tearDown(() => _preview.value = null);

      /// Pumps the first cut, switches to the second — with [listening]
      /// hearing what the switch builds — and holds that every row came
      /// back whole.
      Future<void> crossed(
        WidgetTester tester, {
        _RowRebuilds? listening,
      }) async {
        heard = [];
        hooks = _hooksHeardBy(heard);
        await tester.binding.setSurfaceSize(const Size(1600, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_panel(_one, orientation, heard, hooks));
        await tester.pumpAndSettle();
        List<Widget> rows() =>
            tester.widgetList(find.byType(TimelineFrameCellsRow)).toList();
        final before = rows();
        expect(
          before,
          hasLength(_layers[_one]!.length),
          reason: 'LIVENESS: every row stands',
        );

        listening?.listen();
        try {
          await tester.pumpWidget(_panel(_two, orientation, heard, hooks));
          await tester.pumpAndSettle();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }

        expect(
          find.named('$grid-frame-$along-area-${_two.draw}'),
          findsOneWidget,
          reason: 'LIVENESS: the rows stand for the second cut',
        );
        expect(
          rows(),
          orderedEquals(before),
          reason: 'every row of the second cut has the shape the first '
              'cut\'s row had — a berth hands it back whole',
        );
        heard.clear();
      }

      /// The middle of [frame]'s cell on [layerId]'s row, on screen.
      Offset cellOf(WidgetTester tester, String layerId, int frame) {
        final strip = find.named('$grid-row-cells-$layerId');
        final painter = tester.widget<CustomPaint>(strip).painter!
            as TimelineRowCellsPainter;
        final frames = painter.geometry.value;
        final main = (frames.edgeAt(frame) + frames.edgeAt(frame + 1)) / 2;
        final box = tester.getRect(strip);
        final axis = orientation.axis;
        return offsetAlong(
          axis,
          along: startAlong(axis, box) + main,
          across: partAcross(axis, box.center),
        );
      }

      /// Two cells further along the frame axis.
      Offset twoCells(WidgetTester tester, String layerId) =>
          cellOf(tester, layerId, 3) - cellOf(tester, layerId, 1);

      /// Holds the file over [at] — a cell of [target], which spans the
      /// row's frames and so stands mostly outside the window a row lays
      /// out — and lets it go.
      Future<void> dropFileOn(
        WidgetTester tester,
        Finder target,
        Offset at,
      ) async {
        expect(target, findsOneWidget, reason: 'LIVENESS: the row takes it');
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_fileKey)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveTo(at);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      final presses = <String, (Future<void> Function(WidgetTester), String)>{
        'a press on a cell': (
          (tester) async {
            await tester.tapAt(
              cellOf(tester, _two.draw, 1),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
          },
          'select ${_two.draw}',
        ),
        'a double tap on a cell': (
          (tester) async {
            final cell = cellOf(tester, _two.draw, 1);
            await tester.tapAt(cell, kind: PointerDeviceKind.mouse);
            await tester.pump(const Duration(milliseconds: 60));
            await tester.tapAt(cell, kind: PointerDeviceKind.mouse);
            await tester.pump(const Duration(milliseconds: 700));
          },
          'activate ${_two.draw}',
        ),
        'a drag across the cells': (
          (tester) async {
            await tester.dragFrom(
              cellOf(tester, _two.plain, 1),
              twoCells(tester, _two.plain),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
          },
          'range ${_two.plain}',
        ),
        'a drag inside the selection': (
          (tester) async {
            hooks.selection.value = TimelineFrameRangeSelection(
              layerId: LayerId(_two.plain),
              startIndex: 0,
              endIndexExclusive: 3,
            );
            await tester.pump();
            await tester.dragFrom(
              cellOf(tester, _two.plain, 1),
              twoCells(tester, _two.plain),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
          },
          'move ${_two.plain}',
        ),
        'a block\'s end grip': (
          (tester) async {
            final chrome = find.named('$grid-edit-chrome-${_two.draw}');
            final painter = tester.widget<CustomPaint>(chrome).painter!
                as TimelineRowEditChromePainter;
            final grip = painter.model.targets
                .whereType<TimelineRowGripTarget>()
                .firstWhere((grip) => grip.edge == TimelineBlockEdge.end);
            await tester.dragFrom(
              tester.getTopLeft(chrome) + grip.rect.center,
              twoCells(tester, _two.draw),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
          },
          'grip ${_two.draw}',
        ),
        'a file let go on the row': (
          (tester) => dropFileOn(
            tester,
            find.named('$grid-layer-asset-drop-${_two.draw}'),
            cellOf(tester, _two.draw, 1),
          ),
          'drop ${_two.draw}',
        ),
        'a file let go on a sound row\'s empty cells': (
          (tester) => dropFileOn(
            tester,
            find.named('$grid-se-cell-drop-${_two.sound}-3'),
            cellOf(tester, _two.sound, 4),
          ),
          'drop ${_two.sound}',
        ),
      };

      for (final MapEntry(key: verb, value: (press, expected))
          in presses.entries) {
        testWidgets('$verb acts on the layer the row stands for now', (
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

      testWidgets('every picture draws the layer the row stands for, in the '
          'cut it stands in', (tester) async {
        await crossed(tester);

        final pictures = [
          for (final paint in tester.widgetList<CustomPaint>(
            find.byType(CustomPaint),
          ))
            if (paint.painter case final TimelineRowCellsPainter painter)
              painter,
        ];
        expect(
          {for (final picture in pictures) picture.layer},
          _layers[_two]!.toSet(),
          reason: 'each row draws the second cut\'s layer, as it holds it',
        );
        expect(
          {for (final picture in pictures) picture.substrateGeneration},
          {_two.world},
          reason: 'and bakes its tiles for the second cut\'s world',
        );
      });

      testWidgets('every name a row spells with the layer it was built for '
          'ENDS with the layer\'s id — how a finder reads a kept row\'s '
          'names', (tester) async {
        await crossed(tester);

        var spelled = 0;
        for (final row in find.byType(TimelineFrameCellsRow).evaluate()) {
          final builtFor =
              (row.widget as TimelineFrameCellsRow).layer.id.value;
          void visit(Element element) {
            if (element.widget case Named(name: final name?)
                when name.contains(builtFor)) {
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
          greaterThanOrEqualTo(_layers[_one]!.length * 2),
          reason: 'LIVENESS: the rows\' names were read',
        );
      });

      // What the hand-back saves, held by the rows' own count, not by the
      // clock.
      testWidgets('the switch builds again only the pieces that draw the '
          'layer', (tester) async {
        final rebuilt = _RowRebuilds();
        await crossed(tester, listening: rebuilt);

        expect(
          rebuilt.pictures,
          greaterThanOrEqualTo(_layers[_one]!.length),
          reason: 'LIVENESS: every row drew the next cut\'s layer',
        );
        expect(
          rebuilt.outsideThePictures,
          isEmpty,
          reason: 'a kept row builds again only what draws what it shows',
        );
      });

      testWidgets('a pass that changes nothing builds nothing in the rows', (
        tester,
      ) async {
        await crossed(tester);
        final rebuilt = _RowRebuilds()..listen();
        try {
          await tester.pumpWidget(_panel(_two, orientation, heard, hooks));
          await tester.pump();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }

        expect(rebuilt.pictures, 0);
        expect(rebuilt.outsideThePictures, isEmpty);
      });

      testWidgets('a drag\'s preview shows on the row standing for the layer '
          'it drags', (tester) async {
        await crossed(tester);
        final drawn = _layers[_two]!.firstWhere(
          (layer) => layer.id.value == _two.draw,
        );
        final previewed = drawn.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f'), length: 9),
          },
        );
        _preview.value = ExposureEdgeDragPreview(previewLayer: previewed);
        await tester.pump();

        final painter =
            tester
                    .widget<CustomPaint>(
                      find.named('$grid-row-cells-${_two.draw}'),
                    )
                    .painter!
                as TimelineRowCellsPainter;
        expect(identical(painter.layer, previewed), isTrue);
      });

      testWidgets('a held file\'s cells show on the row standing for the '
          'layer it would land on', (tester) async {
        await crossed(tester);
        _preview.value = MediaPlacementPreview(
          silhouette: (
            layerId: LayerId(_two.plain),
            startIndex: 6,
            endIndexExclusive: 8,
          ),
        );
        await tester.pump();

        final silhouettes = find.descendant(
          of: find.named('$grid-frame-$along-area-${_two.plain}'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter is TimelineSilhouettePainter,
          ),
        );
        expect(silhouettes, findsOneWidget);
        expect(
          (tester.widget<CustomPaint>(silhouettes).painter!
                  as TimelineSilhouettePainter)
              .frames,
          2,
        );
      });

      testWidgets('the same layers in another world draw that world', (
        tester,
      ) async {
        await crossed(tester);
        final rows =
            tester.widgetList(find.byType(TimelineFrameCellsRow)).toList();

        await tester.pumpWidget(
          _panel(
            (world: 'world-3', camera: '', sound: '', draw: '', plain: ''),
            orientation,
            heard,
            hooks,
            layers: _layers[_two],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          {
            for (final paint in tester.widgetList<CustomPaint>(
              find.byType(CustomPaint),
            ))
              if (paint.painter case final TimelineRowCellsPainter painter)
                painter.substrateGeneration,
          },
          {'world-3'},
          reason: 'linked cuts share their layers; the world says which '
              'cut the tiles are baked for (#29)',
        );
        expect(
          tester.widgetList(find.byType(TimelineFrameCellsRow)).toList(),
          orderedEquals(rows),
        );
      });

      testWidgets('a finger pressed inside the selection is read inside it: '
          'it takes the block once the block would leave its seat, not '
          'once it leaves the cell', (tester) async {
        await crossed(tester);
        void select() => hooks.selection.value = TimelineFrameRangeSelection(
          layerId: LayerId(_two.plain),
          startIndex: 0,
          endIndexExclusive: 3,
        );
        final cell = twoCells(tester, _two.plain) / 2;
        // Late in cell 1, so the finger leaves the cell before it has gone
        // half a cell: a press read as off the selection steps there.
        final from = cellOf(tester, _two.plain, 1) + cell * 0.35;
        // A finger: its drag waits out a slop the first step cuts short
        // ([EagerPanGestureRecognizer.firstStepAt]) — a mouse's drag starts
        // a pixel on, whatever the step says.
        Future<void> dragBy(double cells) async {
          final gesture = await tester.startGesture(from);
          await gesture.moveBy(cell * cells);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        }

        select();
        await tester.pump();
        await dragBy(0.3);
        expect(
          heard.where((verb) => verb.startsWith('move')),
          isEmpty,
          reason: 'inside the selection the first step is the block\'s — a '
              'press read on the layer the row was built for stepped as it '
              'left the cell, and moved',
        );

        select();
        await tester.pump();
        await dragBy(0.6);
        expect(
          heard,
          contains('move ${_two.plain}'),
          reason: 'LIVENESS: past half a cell the same press moves it',
        );
      });

      testWidgets('a sound that began in the cut before keeps no start grip '
          'on the row standing in that cut — the row draws the world it '
          'stands in, not the one it was built in', (tester) async {
        Iterable<TimelineRowGripTarget> startGrips() =>
            (tester
                        .widget<CustomPaint>(
                          find.named('$grid-edit-chrome-${_two.sound}'),
                        )
                        .painter!
                    as TimelineRowEditChromePainter)
                .model
                .targets
                .whereType<TimelineRowGripTarget>()
                .where(
                  (grip) =>
                      grip.edge == TimelineBlockEdge.start &&
                      grip.blockStartIndex == 0,
                );
        await crossed(tester);
        expect(
          startGrips(),
          isNotEmpty,
          reason: 'LIVENESS: a block of the cut\'s own starts with a grip',
        );

        await tester.pumpWidget(
          _panel(
            _two,
            orientation,
            heard,
            hooks,
            spill: {LayerId(_two.sound): 2},
          ),
        );
        await tester.pumpAndSettle();

        expect(
          startGrips(),
          isEmpty,
          reason: 'a block that began in the cut before wears its `~` '
              'where the start grip was (UI-R7 #6)',
        );
      });

      testWidgets('a layer edited under a standing preview reaches the row: '
          'its edges call back on the layer as committed (R12-③)', (
        tester,
      ) async {
        await crossed(tester);
        final drawn = _layers[_two]!.firstWhere(
          (layer) => layer.id.value == _two.draw,
        );
        _preview.value = ExposureEdgeDragPreview(
          previewLayer: drawn.copyWith(
            timeline: {
              0: const TimelineExposure.drawing(FrameId('f'), length: 9),
            },
          ),
        );
        await tester.pump();
        // Committed while the preview stands: the same layer, a new value.
        final committed = drawn.copyWith(name: 'Draw');

        await tester.pumpWidget(
          _panel(
            _two,
            orientation,
            heard,
            hooks,
            layers: [
              for (final layer in _layers[_two]!)
                if (layer.id == committed.id) committed else layer,
            ],
          ),
        );
        await tester.pump();

        final chrome = tester.widget<TimelineRowEditChromeLayer>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TimelineRowEditChromeLayer &&
                widget.layerId == committed.id,
          ),
        );
        expect(
          identical(chrome.resolver.baseLayer, committed),
          isTrue,
          reason: 'the preview stands as it was; the layer under it moved',
        );
      });
    });
  }
}

/// One cut's rows: the same shapes in both cuts, other layers.
typedef _Cut = ({
  String world,
  String camera,
  String sound,
  String draw,
  String plain,
});

const _one = (
  world: 'world-1',
  camera: 'camera-1',
  sound: 'sound-1',
  draw: 'draw-1',
  plain: 'plain-1',
);

const _two = (
  world: 'world-2',
  camera: 'camera-2',
  sound: 'sound-2',
  draw: 'draw-2',
  plain: 'plain-2',
);

/// Each cut's layers, ONE list apiece: a host hands an untouched layer
/// back as the same instance, and a row draws anew when its layer is
/// another.
final _layers = {for (final cut in [_one, _two]) cut: _layersOf(cut)};

List<Layer> _layersOf(_Cut cut) => [
  Layer(
    id: LayerId(cut.camera),
    name: 'Camera',
    kind: LayerKind.camera,
    frames: const [],
  ),
  Layer(
    id: LayerId(cut.sound),
    name: 'Sound',
    kind: LayerKind.se,
    frames: const [],
    timeline: const {0: TimelineExposure.drawing(FrameId('s'), length: 3)},
    audioClips: [AudioClip(filePath: 'take.wav', frameId: const FrameId('s'))],
  ),
  // The second cut's blocks are longer: the rows draw another picture.
  _drawing(cut.draw, 'Draw', cut == _one ? 4 : 6),
  _drawing(cut.plain, 'Plain', cut == _one ? 3 : 5),
];

Layer _drawing(String id, String name, int length) => Layer(
  id: LayerId(id),
  name: name,
  frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
  timeline: {0: TimelineExposure.drawing(const FrameId('f'), length: length)},
);

const _fileKey = ValueKey<String>('a-file-to-drop');

final _cursor = ValueNotifier<int>(0);
final _preview = ValueNotifier<TimelineDragPreview?>(null);

/// Every cell uncovered, from one function for every pump — as the
/// session's tear-off is: a fresh closure is a new row.
TimelineCellExposureState _uncovered(Layer _, int _) =>
    TimelineCellExposureState.uncovered;

/// The hooks a host binds ONCE, as it binds its own: a kept row holds the
/// ones it was built with.
typedef _Hooks = ({
  ValueNotifier<TimelineFrameRangeSelection?> selection,
  TimelineFrameRangeHooks range,
  TimelineCommaDragCallbacks commaDrag,
});

_Hooks _hooksHeardBy(List<String> heard) {
  final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
  return (
    selection: selection,
    range: TimelineFrameRangeHooks(
      selection: selection,
      onSelectUpdate:
          (layerId, _, _, {headLayerId, spanRows = const []}) =>
              heard.add('range ${layerId.value}'),
      // As the host's: a press that clears lets the selection go, so a
      // press read as off it cannot go on to move it.
      onClear: () => selection.value = null,
      move: TimelineRangeMoveCallbacks(
        holds: (_) => false,
        onBegin: (layerId) {
          heard.add('move ${layerId.value}');
          return true;
        },
        onUpdate: ({required frameDelta, targetLayerId}) {},
        onEnd: () {},
        onCancel: () {},
      ),
    ),
    commaDrag: TimelineCommaDragCallbacks(
      onBegin: (layerId, _, _) {
        heard.add('grip ${layerId.value}');
        return true;
      },
      onUpdate: (_) {},
      onEnd: () {},
      onCancel: () {},
    ),
  );
}

/// What a pass built again inside the cells rows: how many pictures, and
/// every other widget built there that no picture holds.
final class _RowRebuilds {
  final List<Type> outsideThePictures = [];
  int pictures = 0;

  static const _drawing = {'_Shown', '_RowCellsPicture'};

  void listen() {
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget.runtimeType.toString() == '_RowCellsPicture') {
        pictures += 1;
      }
      var underAPicture = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is TimelineFrameCellsRow) {
          if (!underAPicture &&
              !_drawing.contains(element.widget.runtimeType.toString())) {
            outsideThePictures.add(element.widget.runtimeType);
          }
          return false;
        }
        if (_drawing.contains(ancestor.widget.runtimeType.toString())) {
          underAPicture = true;
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
  _Hooks hooks, {
  List<Layer>? layers,
  Map<LayerId, int> spill = const {},
}) {
  void hear(String verb, LayerId id) => heard.add('$verb ${id.value}');
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Draggable<MediaAssetDragData>(
            data: MediaAssetDragData(path: 'C:/art/a.png', name: 'a'),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: SizedBox(width: 8, height: 8),
            // Painted, so a press hits it: an empty box takes no pointer.
            child: ColoredBox(
              key: _fileKey,
              color: Color(0xFF808080),
              child: SizedBox(width: 40, height: 40),
            ),
          ),
          Expanded(
            child: TimelinePanel(
              layers: layers ?? _layers[cut]!,
              activeLayerId: null,
              substrateGeneration: cut.world,
              frameCursor: _cursor,
              playbackFrameCount: 12,
              spillInLeadFrames: spill,
              exposureStateForLayer: _uncovered,
              onSelectLayer: (id) => hear('select', id),
              onSelectFrame: (_) {},
              onActivateCell: (id, _) => hear('activate', id),
              onDropMediaAssetOnLayer: (id, _, _) => hear('drop', id),
              commaDrag: hooks.commaDrag,
              rangeHooks: hooks.range,
              dragPreview: _preview,
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              orientation: orientation,
              onOrientationChanged: (_) {},
            ),
          ),
        ],
      ),
    ),
  );
}
