import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/layer_controls_row_facts.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show TimelineGroupFold;

/// 🚨F-244: A KEPT CONTROLS ROW SEES EVERY FACT IT SHOWS.
///
/// The rail and the x-sheet keep a layer's controls row while
/// [layerControlsRowFacts] answers the same, so a fact left out of it is a
/// row kept across a change of it — the rail's own key had left out four.
/// This changes one fact at a time, the way the display token's test
/// changes one Layer field at a time ([ControlsRowFace]); the Layer's own
/// fields are that test's.
void main() {
  const id = LayerId('row');
  // A folder, so the stack under it can make it an attach organizer — the
  // one fact read off OTHER layers.
  final row = Layer(
    id: id,
    name: 'Row',
    kind: LayerKind.folder,
    frames: const [],
    timeline: const {},
  );
  Layer member({required bool attached}) => Layer(
    id: const LayerId('member'),
    name: 'Member',
    frames: const [],
    timeline: const {},
    folderId: id,
    attachedToLayerId: attached ? const LayerId('base') : null,
  );
  final base = Layer(
    id: const LayerId('base'),
    name: 'Base',
    frames: const [],
    timeline: const {},
  );
  final overrideA = ValueNotifier<double>(1);
  final overrideB = ValueNotifier<double>(1);
  final previewA = ValueNotifier<({Set<LayerId> layerIds, double opacity})?>(
    null,
  );
  final previewB = ValueNotifier<({Set<LayerId> layerIds, double opacity})?>(
    null,
  );

  LayerControlsRowFacts facts({
    LayerId? activeLayerId,
    Set<TimelineRowAddress> selectedRows = const {},
    Set<LayerId> expandedLaneLayerIds = const {},
    LayerFxState fxState = LayerFxState.on,
    bool onionSkinEnabled = false,
    List<String> linkPartners = const ['other'],
    bool soloed = false,
    AttachedPlacement? attachArrow,
    bool sourceIsShort = false,
    bool memberAttached = false,
    ValueListenable<double>? opacityOverride,
    ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
    opacityDragPreview,
    TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
    int depth = 0,
    TimelineGroupFold fold = (has: false, expanded: false, onToggle: null),
    bool hasLanes = false,
    double? mainExtent,
    void Function(LayerId)? onSelectLayer,
  }) => layerControlsRowFacts(
    TimelineDisplayRow.layer(row, layerIndex: 0, depth: depth),
    (
      hooks: TimelineGridHooks(
        activeLayerId: activeLayerId,
        frameCursor: ValueNotifier<int>(0),
        playbackFrameCount: 24,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: onSelectLayer ?? (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        selectedRows: selectedRows,
        expandedLaneLayerIds: expandedLaneLayerIds,
        layerFxStateOf: (_) => fxState,
        layerOnionSkinEnabledOf: (_) => onionSkinEnabled,
        // A fresh list at every ask, as the session hands them out.
        layerLinkPartnersOf: (_) => [...linkPartners],
        isLayerSoloed: (_) => soloed,
        attachArrowPlacementOf: (_) => attachArrow,
        layerSourceIsShortOf: (_) => sourceIsShort,
        layerOpacityOverrideOf: (_) => opacityOverride,
        opacityDragPreview: opacityDragPreview,
      ),
      layers: [row, member(attached: memberAttached), base],
      metrics: metrics,
      axis: Axis.horizontal,
      keyPrefix: 'timeline',
      mainExtent: mainExtent,
    ),
    fold: fold,
    hasLanes: hasLanes,
  );

  test('the same facts, asked again, are the same facts — and a verb is '
      'not one', () {
    expect(
      facts(onSelectLayer: (_) {}),
      facts(onSelectLayer: (_) {}),
      reason: 'a fresh list and a fresh closure at every build would miss '
          'the memo at every build',
    );
    expect(
      facts(fold: (has: true, expanded: false, onToggle: (_) {})),
      facts(fold: (has: true, expanded: false, onToggle: (_) {})),
    );
    expect(
      facts(opacityOverride: overrideA, opacityDragPreview: previewA),
      facts(opacityOverride: overrideA, opacityDragPreview: previewA),
    );
  });

  final changes = <String, LayerControlsRowFacts Function()>{
    'active': () => facts(activeLayerId: id),
    'selected': () => facts(selectedRows: {const LayerRowAddress(id)}),
    'lanesExpanded': () => facts(expandedLaneLayerIds: {id}),
    'fxState': () => facts(fxState: LayerFxState.off),
    'onionSkinEnabled': () => facts(onionSkinEnabled: true),
    'linkPartners': () => facts(linkPartners: const ['another']),
    'soloed': () => facts(soloed: true),
    'attachArrow': () => facts(attachArrow: AttachedPlacement.below),
    'isReferenceSourceShort': () => facts(sourceIsShort: true),
    'wearsBaseComposite': () => facts(memberAttached: true),
    'opacityOverride': () => facts(opacityOverride: overrideB),
    'opacityDragPreview': () => facts(opacityDragPreview: previewB),
    'layerRowHeight': () => facts(
      metrics: TimelineGridMetrics.defaults.copyWith(layerRowHeight: 40),
    ),
    'layerControlsWidth': () => facts(
      metrics: TimelineGridMetrics.defaults.copyWith(layerControlsWidth: 500),
    ),
    'sectionLabelGutterWidth': () =>
        facts(metrics: const TimelineGridMetrics(sectionLabelGutterWidth: 30)),
    'railColumns': () => facts(
      metrics: TimelineGridMetrics.defaults.copyWith(
        railColumns: (
          opacity: TimelineGridMetrics.defaults.railColumns.opacity + 10,
          blend: TimelineGridMetrics.defaults.railColumns.blend - 10,
        ),
      ),
    ),
    'depth': () => facts(depth: 1),
    'hasGroupFold': () =>
        facts(fold: (has: true, expanded: false, onToggle: null)),
    'groupFoldExpanded': () =>
        facts(fold: (has: false, expanded: true, onToggle: null)),
    'hasLanes': () => facts(hasLanes: true),
    'mainExtent': () => facts(mainExtent: 180),
  };
  for (final change in changes.entries) {
    test('${change.key} is a fact the row shows — it must change the facts',
        () {
      expect(
        facts() == change.value(),
        isFalse,
        reason: 'the row is given ${change.key}; a kept row that survives '
            'its change shows it stale',
      );
    });
  }

  test('language is a fact the row shows — it must change the facts', () {
    final before = facts();
    final settings = AppText.settings.value;
    addTearDown(() => AppText.settings.value = settings);
    AppText.settings.value = settings.copyWith(
      programLanguage: settings.programLanguage == AppLanguage.ja
          ? AppLanguage.en
          : AppLanguage.ja,
    );
    expect(
      before == facts(),
      isFalse,
      reason: 'R27 #6: the blend chip prints a language-dependent name',
    );
  });
}
