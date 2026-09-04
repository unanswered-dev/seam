import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Size, lerpDouble;

import 'package:flutter/foundation.dart';

/// The single moving light that every bone in a scope is lit by.
///
/// The convention is a gradient swept across each widget by a `ShaderMask`.
/// That costs a `saveLayer` per widget — one of the most expensive things the
/// raster thread does — and because each widget animates on its own
/// controller, the sweeps run out of phase. Twenty-five rows means twenty-five
/// offscreen buffers and twenty-five independent suns over one screen.
///
/// Seam inverts it. One scope holds one phase; each bone asks this object how
/// bright it should be given where it sits, and fills itself with a solid
/// colour. There is no mask, no offscreen buffer and nothing to fall out of
/// sync, because there is only one light.
@immutable
class SeamLight {
  /// Creates a light with explicit parameters.
  const SeamLight({
    this.period = const Duration(milliseconds: 1900),
    this.directionDegrees = 20,
    this.softness = 0.55,
    this.travel = 1.7,
    this.intensity = 0.9,
  })  : assert(softness > 0 && softness <= 2, 'softness must be in (0, 2]'),
        assert(intensity >= 0 && intensity <= 1, 'intensity must be in [0, 1]');

  /// A soft, wide source travelling gently down and to the right.
  const SeamLight.ambient()
      : period = const Duration(milliseconds: 1900),
        directionDegrees = 20,
        softness = 0.55,
        travel = 1.7,
        intensity = 0.9;

  /// A tighter, faster highlight closer to the classic sweep. Useful when
  /// migrating an existing design that people already recognise.
  const SeamLight.sweep()
      : period = const Duration(milliseconds: 1500),
        directionDegrees = 0,
        softness = 0.28,
        travel = 1.9,
        intensity = 1.0;

  /// How long one traversal takes.
  final Duration period;

  /// The direction the source travels, in degrees clockwise from horizontal.
  final double directionDegrees;

  /// Falloff width as a fraction of the scope's diagonal. Larger is softer.
  final double softness;

  /// How far beyond the scope the source travels, as a multiple of its size.
  /// Values above 1 give a pause between passes instead of a hard wrap.
  final double travel;

  /// Peak brightness, 0..1.
  final double intensity;

  /// Where the source sits within a scope of [scopeSize] at [phase] (0..1).
  Offset originAt(double phase, Size scopeSize) {
    final double radians = directionDegrees * math.pi / 180.0;
    final double dx = math.cos(radians);
    final double dy = math.sin(radians);

    // Travel along the direction vector, starting off one edge and ending off
    // the other, so bones near the edges are lit as fully as those in the
    // middle.
    final double span = (scopeSize.width.abs() + scopeSize.height.abs()) * travel;
    final double t = (phase * span) - (span - scopeSize.width) / 2;

    return Offset(
      t * dx.abs().clamp(0.2, 1.0) - scopeSize.width * (travel - 1) / 2,
      scopeSize.height / 2 + dy * (t - scopeSize.width / 2),
    );
  }

  /// How brightly a bone centred at [boneCenter] is lit, in 0..1.
  ///
  /// [boneCenter] and [scopeSize] are both in the scope's coordinate space, so
  /// two bones the same distance from the source are lit equally no matter how
  /// deep in the widget tree they live. That is what makes the light read as
  /// one source crossing a surface rather than an effect applied per widget.
  double luminanceAt(double phase, Offset boneCenter, Size scopeSize) {
    if (scopeSize.isEmpty) return 0;

    final Offset origin = originAt(phase, scopeSize);
    final double diagonal = math.sqrt(
      scopeSize.width * scopeSize.width + scopeSize.height * scopeSize.height,
    );
    final double reach = diagonal * softness;
    if (reach <= 0) return 0;

    // Distance is compressed on the cross-axis so the highlight reads as a
    // broad band rather than a circular spot, which at typical list widths
    // looks like a torch being shone at the screen.
    final double dx = boneCenter.dx - origin.dx;
    final double dy = (boneCenter.dy - origin.dy) * 0.45;
    final double distance = math.sqrt(dx * dx + dy * dy);

    final double raw = (1.0 - (distance / reach)).clamp(0.0, 1.0);
    // Smoothstep: no hard edge where the falloff reaches zero.
    return raw * raw * (3 - 2 * raw) * intensity;
  }

  /// The bone colour at [luminance], between [base] and [highlight].
  Color colorAt(double luminance, Color base, Color highlight) {
    return Color.lerp(base, highlight, luminance.clamp(0.0, 1.0)) ?? base;
  }

  /// Linearly interpolates between two lights.
  static SeamLight? lerp(SeamLight? a, SeamLight? b, double t) {
    if (a == null || b == null) return t < 0.5 ? a : b;
    return SeamLight(
      period: Duration(
        milliseconds: lerpDouble(
              a.period.inMilliseconds.toDouble(),
              b.period.inMilliseconds.toDouble(),
              t,
            )?.round() ??
            a.period.inMilliseconds,
      ),
      directionDegrees:
          lerpDouble(a.directionDegrees, b.directionDegrees, t) ?? a.directionDegrees,
      softness: lerpDouble(a.softness, b.softness, t) ?? a.softness,
      travel: lerpDouble(a.travel, b.travel, t) ?? a.travel,
      intensity: lerpDouble(a.intensity, b.intensity, t) ?? a.intensity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeamLight &&
      other.period == period &&
      other.directionDegrees == directionDegrees &&
      other.softness == softness &&
      other.travel == travel &&
      other.intensity == intensity;

  @override
  int get hashCode =>
      Object.hash(period, directionDegrees, softness, travel, intensity);
}
