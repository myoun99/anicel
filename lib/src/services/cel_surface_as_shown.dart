import '../models/bitmap_surface.dart';
import '../models/layer_effect.dart';
import 'cel_source_effect_pass.dart';
import 'cel_text_laying.dart';

/// THE SEAM A CEL'S PICTURE CROSSES ON ITS WAY TO BEING SHOWN: the tiles a
/// row draws for [surface] under its effect chain [effects].
///
/// Two things are computed over a cel's own bytes before anything is drawn,
/// and their order is the order they exist in: the texts are part of the
/// picture ([celSurfaceWithTextsLaid]), and the colour keys are a filter
/// over that picture ([celSurfaceWithSourceEffects]) — so a key names a
/// letter's colour exactly as it names a drawn line's.
///
/// 🚨★★★EVERY ROUTE THAT DRAWS A CEL COMES THROUGH HERE — the shared plan
/// (`CutFrameCompositeLayer`: playback, export, the camera), the editing
/// stack's row images (`LayerFrameImageCache`), the row being drawn on and
/// the conte's live picture. A route that took the keys' pass alone would
/// show a cel without its texts, which is why the keys' pass is not called
/// from anywhere else (`a_cel_is_shown_through_one_seam_test`).
///
/// Pass `const []` where the row has no chain.
BitmapSurface celSurfaceAsShown(
  BitmapSurface surface,
  List<ResolvedLayerEffect> effects,
) => celSurfaceWithSourceEffects(celSurfaceWithTextsLaid(surface), effects);
