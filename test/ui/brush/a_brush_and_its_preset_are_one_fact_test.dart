import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';

/// H25-again / H36 — THE BRUSH A TOOL HOLDS AND THE PRESET IT CAME FROM ARE
/// ONE FACT.
///
/// 유저 2026-09-11: 「브러시1의 크기 6이고 2가 100이면 … 다시 2 고르면
/// 100이아니라 6이되」 and 「지우개는 첫 선택된 지우개가 활성화표시? 그게
/// 안되있는데? 브러시만 되있는데 이상하잖아」. Both were one disagreement: the
/// preset id lived in a map BESIDE the state, so a listener could read one
/// brush's values under another brush's name, and a tool the map had never
/// been told about held a brush the library could not name.
///
/// The workspace half — the listener, the panel, the user's own sequence — is
/// driven through the real app in `workspace_applies_a_preset_test`.
void main() {
  BrushPreset preset(String id, {double size = 10}) => BrushPreset(
    id: BrushPresetId(id),
    name: id,
    settings: BrushSettings.fromShape(BrushShape(size: size)),
  );

  BrushToolState holding(BrushPreset preset, {CanvasTool? tool}) =>
      BrushToolState.defaults.withPreset(
        preset,
        tool: tool ?? CanvasTool.brush,
      );

  test('applying a preset makes the state hold it — the values and the name '
      'arrive in one assignment', () {
    final held = holding(preset('pen', size: 12));

    expect(held.presetId, const BrushPresetId('pen'));
    expect(held.size, 12);
  });

  test('every edit keeps the brush it is an edit of', () {
    final held = holding(preset('pen'));

    expect(held.copyWith(size: 40).presetId, const BrushPresetId('pen'));
    expect(
      held.withMask(BrushMaskSlot.dual, null).presetId,
      const BrushPresetId('pen'),
      reason: 'the private shape path lists the fields outside the shape by '
          'hand — the one place a new field can be dropped on the floor',
    );
  });

  test('two states wearing one shape under two names are NOT equal — or the '
      'highlight would not move between two identical presets', () {
    final a = holding(preset('a'));
    final b = holding(preset('b'));

    expect(a.shape, b.shape, reason: 'premise: the very same brush');
    expect(a == b, isFalse);
    expect(a.hashCode == b.hashCode, isFalse);
  });

  group('the paint-tool bank moves a brush WITH its name (R11-④)', () {
    test('🚨H36: the eraser, taken up the first time, holds the brush the '
        'brush tool held — and can say which one it is', () {
      final notifier = PaintToolStateNotifier(holding(preset('pen')));
      addTearDown(notifier.dispose);

      notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);

      expect(
        notifier.value.presetId,
        const BrushPresetId('pen'),
        reason: 'a brush in hand that the library cannot name is F-63 again, '
            'one tool over',
      );
    });

    test('🚨each tool comes back holding its OWN brush under its OWN name', () {
      final notifier = PaintToolStateNotifier(holding(preset('pen', size: 6)));
      addTearDown(notifier.dispose);
      notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
      notifier.value = notifier.value.withPreset(
        preset('chalk', size: 50),
        tool: CanvasTool.eraser,
      );

      notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);
      expect(notifier.value.presetId, const BrushPresetId('pen'));
      expect(notifier.value.size, 6);

      notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
      expect(
        notifier.value.presetId,
        const BrushPresetId('chalk'),
        reason: 'restoring the shape alone left the brush tool\'s name on the '
            'eraser\'s brush',
      );
      expect(notifier.value.size, 50);
    });
  });
}
