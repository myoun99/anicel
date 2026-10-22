import '../../services/playback/frame_demand.dart';
import '../quiet_turns.dart' show QuietTurns, notDue;

/// What a frame's picture is made of, where the screen that shows it looks
/// for it — asked by the one maker of playback's pictures, and through it by
/// a run that waits for one and the ruler's bar that counts them, so none of
/// them can mean a different picture from the one the screen draws
/// (playback-plays-the-screen-material).
abstract interface class PlaybackPictures {
  /// Whether [picture] is there to show.
  bool has(DemandedPicture picture);

  /// The parts of [picture] not there yet that making it would make, each
  /// by an identity two frames showing it share — what a walk asking ahead
  /// counts so a part is asked for once.
  Set<Object> partsToMake(DemandedPicture picture);

  /// Whether making [picture] threw at the content it has now — it is not
  /// waited for, nor made again until that content changes ([noteFailure]).
  bool failed(DemandedPicture picture);

  /// Remembers that making [picture] threw at the content it has now.
  void noteFailure(DemandedPicture picture);

  /// The bytes making [picture] would add — what its parts will be made as,
  /// where what they are made of is in hand ([readIn]).
  int bytesToMake(DemandedPicture picture);

  /// Reads in what making [picture] reads first, so [bytesToMake] weighs it
  /// by what it will be made as. Never throws: what will not read is said by
  /// [make].
  Future<void> readIn(DemandedPicture picture);

  /// The bytes [picture] holds that [seen] has not counted, which it adds to
  /// [seen]: a walk weighs the window it has passed over by this, each
  /// picture's parts counted once however many frames show them.
  int weighNew(DemandedPicture picture, Set<Object> seen);

  /// Makes [picture]: true when it landed, false when [shouldAbort] stood it
  /// down. Throws where its content cannot be read.
  ///
  /// What it puts on the GPU waits for the quiet between a run's held frames
  /// ([QuietTurns]) — except while [due]: then the run's next held frame
  /// shows what is being made, and the quiet that frame leaves comes too
  /// late for it.
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    bool Function() due = notDue,
  });
}
