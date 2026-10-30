import 'cut.dart';
import 'layer.dart';
import 'layer_effect.dart';

/// What binds a plugin's effect to its run ([ResolvedLayerEffect.run]):
/// [effects] — [row]'s chain at [frameIndex] of [cut] — with the plugin
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
      required Layer row,
      required int frameIndex,
    });
