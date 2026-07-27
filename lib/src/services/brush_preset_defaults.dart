import '../models/brush_group.dart';
import '../models/brush_group_icon.dart';
import '../models/brush_group_id.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_settings.dart';
import '../models/brush_tip_rotation_mode.dart';
import 'brush_tip_mask_defaults.dart';

const BrushGroupId _pencilGroup = BrushGroupId('builtin-pencil-group');
const BrushGroupId _inkGroup = BrushGroupId('builtin-ink-group');
const BrushGroupId _paintGroup = BrushGroupId('builtin-paint-group');
const BrushGroupId _textureGroup = BrushGroupId('builtin-texture-group');

/// Built-in library groups seeded alongside [defaultBrushPresets], in display
/// order. A library saved at an older version gains the ones it lacks on
/// load, and any built-in preset still sitting at the root section moves
/// into the group it ships in.
///
/// There is deliberately NO eraser group: erasing is the tool's blend, not
/// preset payload (size and blend mode are hand settings a preset never
/// carries), so an "eraser brush" would only ever be a tip SHAPE — and those
/// already live above. Pick any brush while the eraser is active.
final List<BrushGroup> defaultBrushGroups = List.unmodifiable(<BrushGroup>[
  const BrushGroup(
    id: _pencilGroup,
    name: 'Pencil',
    icon: BrushGroupIcon.pencil,
  ),
  const BrushGroup(id: _inkGroup, name: 'Ink', icon: BrushGroupIcon.pen),
  const BrushGroup(id: _paintGroup, name: 'Paint', icon: BrushGroupIcon.paint),
  const BrushGroup(
    id: _textureGroup,
    name: 'Texture',
    icon: BrushGroupIcon.texture,
  ),
]);

