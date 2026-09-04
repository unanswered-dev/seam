import 'package:flutter/widgets.dart';

/// The two colours a bone is painted between.
///
/// A bone is filled with a single solid colour interpolated from [base] to
/// [highlight] by how brightly the scope's light falls on it. There is no
/// gradient and no mask — which is why a screen of bones costs no `saveLayer`
/// — so these two colours fully describe the effect's appearance.
///
/// Set one on [SeamScope] to theme every bone at once; a slot can still
/// override it.
@immutable
class SeamPalette {
  /// Creates a palette from an unlit and a fully lit colour.
  const SeamPalette({required this.base, required this.highlight});

  /// Neutral greys for a light background.
  const SeamPalette.light()
      : base = const Color(0xFFCDD4DC),
        highlight = const Color(0xFFF2F5F8);

  /// Neutral greys for a dark background.
  const SeamPalette.dark()
      : base = const Color(0xFF2D333B),
        highlight = const Color(0xFF3F4752);

  /// Derives a palette from a single colour.
  ///
  /// [highlight] is [seed] lifted toward [toward] — white by default — by
  /// [lift]. Useful for tinting bones to a brand colour without hand-picking
  /// both ends. On a dark ground, pass a smaller [lift] so the highlight does
  /// not blow out.
  factory SeamPalette.from(
    Color seed, {
    double lift = 0.32,
    Color toward = const Color(0xFFFFFFFF),
  }) {
    assert(lift >= 0 && lift <= 1, 'lift must be in [0, 1]');
    return SeamPalette(
      base: seed,
      highlight: Color.lerp(seed, toward, lift) ?? seed,
    );
  }

  /// The colour of a bone the light is not reaching.
  final Color base;

  /// The colour of a bone at the centre of the light.
  final Color highlight;

  /// The palette matching [context]'s platform brightness.
  ///
  /// This is the fallback when no palette is set on the scope or the slot.
  static SeamPalette of(BuildContext context) {
    return MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark
        ? const SeamPalette.dark()
        : const SeamPalette.light();
  }

  /// Returns a copy with the given fields replaced.
  SeamPalette copyWith({Color? base, Color? highlight}) => SeamPalette(
        base: base ?? this.base,
        highlight: highlight ?? this.highlight,
      );

  /// Linearly interpolates between two palettes.
  static SeamPalette? lerp(SeamPalette? a, SeamPalette? b, double t) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return SeamPalette(
      base: Color.lerp(a.base, b.base, t) ?? a.base,
      highlight: Color.lerp(a.highlight, b.highlight, t) ?? a.highlight,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeamPalette && other.base == base && other.highlight == highlight;

  @override
  int get hashCode => Object.hash(base, highlight);

  @override
  String toString() => 'SeamPalette(base: $base, highlight: $highlight)';
}
