/// The state of a single piece of loadable data.
///
/// Most loading APIs model this as a `bool`. A boolean can say "waiting" or
/// "done" and nothing else, which means it cannot express the two situations
/// that dominate real apps:
///
///  * a cache holds last week's value while the network answers, and
///  * a value is arriving in pieces (a streamed response, a paginated feed).
///
/// [SeamValue] names four states instead of two so both are expressible, and
/// so a widget can decide to show *something useful* rather than a grey box.
///
/// ```dart
/// SeamValue<Article> value = const SeamValue.absent();
/// value = SeamValue.stale(cached, asOf: cache.writtenAt);
/// value = SeamValue.partial(partialArticle, progress: 0.4);
/// value = SeamValue.fresh(article);
/// ```
///
/// The type is `sealed`, so `switch` over it is exhaustive and the analyzer
/// will tell you when a new state is unhandled.
sealed class SeamValue<T> {
  /// Const superclass constructor.
  const SeamValue();

  /// Nothing has arrived. This is the only state that warrants a skeleton.
  const factory SeamValue.absent() = SeamAbsent<T>;

  /// A previously known value, believed out of date.
  ///
  /// Showing this degraded is almost always better than showing a skeleton:
  /// the reader gets real information immediately, and the update replaces it
  /// in place. [asOf] records when the value was current, so the UI can say
  /// how stale it is rather than hiding the fact.
  const factory SeamValue.stale(T value, {DateTime? asOf}) = SeamStale<T>;

  /// An incomplete value that is still arriving.
  ///
  /// [progress] is a hint in the range 0..1 when the source knows how much is
  /// left, and null when it does not. It is a hint only; nothing depends on
  /// its accuracy.
  const factory SeamValue.partial(T value, {double? progress}) =
      SeamPartial<T>;

  /// A current, complete value.
  ///
  /// This is the only state Seam measures geometry from — see
  /// `SeamMemory`. Recording the shape of stale or partial content would
  /// teach the skeleton the wrong shape.
  const factory SeamValue.fresh(T value) = SeamFresh<T>;

  /// The best value available right now, or null if nothing has arrived.
  ///
  /// Note that a `SeamValue<int?>` cannot distinguish "absent" from "a fresh
  /// null" through this getter. Switch over the state directly when that
  /// distinction matters.
  T? get valueOrNull;

  /// Whether any value — stale, partial or fresh — is available to render.
  bool get hasValue => valueOrNull != null;

  /// Whether this value is current and complete.
  bool get isFresh => this is SeamFresh<T>;

  /// Whether Seam should still be indicating activity for this value.
  ///
  /// True for every state except [SeamFresh], including [SeamStale] — a
  /// stale value is readable, but a refresh is still outstanding.
  bool get isResolving => !isFresh;

  /// How far this value has progressed, in the range 0..1.
  ///
  /// Slots report this to their scope so the effect can encode real progress
  /// instead of looping blindly. [SeamStale] contributes 0 because a stale
  /// value represents no progress toward the *new* value.
  double get resolvedFraction => switch (this) {
        SeamAbsent<T>() => 0.0,
        SeamStale<T>() => 0.0,
        SeamPartial<T>(:final progress) => (progress ?? 0.5).clamp(0.0, 1.0),
        SeamFresh<T>() => 1.0,
      };

  /// Applies [transform] to the carried value, preserving the state.
  ///
  /// Useful for adapting a source to a widget's expected type without
  /// collapsing the four states back into a boolean.
  SeamValue<R> mapValue<R>(R Function(T value) transform) => switch (this) {
        SeamAbsent<T>() => SeamValue<R>.absent(),
        SeamStale<T>(:final value, :final asOf) =>
          SeamValue<R>.stale(transform(value), asOf: asOf),
        SeamPartial<T>(:final value, :final progress) =>
          SeamValue<R>.partial(transform(value), progress: progress),
        SeamFresh<T>(:final value) => SeamValue<R>.fresh(transform(value)),
      };

  /// Exhaustively handles each state.
  ///
  /// Prefer a `switch` expression at the call site; this exists for callers
  /// on older analysis settings and for terse one-liners.
  R when<R>({
    required R Function() absent,
    required R Function(T value, DateTime? asOf) stale,
    required R Function(T value, double? progress) partial,
    required R Function(T value) fresh,
  }) =>
      switch (this) {
        SeamAbsent<T>() => absent(),
        SeamStale<T>(:final value, :final asOf) => stale(value, asOf),
        SeamPartial<T>(:final value, :final progress) =>
          partial(value, progress),
        SeamFresh<T>(:final value) => fresh(value),
      };
}

/// No value has arrived. See [SeamValue.absent].
final class SeamAbsent<T> extends SeamValue<T> {
  /// Creates the absent state.
  const SeamAbsent();

  @override
  T? get valueOrNull => null;

  @override
  bool operator ==(Object other) => other is SeamAbsent<T>;

  @override
  int get hashCode => Object.hash(SeamAbsent, T);

  @override
  String toString() => 'SeamValue<$T>.absent()';
}

/// A known-outdated value. See [SeamValue.stale].
final class SeamStale<T> extends SeamValue<T> {
  /// Creates the stale state around [value].
  const SeamStale(this.value, {this.asOf});

  /// The out-of-date value. Safe to render, but mark it as stale.
  final T value;

  /// When [value] was last known to be current, if the source tracks it.
  final DateTime? asOf;

  @override
  T? get valueOrNull => value;

  @override
  bool operator ==(Object other) =>
      other is SeamStale<T> && other.value == value && other.asOf == asOf;

  @override
  int get hashCode => Object.hash(SeamStale, value, asOf);

  @override
  String toString() => 'SeamValue<$T>.stale($value, asOf: $asOf)';
}

/// A value still arriving. See [SeamValue.partial].
final class SeamPartial<T> extends SeamValue<T> {
  /// Creates the partial state around what has arrived so far.
  const SeamPartial(this.value, {this.progress});

  /// The portion of the value received so far.
  final T value;

  /// Optional 0..1 completion hint.
  final double? progress;

  @override
  T? get valueOrNull => value;

  @override
  bool operator ==(Object other) =>
      other is SeamPartial<T> &&
      other.value == value &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(SeamPartial, value, progress);

  @override
  String toString() => 'SeamValue<$T>.partial($value, progress: $progress)';
}

/// A current, complete value. See [SeamValue.fresh].
final class SeamFresh<T> extends SeamValue<T> {
  /// Creates the fresh state around [value].
  const SeamFresh(this.value);

  /// The current value.
  final T value;

  @override
  T? get valueOrNull => value;

  @override
  bool operator ==(Object other) => other is SeamFresh<T> && other.value == value;

  @override
  int get hashCode => Object.hash(SeamFresh, value);

  @override
  String toString() => 'SeamValue<$T>.fresh($value)';
}
