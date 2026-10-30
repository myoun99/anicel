import 'cut.dart';
import 'layer_effect.dart';

/// What binds a plugin's effect to its run ([ResolvedLayerEffect.run]):
/// [effects] — a chain of [cut] at its frame [frameIndex], a row's, a
/// folder's, an adjustment's or the V row's over the cut — with each plugin
/// that runs there run, and [effects] itself where none does.
///
/// Handed to the plan where a route can say what a plugin runs with — a
/// device's builds, a project's frame rate, a store of pictures
/// (`deviceFxPluginBinding`); null where a route runs none, as
/// `hasPlugin: null` reads none as missing (🗣️I-132-Q28).
typedef FxPluginBinding =
    List<ResolvedLayerEffect> Function(
      List<ResolvedLayerEffect> effects, {
      required Cut cut,
      required int frameIndex,
    });
