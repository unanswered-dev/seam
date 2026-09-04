import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';

void main() {
  group('SeamValue states', () {
    test('absent carries nothing and is resolving', () {
      const SeamValue<String> v = SeamValue<String>.absent();
      expect(v.valueOrNull, isNull);
      expect(v.hasValue, isFalse);
      expect(v.isFresh, isFalse);
      expect(v.isResolving, isTrue);
    });

    test('stale carries a value and is still resolving', () {
      final DateTime asOf = DateTime(2026, 8, 29);
      final SeamValue<String> v = SeamValue<String>.stale('old', asOf: asOf);
      expect(v.valueOrNull, 'old');
      expect(v.hasValue, isTrue);
      // A stale value is readable, but a refresh is still outstanding — the
      // effect should keep indicating activity.
      expect(v.isResolving, isTrue);
      expect(v.isFresh, isFalse);
    });

    test('partial carries what has arrived so far', () {
      const SeamValue<String> v = SeamValue<String>.partial('half', progress: 0.5);
      expect(v.valueOrNull, 'half');
      expect(v.isResolving, isTrue);
    });

    test('fresh is the only settled state', () {
      const SeamValue<String> v = SeamValue<String>.fresh('done');
      expect(v.valueOrNull, 'done');
      expect(v.isFresh, isTrue);
      expect(v.isResolving, isFalse);
    });
  });

  group('resolvedFraction', () {
    test('stale contributes no progress toward the new value', () {
      // Stale data is useful to a reader but is not progress: the request that
      // will replace it has not advanced at all.
      expect(const SeamValue<int>.stale(1).resolvedFraction, 0.0);
    });

    test('absent is zero and fresh is one', () {
      expect(const SeamValue<int>.absent().resolvedFraction, 0.0);
      expect(const SeamValue<int>.fresh(1).resolvedFraction, 1.0);
    });

    test('partial uses its hint, defaulting to a half', () {
      expect(const SeamValue<int>.partial(1, progress: 0.25).resolvedFraction, 0.25);
      expect(const SeamValue<int>.partial(1).resolvedFraction, 0.5);
    });

    test('partial clamps an out-of-range hint', () {
      expect(const SeamValue<int>.partial(1, progress: 4).resolvedFraction, 1.0);
      expect(const SeamValue<int>.partial(1, progress: -2).resolvedFraction, 0.0);
    });
  });

  group('mapValue', () {
    test('preserves the state while transforming the value', () {
      final DateTime asOf = DateTime(2026);
      final SeamValue<int> stale = SeamValue<String>.stale('12', asOf: asOf)
          .mapValue<int>(int.parse);
      expect(stale, isA<SeamStale<int>>());
      expect(stale.valueOrNull, 12);
      expect((stale as SeamStale<int>).asOf, asOf);
    });

    test('absent stays absent', () {
      final SeamValue<int> mapped =
          const SeamValue<String>.absent().mapValue<int>(int.parse);
      expect(mapped, isA<SeamAbsent<int>>());
    });

    test('carries the progress hint through', () {
      final SeamValue<int> mapped =
          const SeamValue<String>.partial('7', progress: 0.3)
              .mapValue<int>(int.parse);
      expect((mapped as SeamPartial<int>).progress, 0.3);
    });
  });

  group('when', () {
    test('dispatches to the matching branch', () {
      String describe(SeamValue<String> v) => v.when(
            absent: () => 'absent',
            stale: (String value, DateTime? asOf) => 'stale:$value',
            partial: (String value, double? progress) => 'partial:$value',
            fresh: (String value) => 'fresh:$value',
          );

      expect(describe(const SeamValue<String>.absent()), 'absent');
      expect(describe(const SeamValue<String>.stale('a')), 'stale:a');
      expect(describe(const SeamValue<String>.partial('b')), 'partial:b');
      expect(describe(const SeamValue<String>.fresh('c')), 'fresh:c');
    });
  });

  group('equality', () {
    test('same state and value compare equal', () {
      expect(const SeamValue<int>.fresh(1), const SeamValue<int>.fresh(1));
      expect(const SeamValue<int>.absent(), const SeamValue<int>.absent());
    });

    test('different states never compare equal', () {
      expect(
        const SeamValue<int>.fresh(1) == const SeamValue<int>.stale(1),
        isFalse,
      );
    });

    test('a differing progress hint is a differing value', () {
      expect(
        const SeamValue<int>.partial(1, progress: 0.1) ==
            const SeamValue<int>.partial(1, progress: 0.9),
        isFalse,
      );
    });
  });
}
