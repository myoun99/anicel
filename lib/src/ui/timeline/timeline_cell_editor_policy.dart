import '../../models/layer_kind.dart';

/// Entrance unification: EVERY layer kind opens the shared instance-edit
/// dialog on cell double-tap — animation/storyboard/image edit the frame
/// name, SE its name/dialogue, instruction its event, camera its keys.
/// Kept as a function (not a constant) so the gate stays declarative at
/// the call sites and future kinds opt in/out in one place.
///
/// Trade-off (accepted for consistency): a non-null onDoubleTap delays
/// single-tap selection by the double-tap window on every cell, as SE and
/// instruction rows already did.
bool layerKindOpensCellEditorOnDoubleTap(LayerKind kind) => true;
