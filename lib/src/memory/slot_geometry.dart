import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// One observation of the size real content actually occupied in a slot.
///
/// A skeleton is a claim about the shape of content that has not arrived. Seam
/// only makes that claim from something it measured, and only replays it under
/// the layout conditions it was measured in — [measuredUnder]. Geometry
/// recorded at one width says nothing about the same slot at another width,
/// because text rewraps.
@immutable
class SlotGeometry {
  /// Records that content of [size] was laid out under [measuredUnder].
  const SlotGeometry({required this.size, required this.measuredUnder});

  /// The size the real content occupied.
  final Size size;

  /// The constraints that layout was performed under.
  final BoxConstraints measuredUnder;

  /// Whether this observation can be replayed under [constraints].
  ///
  /// Width is what drives text wrapping, so incoming width bounds must match
  /// within [tolerance]. Height bounds are usually unbounded in scrollables
  /// and are deliberately not compared.
  bool appliesUnder(BoxConstraints constraints, {double tolerance = 0.5}) {
    bool near(double a, double b) {
      if (a == b) return true;
      if (a.isInfinite || b.isInfinite) return false;
      return (a - b).abs() <= tolerance;
    }

    return near(measuredUnder.maxWidth, constraints.maxWidth) &&
        near(measuredUnder.minWidth, constraints.minWidth);
  }

  /// Serialises to a JSON-compatible map for persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'w': size.width,
        'h': size.height,
        'cminW': _enc(measuredUnder.minWidth),
        'cmaxW': _enc(measuredUnder.maxWidth),
        'cminH': _enc(measuredUnder.minHeight),
        'cmaxH': _enc(measuredUnder.maxHeight),
      };

  /// Reads back a map produced by [toJson], or null if it is malformed.
  static SlotGeometry? fromJson(Object? json) {
    if (json is! Map) return null;
    final double? w = _num(json['w']);
    final double? h = _num(json['h']);
    if (w == null || h == null) return null;
    return SlotGeometry(
      size: Size(w, h),
      measuredUnder: BoxConstraints(
        minWidth: _dec(json['cminW']) ?? 0,
        maxWidth: _dec(json['cmaxW']) ?? double.infinity,
        minHeight: _dec(json['cminH']) ?? 0,
        maxHeight: _dec(json['cmaxH']) ?? double.infinity,
      ),
    );
  }

  static Object _enc(double v) => v.isFinite ? v : 'inf';
  static double? _dec(Object? v) => v == 'inf' ? double.infinity : _num(v);
  static double? _num(Object? v) => v is num ? v.toDouble() : null;

  @override
  bool operator ==(Object other) =>
      other is SlotGeometry &&
      other.size == size &&
      other.measuredUnder == measuredUnder;

  @override
  int get hashCode => Object.hash(size, measuredUnder);

  @override
  String toString() => 'SlotGeometry($size under $measuredUnder)';
}

/// The observations recorded for one slot id.
///
/// A slot rarely has *one* true size. A feed of article titles is a different
/// length in every row, and a skeleton built from a single observation would
/// be wrong for most of them. So a slot keeps a bounded window of recent
/// observations and reports their median, which is stable against outliers and
/// converges on the shape most rows actually have.
class SlotSamples {
  /// Creates an empty sample window holding at most [capacity] observations.
  SlotSamples({this.capacity = 8}) : assert(capacity > 0, 'capacity must be > 0');

  /// Maximum observations retained. Older ones are evicted first.
  final int capacity;

  final List<SlotGeometry> _samples = <SlotGeometry>[];

  /// The observations currently held, oldest first.
  List<SlotGeometry> get samples => List<SlotGeometry>.unmodifiable(_samples);

  /// Whether anything has been recorded.
  bool get isEmpty => _samples.isEmpty;

  /// Records one observation, evicting the oldest if at [capacity].
  void record(SlotGeometry geometry) {
    _samples.add(geometry);
    while (_samples.length > capacity) {
      _samples.removeAt(0);
    }
  }

  /// The median size of observations that apply under [constraints].
  ///
  /// Returns null when fewer than [minSamples] compatible observations exist —
  /// Seam guesses rather than replaying a shape it is not yet confident in.
  ///
  /// Width comes from the constraints rather than the samples when the slot is
  /// width-bounded, because that is what the real content will be handed.
  Size? medianUnder(BoxConstraints constraints, {int minSamples = 1}) {
    final List<SlotGeometry> usable = <SlotGeometry>[
      for (final SlotGeometry g in _samples)
        if (g.appliesUnder(constraints)) g,
    ];
    if (usable.length < minSamples) return null;

    final List<double> heights = <double>[
      for (final SlotGeometry g in usable) g.size.height,
    ]..sort();
    final List<double> widths = <double>[
      for (final SlotGeometry g in usable) g.size.width,
    ]..sort();

    return Size(_median(widths), _median(heights));
  }

  /// The spread of observed heights, as max minus min.
  ///
  /// High variance means measurement is a weak signal for this slot. Callers
  /// can use it to fall back to a guess instead of asserting a shape the
  /// content will usually contradict.
  double get heightVariance {
    if (_samples.length < 2) return 0;
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final SlotGeometry g in _samples) {
      lo = math.min(lo, g.size.height);
      hi = math.max(hi, g.size.height);
    }
    return hi - lo;
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final int mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Serialises the window for persistence.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'capacity': capacity,
        'samples': <Map<String, dynamic>>[
          for (final SlotGeometry g in _samples) g.toJson(),
        ],
      };

  /// Reads back a map produced by [toJson], skipping malformed entries.
  static SlotSamples fromJson(Object? json) {
    final int capacity =
        (json is Map && json['capacity'] is num) ? (json['capacity'] as num).toInt() : 8;
    final SlotSamples out = SlotSamples(capacity: capacity > 0 ? capacity : 8);
    if (json is Map && json['samples'] is List) {
      for (final Object? raw in json['samples'] as List<Object?>) {
        final SlotGeometry? g = SlotGeometry.fromJson(raw);
        if (g != null) out.record(g);
      }
    }
    return out;
  }
}
