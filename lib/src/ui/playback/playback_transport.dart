import 'package:flutter/foundation.dart';

/// A thing that plays, as [PlaybackActuationGate] sees one.
///
/// 🚨★★★**「재생은 앱에 하나」** (유저 2026-09-07, answering
/// `viewer-plays-sound-Q1` with `exclusive`): 「나중에 누른 쪽이 이기고 진
/// 쪽은 정지」, and the option they picked spelled BOTH directions —
/// 「takeover 와 반대 방향도 성립합니다: 뷰어가 소리를 내는 중에 타임라인
/// 재생을 누르면 뷰어가 멈춥니다」.
///
/// ⛔**This interface exists so the law keeps ONE home.** The gate used to
/// hold a `CanvasPlaybackController` by its concrete type, which is why the
/// canvas→viewer direction worked and the viewer→canvas direction did not
/// exist: the viewer runs its own timer and the gate had no way to hear it.
/// The alternative — teaching the gate about a second concrete class — is
/// the shape that file's own note refuses in its first paragraph: 「법은
/// 하나고 집도 하나 … 각 표면에 「나 재생 중인가?」를 묻게 하면 내일
/// 추가되는 표면이 잊는다」.
///
/// The surface is exactly what the gate uses and nothing more.
abstract interface class PlaybackTransport {
  /// Whether this transport is running right now.
  bool get isPlaying;

  /// Stops where it stands. 「재생아닌상태가 일시정지상태나 다름없음」 only
  /// holds if stopping does not also rewind.
  void stop();

  /// Notifies when [isPlaying] flips, and ONLY then.
  ///
  /// ⚠️Never the transport itself: the canvas controller notifies once per
  /// played frame, and a gate rebuilt at fps is the exact mistake the
  /// playback view's comments were written to prevent.
  ValueListenable<bool> get isActiveListenable;
}

/// Every transport the app has, and the one answer the gate asks for.
///
/// 🚨★★★**EXCLUSIVE FALLS OUT OF THE GATE; THERE IS NO SECOND MECHANISM.**
/// A transport can only be started by an ACTUATION, and while any transport
/// plays the gate eats the first actuation and stops everything. So
/// 「나중에 누른 쪽이 이긴다」 is what a person experiences without anything
/// here arbitrating: press one, playback stops; press again, the other one
/// runs. ⛔No「claim」verb, no start-time arbitration — a second mechanism
/// would be a second answer to 「who is playing」, and the two would drift.
///
/// ⚠️The double press is the LAW showing through, not a bug: 유저
/// 2026-09-08, asked whether to make the viewer an exception, said 「그대로
/// 둠. 그게 직관적임」. The actuation is consumed everywhere or the rule is
/// 「most places」.
class PlaybackTransports with ChangeNotifier implements ValueListenable<bool> {
  /// ⚠️Order is not meaningful and membership is small — one canvas plus
  /// whatever media viewers are open. A list keeps [stopAll] deterministic
  /// for a test to read.
  final List<PlaybackTransport> _members = <PlaybackTransport>[];

  /// True while ANY member is playing — what the gate arms itself on.
  @override
  bool get value => _members.any((t) => t.isPlaying);

  /// The last [value] the listeners were told about.
  ///
  /// 🚨★★★NOTIFY ON THE ANSWER CHANGING, NOT ON SOMETHING HAPPENING.
  /// A media viewer registers from its `initState`, which runs DURING a
  /// build — and a `ValueListenableBuilder` above it calling `setState`
  /// there is the framework error 「setState() called during build」
  /// (measured, not assumed: it threw on the first run of the viewer's
  /// own test). A newcomer is stopped, so the answer does not change and
  /// nobody needs telling. The same rule covers the closing tab, which
  /// deregisters while the tree is locked.
  bool _reported = false;

  void _reportIfChanged() {
    final now = value;
    if (now == _reported) {
      return;
    }
    _reported = now;
    notifyListeners();
  }

  /// Who is registered right now.
  ///
  /// ⚠️Test-only ON PURPOSE, and it exists because [remove] is otherwise
  /// unobservable: a stale member reports `isPlaying == false` forever, so
  /// a viewer tab that forgot to deregister looks exactly like a healthy
  /// app until the list has grown for a session and [dispose] is walking
  /// notifiers their owners already disposed. Nothing in `lib/` may read
  /// this — a surface that needs to know who is playing is asking [value].
  @visibleForTesting
  List<PlaybackTransport> get registered => List.unmodifiable(_members);

  /// Adds [transport] and follows it until [remove].
  ///
  /// ⛔Idempotent: a State that re-registers on a hot reload must not end up
  /// listened to twice, which would leave a listener behind on removal.
  void add(PlaybackTransport transport) {
    if (_members.contains(transport)) {
      return;
    }
    _members.add(transport);
    transport.isActiveListenable.addListener(_reportIfChanged);
    _reportIfChanged();
  }

  /// Drops [transport]. ⚠️A viewer tab closing MUST call this — a dead
  /// transport left in the list answers `isPlaying` from a disposed timer
  /// and would arm the gate over nothing.
  void remove(PlaybackTransport transport) {
    if (!_members.remove(transport)) {
      return;
    }
    transport.isActiveListenable.removeListener(_reportIfChanged);
    _reportIfChanged();
  }

  /// Stops every member. What the gate does with the actuation it ate.
  ///
  /// ⚠️All of them rather than「the playing one」: asking which is playing
  /// and then stopping it is two reads of a thing that can change between
  /// them, and stopping an already-stopped transport is free.
  void stopAll() {
    for (final transport in List<PlaybackTransport>.of(_members)) {
      transport.stop();
    }
  }

  @override
  void dispose() {
    for (final transport in _members) {
      transport.isActiveListenable.removeListener(_reportIfChanged);
    }
    _members.clear();
    super.dispose();
  }
}
