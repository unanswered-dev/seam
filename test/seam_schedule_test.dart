import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';

void main() {
  group('SeamSchedule.nng', () {
    const SeamSchedule s = SeamSchedule.nng();

    test('holds below 400ms', () {
      // Below this, a skeleton appears and vanishes as a flash, which measures
      // worse than showing nothing at all.
      expect(s.phaseAt(Duration.zero), SeamPhase.held);
      expect(s.phaseAt(const Duration(milliseconds: 399)), SeamPhase.held);
    });

    test('lights up through the band where skeletons help', () {
      expect(s.phaseAt(const Duration(milliseconds: 400)), SeamPhase.lit);
      expect(s.phaseAt(const Duration(milliseconds: 2999)), SeamPhase.lit);
    });

    test('escalates past 3s', () {
      expect(s.phaseAt(const Duration(seconds: 3)), SeamPhase.escalated);
      expect(s.phaseAt(const Duration(seconds: 30)), SeamPhase.escalated);
    });
  });

  group('SeamSchedule.always', () {
    const SeamSchedule s = SeamSchedule.always();

    test('lights immediately, matching every other package', () {
      expect(s.phaseAt(Duration.zero), SeamPhase.lit);
    });

    test('never escalates in any realistic load', () {
      expect(s.phaseAt(const Duration(minutes: 30)), SeamPhase.lit);
    });
  });

  group('nextBoundaryAfter', () {
    const SeamSchedule s = SeamSchedule.nng();

    test('counts down to the suppression threshold', () {
      expect(
        s.nextBoundaryAfter(const Duration(milliseconds: 100)),
        const Duration(milliseconds: 300),
      );
    });

    test('counts down to escalation once lit', () {
      expect(
        s.nextBoundaryAfter(const Duration(milliseconds: 400)),
        const Duration(milliseconds: 2600),
      );
    });

    test('is null once every threshold is behind us', () {
      expect(s.nextBoundaryAfter(const Duration(seconds: 5)), isNull);
    });
  });

  group('construction', () {
    test('is const-constructible with the default thresholds', () {
      // Duration comparison is not const-evaluable, so validation cannot live
      // in the constructor without making `const SeamSchedule()` uncompilable.
      const SeamSchedule s = SeamSchedule();
      expect(s.suppressBefore, const Duration(milliseconds: 400));
    });

    test('rejects a suppression later than escalation, when used', () {
      const SeamSchedule bad = SeamSchedule(
        suppressBefore: Duration(seconds: 5),
        escalateAfter: Duration(seconds: 1),
      );
      expect(() => bad.phaseAt(Duration.zero), throwsAssertionError);
    });

    test('equal schedules compare equal', () {
      expect(const SeamSchedule.nng(), const SeamSchedule());
    });
  });
}
