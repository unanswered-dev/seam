import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'slot_geometry.dart';

/// A key-value sink for persisting measured geometry.
///
/// The core package has no storage dependency. Supply an adapter over
/// `shared_preferences`, Hive, a file, or anything else, and pass it to
/// [SeamMemory.persistent].
abstract class SeamStore {
  /// Reads the previously written blob, or null on a cold start.
  Future<String?> read();

  /// Writes [data], replacing anything already stored.
  Future<void> write(String data);
}

/// Records the shape real content took, so the next skeleton is that shape.
///
/// This is the part of Seam that makes a skeleton stop being a guess. A slot
/// that has rendered real content at least once knows how tall it was; the
/// next time that slot loads, the placeholder reserves exactly that space and
/// the arrival moves nothing.
///
/// Two rules keep it from being confidently wrong, which would be worse than
/// guessing:
///
///  * geometry is filed against the constraints it was measured under, and is
///    never replayed under different ones (see [SlotGeometry.appliesUnder]);
///  * a slot whose observed heights vary by more than [varianceTolerance] is
///    treated as having no reliable shape, and Seam falls back to a guess.
abstract class SeamMemory {
  /// Const superclass constructor.
  const SeamMemory();

  /// An in-process memory. Nothing is written to disk.
  ///
  /// This is the default: it costs nothing, needs no dependency, and already
  /// removes reflow for every load after the first within a session.
  factory SeamMemory.inMemory({
    int capacity,
    int minSamples,
    double varianceTolerance,
  }) = _InMemorySeamMemory;

  /// A memory backed by [store], so the *first* load of a session is accurate.
  ///
  /// Call [SeamMemory.load] once during startup to hydrate it. Writes are
  /// debounced and fire and forget; a failed write degrades to guessing, never
  /// to an error.
  factory SeamMemory.persistent({
    required SeamStore store,
    int capacity,
    int minSamples,
    double varianceTolerance,
    Duration writeDebounce,
    void Function(Object error, StackTrace stack)? onError,
  }) = _PersistentSeamMemory;

  /// A memory that records nothing and returns nothing. Useful in tests and to
  /// disable the feature without changing the widget tree.
  const factory SeamMemory.none() = _NullSeamMemory;

  /// The size to reserve for [slotId] under [constraints], or null when Seam
  /// has no confident answer and the caller should fall back to a guess.
  Size? reserveFor(String slotId, BoxConstraints constraints);

  /// Records that real content in [slotId] occupied [size] under
  /// [constraints].
  ///
  /// Only ever called for `SeamFresh` content — recording a stale or partial
  /// render would teach the skeleton the wrong shape.
  void record(String slotId, Size size, BoxConstraints constraints);

  /// Hydrates from the backing store, if there is one. Safe to call always.
  Future<void> load() async {}

  /// Writes pending geometry to the backing store immediately, if there is
  /// one. Debounced writes make this a no-op for the in-memory variants.
  Future<void> flush() async {}

  /// Forgets everything recorded for [slotId].
  void forget(String slotId);

  /// Forgets everything.
  void clear();
}

class _NullSeamMemory extends SeamMemory {
  const _NullSeamMemory();

  @override
  Size? reserveFor(String slotId, BoxConstraints constraints) => null;

  @override
  void record(String slotId, Size size, BoxConstraints constraints) {}

  @override
  void forget(String slotId) {}

  @override
  void clear() {}
}

class _InMemorySeamMemory extends SeamMemory {
  _InMemorySeamMemory({
    this.capacity = 8,
    this.minSamples = 1,
    this.varianceTolerance = 24.0,
  });

  /// Observations retained per slot.
  final int capacity;

  /// Compatible observations required before a shape is asserted.
  final int minSamples;

  /// Height spread above which a slot is judged too variable to predict.
  final double varianceTolerance;

  @protected
  final Map<String, SlotSamples> slots = <String, SlotSamples>{};

  @override
  Size? reserveFor(String slotId, BoxConstraints constraints) {
    final SlotSamples? entry = slots[slotId];
    if (entry == null || entry.isEmpty) return null;

    // A slot whose content varies wildly has no shape worth asserting.
    // Guessing is honest; replaying a median that is wrong for most rows is
    // not, and it reintroduces the reflow this exists to remove.
    if (entry.heightVariance > varianceTolerance) return null;

    return entry.medianUnder(constraints, minSamples: minSamples);
  }

  @override
  void record(String slotId, Size size, BoxConstraints constraints) {
    if (!size.isFinite || size.isEmpty) return;
    final SlotSamples entry =
        slots.putIfAbsent(slotId, () => SlotSamples(capacity: capacity));
    entry.record(SlotGeometry(size: size, measuredUnder: constraints));
    onRecorded();
  }

  /// Hook for subclasses that persist. Called after every successful record.
  @protected
  void onRecorded() {}

  @override
  void forget(String slotId) {
    slots.remove(slotId);
    onRecorded();
  }

  @override
  void clear() {
    slots.clear();
    onRecorded();
  }
}

class _PersistentSeamMemory extends _InMemorySeamMemory {
  _PersistentSeamMemory({
    required this.store,
    super.capacity,
    super.minSamples,
    super.varianceTolerance,
    this.writeDebounce = const Duration(seconds: 2),
    this.onError,
  });

  /// Where the serialised geometry lives.
  final SeamStore store;

  /// How long to coalesce writes before touching the store.
  final Duration writeDebounce;

  /// Notified when the store cannot be read, decoded or written.
  ///
  /// Null by default, and failures are then silent on purpose: this is a cache
  /// of layout hints whose absence is already a fully supported state — Seam
  /// falls back to guessing. Routing that to crash reporting would be noise.
  /// Supply a callback if you want the visibility.
  final void Function(Object error, StackTrace stack)? onError;

  bool _flushScheduled = false;

  @override
  Future<void> load() async {
    String? raw;
    try {
      raw = await store.read();
    } catch (error, stack) {
      // A memory that cannot be read is a memory that guesses. That is the
      // designed fallback, not a failure worth propagating into startup.
      _report('read', error, stack);
      return;
    }
    if (raw == null || raw.isEmpty) return;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      slots.clear();
      decoded.forEach((Object? key, Object? value) {
        if (key is String) slots[key] = SlotSamples.fromJson(value);
      });
    } catch (error, stack) {
      _report('decode', error, stack);
      slots.clear();
    }
  }

  @override
  void onRecorded() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    Future<void>.delayed(writeDebounce, () async {
      _flushScheduled = false;
      await flush();
    });
  }

  /// Writes the current geometry to the store immediately.
  @override
  Future<void> flush() async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        for (final MapEntry<String, SlotSamples> e in slots.entries)
          e.key: e.value.toJson(),
      };
      await store.write(jsonEncode(payload));
    } catch (error, stack) {
      _report('write', error, stack);
    }
  }

  void _report(String phase, Object error, StackTrace stack) {
    assert(() {
      debugPrint('seam: could not $phase slot geometry ($error)');
      return true;
    }());
    onError?.call(error, stack);
  }
}