/// Built-in brush presets seeded when no user preset library exists yet.
///
/// A working starting set covering the four families a drawing tool is
/// expected to ship with, not a curated artist pack. Users can delete or
/// extend them; the library file then persists their choice.
///
/// Every tip and texture here is generated procedurally
/// (`brush_tip_mask_defaults.dart`) — third-party brush files may not be
/// bundled, so the built-ins have to be the engine's own.
///
/// Note that SIZE is a hand setting: applying a preset deliberately keeps
/// the current brush size (R26 #10). The sizes below shape the panel's
/// previews and say what the brush is FOR.
final List<BrushPreset> defaultBrushPresets = List.unmodifiable(<BrushPreset>[
  // ---- Pencil ----------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-pencil'),
    name: 'Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 4,
      hardness: 1.0,
      spacing: 0.15,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-soft-pencil'),
    name: 'Soft Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      hardness: 0.8,
      opacity: 0.85,
      flow: 0.8,
      spacing: 0.12,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.35),
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-mechanical-pencil'),
    name: 'Mechanical Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 2,
      hardness: 1.0,
      spacing: 0.08,
      // A lead has one width; pressure darkens it rather than widening it.
      sizePressureCurve: BrushPressureCurve.linearFrom(0.8),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.45),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-rough-pencil'),
    name: 'Rough Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 8,
      flow: 0.9,
      spacing: 0.1,
      tipMask: grainBrushTipMask,
      textureMask: paperGrainTextureMask,
      textureDensity: 0.55,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.3),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-colored-pencil'),
    name: 'Colored Pencil',
    groupId: _pencilGroup,
    settings: BrushSettings(
      size: 6,
      flow: 0.55,
      spacing: 0.08,
      tipMask: grainBrushTipMask,
      textureMask: paperGrainTextureMask,
      textureScale: 1.4,
      textureDensity: 0.7,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),

  // ---- Ink -------------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-ink-pen'),
    name: 'Ink Pen',
    groupId: _inkGroup,
    settings: BrushSettings(
      size: 8,
      hardness: 1.0,
      spacing: 0.1,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-g-pen'),
    name: 'G-Pen',
    groupId: _inkGroup,
    settings: BrushSettings(
      size: 10,
      hardness: 1.0,
      spacing: 0.08,
      // The nib that snaps open under pressure: little happens early, then
      // the line swells fast.
      sizePressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.08),
        BrushCurvePoint(0.6, 0.4),
        BrushCurvePoint(1.0, 1.0),
      ]),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-maru-pen'),
    name: 'Maru Pen',
    groupId: _inkGroup,
    settings: BrushSettings(
      size: 3,
      hardness: 1.0,
      spacing: 0.06,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.45),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-brush-pen'),
    name: 'Brush Pen',
    groupId: _inkGroup,
    settings: BrushSettings(
      size: 12,
      hardness: 0.85,
      spacing: 0.07,
      sizePressureCurve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.05),
        BrushCurvePoint(0.4, 0.22),
        BrushCurvePoint(1.0, 1.0),
      ]),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-calligraphy'),
    name: 'Calligraphy',
    groupId: _inkGroup,
    settings: BrushSettings(
      size: 14,
      hardness: 0.9,
      spacing: 0.1,
      roundness: 0.3,
      angleDegrees: 45,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-marker'),
    name: 'Marker',
    groupId: _inkGroup,
    settings: BrushSettings(
      size: 16,
      hardness: 0.8,
      opacity: 0.7,
      flow: 0.6,
      spacing: 0.1,
    ),
  ),

  // ---- Paint -----------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-soft-brush'),
    name: 'Soft Brush',
    groupId: _paintGroup,
    settings: BrushSettings(
      size: 24,
      hardness: 0.25,
      flow: 0.7,
      spacing: 0.1,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-airbrush'),
    name: 'Airbrush',
    groupId: _paintGroup,
    settings: BrushSettings(
      size: 40,
      hardness: 0.05,
      flow: 0.12,
      opacity: 0.9,
      // Tight spacing is what makes an airbrush build rather than band.
      spacing: 0.05,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-round-bristle'),
    name: 'Round Bristle',
    groupId: _paintGroup,
    settings: BrushSettings(
      size: 18,
      hardness: 0.9,
      flow: 0.8,
      spacing: 0.06,
      tipMask: bristleBrushTipMask,
      // Bristles rake along the stroke, so the tip turns with it.
      rotationMode: BrushTipRotationMode.direction,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.5),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-flat-bristle'),
    name: 'Flat Bristle',
    groupId: _paintGroup,
    settings: BrushSettings(
      size: 22,
      flow: 0.75,
      spacing: 0.05,
      roundness: 0.3,
      angleDegrees: 45,
      tipMask: bristleBrushTipMask,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-watercolor'),
    name: 'Watercolor',
    groupId: _paintGroup,
    settings: BrushSettings(
      size: 28,
      hardness: 0.3,
      flow: 0.35,
      opacity: 0.8,
      spacing: 0.05,
      textureMask: paperGrainTextureMask,
      textureScale: 2.0,
      textureDensity: 0.8,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-gouache'),
    name: 'Gouache',
    groupId: _paintGroup,
    settings: BrushSettings(
      size: 20,
      hardness: 0.65,
      flow: 0.9,
      spacing: 0.06,
      textureMask: canvasWeaveTextureMask,
      textureScale: 1.5,
      textureDensity: 0.5,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.6),
    ),
  ),

  // ---- Texture ---------------------------------------------------------
  BrushPreset(
    id: const BrushPresetId('builtin-chalk-preset'),
    name: 'Chalk',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 20,
      flow: 0.85,
      spacing: 0.2,
      tipMask: chalkBrushTipMask,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-splatter-preset'),
    name: 'Splatter',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 28,
      spacing: 0.9,
      tipMask: splatterBrushTipMask,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-stipple'),
    name: 'Stipple',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 10,
      spacing: 0.6,
      scatterRadiusRatio: 1.6,
      scatterCount: 4,
      sizeJitter: 0.5,
      opacityJitter: 0.4,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-sponge'),
    name: 'Sponge',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 34,
      flow: 0.8,
      spacing: 0.35,
      tipMask: spongeBrushTipMask,
      // A clump that landed the same way twice would read as a pattern.
      angleJitter: 1.0,
      sizeJitter: 0.25,
    ),
  ),
  BrushPreset(
    id: const BrushPresetId('builtin-cloud'),
    name: 'Cloud',
    groupId: _textureGroup,
    settings: BrushSettings(
      size: 60,
      hardness: 0.2,
      flow: 0.25,
      spacing: 0.25,
      tipMask: spongeBrushTipMask,
      angleJitter: 1.0,
      scatterRadiusRatio: 0.5,
      scatterCount: 2,
      opacityPressureCurve: BrushPressureCurve.identity(),
    ),
  ),
]);
