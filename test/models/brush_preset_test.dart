import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:quick_animaker_v2/src/models/brush_group_id.dart';
import 'package:quick_animaker_v2/src/models/brush_preset.dart';
import 'package:quick_animaker_v2/src/models/brush_preset_id.dart';
import 'package:quick_animaker_v2/src/models/brush_settings.dart';

void main() {
  group('BrushPreset', () {
    final preset = BrushPreset(
      id: const BrushPresetId('preset-1'),
      name: 'Pencil',
      settings: BrushSettings(size: 4),
    );

    test('copyWith preserves unspecified fields', () {
      final renamed = preset.copyWith(name: 'Ink');

      expect(renamed.id, preset.id);
      expect(renamed.settings, preset.settings);
    });

    test('copyWith updates name', () {
      expect(preset.copyWith(name: 'Ink').name, 'Ink');
    });

    test('copyWith updates settings', () {
      final settings = BrushSettings(size: 12);

      expect(preset.copyWith(settings: settings).settings, settings);
    });

    test('toJson/fromJson round-trips', () {
      expectJsonRoundTrip(preset, BrushPreset.fromJson);
    });

    test('equality includes id, name, and settings', () {
      expect(
        preset.copyWith(id: const BrushPresetId('preset-2')),
        isNot(preset),
      );
      expect(preset.copyWith(name: 'Ink'), isNot(preset));
      expect(preset.copyWith(settings: BrushSettings(size: 6)), isNot(preset));
    });

    test('equality includes the group', () {
      final grouped = preset.copyWith(groupId: const BrushGroupId('ink'));

      expect(grouped, isNot(preset));
      expect(grouped.groupId, const BrushGroupId('ink'));
    });

    test('copyWith keeps the group unless it is passed', () {
      final grouped = preset.copyWith(groupId: const BrushGroupId('ink'));

      expect(grouped.copyWith(name: 'Ink').groupId, const BrushGroupId('ink'));
      // An explicit null is the way OUT of a group (back to the root
      // section) — the sentinel keeps that distinct from "not passed".
      expect(grouped.copyWith(groupId: null).groupId, isNull);
    });

    test('a grouped preset round-trips through json', () {
      expectJsonRoundTrip(
        preset.copyWith(groupId: const BrushGroupId('imported-Noah')),
        BrushPreset.fromJson,
      );
    });

    test(
      'duplicate preset names are allowed because BrushPresetId is identity',
      () {
        final duplicateName = BrushPreset(
          id: const BrushPresetId('preset-2'),
          name: preset.name,
          settings: preset.settings,
        );

        expect(duplicateName.name, preset.name);
        expect(duplicateName.id, isNot(preset.id));
        expect(duplicateName, isNot(preset));
      },
    );
  });
}
