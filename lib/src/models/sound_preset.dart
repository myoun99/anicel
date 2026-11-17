import 'layer_effect.dart';

/// A sound's character (board audio-fx-second-effect-and-presets ②): picked
/// from the Fx pill's プリセット, its [effects] come onto the row as a
/// paste of them does (`EffectsAndFx.addEffectCopies`) — and are then the
/// row's own, as effects added one by one are.
///
/// 🗣️Q2 (유저 2026-11-17): 「시안 3 · 시안 1 + 성격 프리셋」 — the menu as
/// approved: セリフ · 音楽 · 効果音 · 環境音, each a bundle of the sound's
/// effects.
///
/// Each bundle is an equalizer then a compressor, the two the app has; the
/// design's セリフ adds ノイズ除去 first, an effect still to come (board
/// audio-fx-second-effect-and-presets-Q1). The values are my choice —
/// common starting points for each kind of sound, not any tool's table
/// (board line 11-18) — and are changed if the user says so.
enum SoundPreset {
  /// A voice: the rumble under it cut, its presence lifted, its level held.
  dialogue('dialogue', label: 'Dialogue'),

  /// Music: only what is under hearing cut, turned down gently.
  music('music', label: 'Music'),

  /// A hit: the rumble cut, its peak caught at once and let go soon.
  soundEffects('soundEffects', label: 'Sound effects'),

  /// A room or a street: kept under a voice — its lows cut, its highs
  /// softened, turned down slowly.
  ambience('ambience', label: 'Ambience');

  const SoundPreset(this.jsonValue, {required this.label});

  /// The key its name is found under in every language.
  final String jsonValue;

  /// Its name in English, the string tables' fallback.
  final String label;

  /// The effects it adds, in the order they sound: an equalizer, then a
  /// compressor ([EffectKind.filtersSound]), at the values its kind names.
  List<LayerEffect> get effects => switch (this) {
    dialogue => _equalizedAndCompressed(
      equalizer: {'lowCut': 80, 'highGain': 2},
      compressor: {
        'threshold': -20,
        'ratio': 3,
        'attack': 5,
        'release': 80,
        'makeup': 3,
      },
    ),
    music => _equalizedAndCompressed(
      equalizer: {'lowCut': 30, 'highGain': 0},
      compressor: {
        'threshold': -16,
        'ratio': 2,
        'attack': 20,
        'release': 200,
        'makeup': 2,
      },
    ),
    soundEffects => _equalizedAndCompressed(
      equalizer: {'lowCut': 40, 'highGain': 0},
      compressor: {
        'threshold': -12,
        'ratio': 4,
        'attack': 2,
        'release': 60,
        'makeup': 2,
      },
    ),
    ambience => _equalizedAndCompressed(
      equalizer: {'lowCut': 100, 'highGain': -2},
      compressor: {
        'threshold': -24,
        'ratio': 2,
        'attack': 30,
        'release': 300,
        'makeup': 0,
      },
    ),
  };
}

/// An equalizer, then a compressor, each at the values given by its
/// parameter's id: the bundle every [SoundPreset] is. Their ids are a
/// paste's to mint.
List<LayerEffect> _equalizedAndCompressed({
  required Map<String, double> equalizer,
  required Map<String, double> compressor,
}) => [
  _effectAt('preset-equalizer', EffectKind.equalizer, equalizer),
  _effectAt('preset-compressor', EffectKind.compressor, compressor),
];

LayerEffect _effectAt(String id, EffectKind kind, Map<String, double> values) =>
    LayerEffect(
      id: EffectId(id),
      kind: kind,
      parameters: {
        for (final MapEntry(:key, :value) in values.entries)
          key: EffectParameter(value: value),
      },
    );
