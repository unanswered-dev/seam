import 'package:flutter/foundation.dart';

/// What Seam should be doing at a given point in a load.
enum SeamPhase {
  /// Too early to show anything. Space is reserved, nothing is painted.
  ///
  /// A load that finishes in this window never flashes a skeleton, which is
  /// the single cheapest improvement available to a loading UI.
  held,

  /// The window where a skeleton measurably helps. The effect runs.
  lit,

  /// The load has outlasted the point where a skeleton reassures.
  ///
  /// The effect slows down and the host is expected to surface something more
  /// informative, because a shimmer still looping at eight seconds reads as a
  /// frozen app rather than a busy one.
  escalated,

  /// Content is current. Nothing to indicate.
  settled,
}

/// When the loading effect is allowed to run.
///
/// Every skeleton package on pub.dev starts animating at 0 ms and loops until
/// data arrives. Nielsen Norman Group's finding is that skeleton screens only
/// improve perceived performance inside a band — roughly 400 ms to 3 s. Below
/// it, the skeleton appears and vanishes as a flash, which feels worse than
/// showing nothing. Above it, it stops reassuring.
///
/// A schedule turns that finding into behaviour instead of advice.
@immutable
class SeamSchedule {
  /// Creates a schedule with explicit thresholds.
  /// [suppressBefore] must not exceed [escalateAfter]. That cannot be
  /// asserted here — comparing two `Duration`s is a method call, which a const
  /// constructor may not perform — so it is checked in [phaseAt] instead.
  const SeamSchedule({
    this.suppressBefore = const Duration(milliseconds: 400),
    this.escalateAfter = const Duration(seconds: 3),
  });

  /// The default: suppress below 400 ms, escalate past 3 s.
  const SeamSchedule.nng()
      : suppressBefore = const Duration(milliseconds: 400),
        escalateAfter = const Duration(seconds: 3);

  /// Paint immediately and never escalate — the behaviour of every other
  /// package. Provided for A/B comparison and for hosts that have measured
  /// their own numbers.
  const SeamSchedule.always()
      : suppressBefore = Duration.zero,
        escalateAfter = const Duration(days: 1);

  /// How long a load may run before any skeleton is painted.
  final Duration suppressBefore;

  /// How long a load may run before the effect is considered unhelpful.
  final Duration escalateAfter;

  /// The phase for a load that has been running for [elapsed] and is not yet
  /// [settled].
  SeamPhase phaseAt(Duration elapsed) {
    assert(
      suppressBefore <= escalateAfter,
      'suppressBefore ($suppressBefore) must not exceed escalateAfter '
      '($escalateAfter); the effect would never light.',
    );
    if (elapsed < suppressBefore) return SeamPhase.held;
    if (elapsed < escalateAfter) return SeamPhase.lit;
    return SeamPhase.escalated;
  }

  /// The next moment at which [phaseAt] would return something different, or
  /// null if [elapsed] is already past every threshold.
  ///
  /// Lets a slot schedule exactly one timer instead of rebuilding per frame
  /// while waiting to cross a boundary.
  Duration? nextBoundaryAfter(Duration elapsed) {
    if (elapsed < suppressBefore) return suppressBefore - elapsed;
    if (elapsed < escalateAfter) return escalateAfter - elapsed;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SeamSchedule &&
      other.suppressBefore == suppressBefore &&
      other.escalateAfter == escalateAfter;

  @override
  int get hashCode => Object.hash(suppressBefore, escalateAfter);

  @override
  String toString() =>
      'SeamSchedule(suppressBefore: $suppressBefore, escalateAfter: $escalateAfter)';
}
