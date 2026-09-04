import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';

const BoxConstraints w300 = BoxConstraints(maxWidth: 300);
const BoxConstraints w400 = BoxConstraints(maxWidth: 400);

void main() {
  group('SlotGeometry.appliesUnder', () {
    test('matches the width it was measured under', () {
      const SlotGeometry g =
          SlotGeometry(size: Size(300, 70), measuredUnder: w300);
      expect(g.appliesUnder(w300), isTrue);
    });

    test('refuses a different width, because text rewraps', () {
      // This is the guard against being confidently wrong. Geometry recorded
      // at 300pt says nothing about the same slot at 400pt.
      const SlotGeometry g =
          SlotGeometry(size: Size(300, 70), measuredUnder: w300);
      expect(g.appliesUnder(w400), isFalse);
    });

    test('tolerates sub-pixel drift', () {
      const SlotGeometry g =
          SlotGeometry(size: Size(300, 70), measuredUnder: w300);
      expect(g.appliesUnder(const BoxConstraints(maxWidth: 300.3)), isTrue);
    });

    test('an unbounded width never matches a bounded one', () {
      const SlotGeometry g =
          SlotGeometry(size: Size(300, 70), measuredUnder: w300);
      expect(g.appliesUnder(const BoxConstraints()), isFalse);
    });
  });

  group('SlotSamples', () {
    test('reports the median height, not the latest', () {
      final SlotSamples s = SlotSamples();
      for (final double h in <double>[50, 90, 60]) {
        s.record(SlotGeometry(size: Size(300, h), measuredUnder: w300));
      }
      expect(s.medianUnder(w300)!.height, 60);
    });

    test('averages the two middle samples when the count is even', () {
      final SlotSamples s = SlotSamples();
      for (final double h in <double>[50, 60, 70, 80]) {
        s.record(SlotGeometry(size: Size(300, h), measuredUnder: w300));
      }
      expect(s.medianUnder(w300)!.height, 65);
    });

    test('excludes samples measured under other constraints', () {
      final SlotSamples s = SlotSamples()
        ..record(const SlotGeometry(size: Size(300, 50), measuredUnder: w300))
        ..record(const SlotGeometry(size: Size(400, 999), measuredUnder: w400));
      expect(s.medianUnder(w300)!.height, 50);
    });

    test('returns null below minSamples', () {
      final SlotSamples s = SlotSamples()
        ..record(const SlotGeometry(size: Size(300, 50), measuredUnder: w300));
      expect(s.medianUnder(w300, minSamples: 3), isNull);
    });

    test('evicts oldest beyond capacity', () {
      final SlotSamples s = SlotSamples(capacity: 2);
      for (final double h in <double>[10, 20, 30]) {
        s.record(SlotGeometry(size: Size(300, h), measuredUnder: w300));
      }
      expect(s.samples.length, 2);
      expect(s.medianUnder(w300)!.height, 25);
    });

    test('heightVariance reports the observed spread', () {
      final SlotSamples s = SlotSamples()
        ..record(const SlotGeometry(size: Size(300, 40), measuredUnder: w300))
        ..record(const SlotGeometry(size: Size(300, 95), measuredUnder: w300));
      expect(s.heightVariance, 55);
    });
  });

  group('SeamMemory', () {
    test('records and reserves a measured size', () {
      final SeamMemory m = SeamMemory.inMemory();
      m.record('row.title', const Size(300, 74), w300);
      expect(m.reserveFor('row.title', w300), const Size(300, 74));
    });

    test('reserves nothing for a slot never measured', () {
      expect(SeamMemory.inMemory().reserveFor('unseen', w300), isNull);
    });

    test('reserves nothing under constraints it has not seen', () {
      final SeamMemory m = SeamMemory.inMemory();
      m.record('row.title', const Size(300, 74), w300);
      expect(m.reserveFor('row.title', w400), isNull);
    });

    test('refuses to predict a slot whose height varies wildly', () {
      // A feed of wildly different row heights has no shape worth asserting.
      // Guessing is honest; replaying a median that is wrong for most rows
      // reintroduces the reflow this exists to remove.
      final SeamMemory m = SeamMemory.inMemory(varianceTolerance: 20);
      m.record('feed.row', const Size(300, 40), w300);
      m.record('feed.row', const Size(300, 300), w300);
      expect(m.reserveFor('feed.row', w300), isNull);
    });

    test('still predicts a slot whose height is merely a little noisy', () {
      final SeamMemory m = SeamMemory.inMemory(varianceTolerance: 20);
      m.record('feed.row', const Size(300, 70), w300);
      m.record('feed.row', const Size(300, 78), w300);
      expect(m.reserveFor('feed.row', w300), isNotNull);
    });

    test('ignores degenerate sizes', () {
      final SeamMemory m = SeamMemory.inMemory();
      m.record('a', Size.zero, w300);
      m.record('b', const Size(300, double.infinity), w300);
      expect(m.reserveFor('a', w300), isNull);
      expect(m.reserveFor('b', w300), isNull);
    });

    test('forget drops one slot, clear drops all', () {
      final SeamMemory m = SeamMemory.inMemory();
      m.record('a', const Size(300, 10), w300);
      m.record('b', const Size(300, 20), w300);
      m.forget('a');
      expect(m.reserveFor('a', w300), isNull);
      expect(m.reserveFor('b', w300), isNotNull);
      m.clear();
      expect(m.reserveFor('b', w300), isNull);
    });

    test('SeamMemory.none records and reserves nothing', () {
      const SeamMemory m = SeamMemory.none();
      m.record('a', const Size(300, 10), w300);
      expect(m.reserveFor('a', w300), isNull);
    });
  });

  group('persistence', () {
    test('survives a round trip through a store', () async {
      final _FakeStore store = _FakeStore();
      final SeamMemory write = SeamMemory.persistent(
        store: store,
        writeDebounce: Duration.zero,
      );
      write.record('row.title', const Size(300, 74), w300);
      await write.flush();

      final SeamMemory read = SeamMemory.persistent(store: store);
      await read.load();
      expect(read.reserveFor('row.title', w300), const Size(300, 74));
    });

    test('a cold store leaves the memory guessing, not broken', () async {
      final SeamMemory m = SeamMemory.persistent(store: _FakeStore());
      await m.load();
      expect(m.reserveFor('anything', w300), isNull);
    });

    test('corrupt stored data is discarded rather than thrown', () async {
      final _FakeStore store = _FakeStore()..data = '{not json';
      final SeamMemory m = SeamMemory.persistent(store: store);
      await m.load();
      expect(m.reserveFor('anything', w300), isNull);
    });

    test('a failing store degrades to guessing', () async {
      final SeamMemory m = SeamMemory.persistent(store: _ThrowingStore());
      await m.load();
      expect(m.reserveFor('anything', w300), isNull);
    });

    test('an infinite constraint round-trips', () {
      const SlotGeometry g = SlotGeometry(
        size: Size(300, 70),
        measuredUnder: BoxConstraints(minWidth: 300),
      );
      final SlotGeometry? back = SlotGeometry.fromJson(g.toJson());
      expect(back, g);
      expect(back!.measuredUnder.maxWidth, double.infinity);
    });
  });
}

class _FakeStore implements SeamStore {
  String? data;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String value) async => data = value;
}

class _ThrowingStore implements SeamStore {
  @override
  Future<String?> read() async => throw StateError('disk unavailable');

  @override
  Future<void> write(String value) async => throw StateError('disk full');
}
