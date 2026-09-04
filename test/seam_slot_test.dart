import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';

/// The height the "real" content occupies. A naive placeholder would guess
/// something else, and that difference is the reflow.
const double kContentHeight = 74;
const double kSlotWidth = 300;

Widget harness({
  required SeamValue<String> value,
  SeamMemory? memory,
  SeamSchedule schedule = const SeamSchedule.always(),
  String id = 'article.body',
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SeamScope(
      memory: memory,
      schedule: schedule,
      child: Center(
        child: SizedBox(
          width: kSlotWidth,
          child: SeamSlot<String>(
            id: id,
            value: value,
            fallbackHeight: 16,
            builder: (BuildContext context, String v) => SizedBox(
              height: kContentHeight,
              child: Text(v),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('state rendering', () {
    testWidgets('absent renders a bone, not content', (WidgetTester t) async {
      await t.pumpWidget(harness(value: const SeamValue<String>.absent()));
      expect(find.byType(SeamBone), findsOneWidget);
      expect(find.text('hello'), findsNothing);
    });

    testWidgets('fresh renders content, not a bone', (WidgetTester t) async {
      await t.pumpWidget(harness(value: const SeamValue<String>.fresh('hello')));
      expect(find.byType(SeamBone), findsNothing);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('stale renders the cached value rather than a bone',
        (WidgetTester t) async {
      // The whole point of the stale state: showing week-old text beats
      // showing a grey box, because the reader can act on it now.
      await t.pumpWidget(harness(value: const SeamValue<String>.stale('old')));
      expect(find.byType(SeamBone), findsNothing);
      expect(find.text('old'), findsOneWidget);
    });

    testWidgets('stale content is visibly degraded', (WidgetTester t) async {
      await t.pumpWidget(harness(value: const SeamValue<String>.stale('old')));
      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('partial renders what has arrived so far',
        (WidgetTester t) async {
      await t.pumpWidget(
        harness(value: const SeamValue<String>.partial('half a sen')),
      );
      expect(find.byType(SeamBone), findsNothing);
      expect(find.text('half a sen'), findsOneWidget);
    });
  });

  group('measurement — the arrival must move nothing', () {
    testWidgets('a second load reserves the height the content actually took',
        (WidgetTester t) async {
      final SeamMemory memory = SeamMemory.inMemory();

      // First load: render real content so there is something to measure.
      await t.pumpWidget(harness(
        value: const SeamValue<String>.fresh('hello'),
        memory: memory,
      ));
      await t.pump();
      final Size contentSize = t.getSize(find.byType(SeamSlot<String>));
      expect(contentSize.height, kContentHeight);

      // Second load of the same slot: the placeholder should already be the
      // shape the content will be.
      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        memory: memory,
      ));
      await t.pump();

      final Size boneSize = t.getSize(find.byType(SeamBone));
      expect(boneSize.height, kContentHeight,
          reason: 'the bone should be the measured height, not the fallback');

      // And the arrival is then a no-op for layout: content is the same size
      // the placeholder already occupied. That is the reflow, removed.
      await t.pumpWidget(harness(
        value: const SeamValue<String>.fresh('hello'),
        memory: memory,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamSlot<String>)), boneSize);
    });

    testWidgets('the first ever load falls back to a guess',
        (WidgetTester t) async {
      // Honest behaviour: with nothing measured there is nothing to assert.
      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        memory: SeamMemory.inMemory(),
      ));
      expect(t.getSize(find.byType(SeamBone)).height, 16);
    });

    testWidgets('geometry is not shared between different slot ids',
        (WidgetTester t) async {
      final SeamMemory memory = SeamMemory.inMemory();
      await t.pumpWidget(harness(
        value: const SeamValue<String>.fresh('hello'),
        memory: memory,
        id: 'article.body',
      ));
      await t.pump();

      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        memory: memory,
        id: 'article.title',
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamBone)).height, 16);
    });

    testWidgets('stale content is never measured', (WidgetTester t) async {
      // Recording the shape of out-of-date content would teach the skeleton
      // the wrong shape for the content that is actually coming.
      final SeamMemory memory = SeamMemory.inMemory();
      await t.pumpWidget(harness(
        value: const SeamValue<String>.stale('old'),
        memory: memory,
      ));
      await t.pump();

      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        memory: memory,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamBone)).height, 16);
    });
  });

  group('schedule', () {
    testWidgets('paints nothing below the suppression threshold',
        (WidgetTester t) async {
      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        schedule: const SeamSchedule.nng(),
      ));

      // Held: the bone exists and reserves space, but does not paint. A load
      // that finishes inside this window never flashes a skeleton.
      expect(t.widget<SeamBone>(find.byType(SeamBone)).lit, isFalse);
      expect(t.getSize(find.byType(SeamBone)).height, 16);
    });

    testWidgets('lights up once inside the band', (WidgetTester t) async {
      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        schedule: const SeamSchedule.nng(),
      ));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.widget<SeamBone>(find.byType(SeamBone)).lit, isTrue);

      // Let the escalation timer fire so the test ends with no pending work.
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('a load that resolves during suppression never paints a bone',
        (WidgetTester t) async {
      await t.pumpWidget(harness(
        value: const SeamValue<String>.absent(),
        schedule: const SeamSchedule.nng(),
      ));
      expect(t.widget<SeamBone>(find.byType(SeamBone)).lit, isFalse);

      await t.pump(const Duration(milliseconds: 200));
      await t.pumpWidget(harness(
        value: const SeamValue<String>.fresh('fast'),
        schedule: const SeamSchedule.nng(),
      ));
      expect(find.byType(SeamBone), findsNothing);
      expect(find.text('fast'), findsOneWidget);
    });
  });

  _reserveTests();

  group('scope', () {
    testWidgets('a slot works with no scope above it', (WidgetTester t) async {
      // Adoption must not begin with a root-level edit.
      await t.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: kSlotWidth,
              child: SeamSlot<String>(
                id: 'standalone',
                value: SeamValue<String>.absent(),
                builder: _text,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SeamBone), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('bones share one controller under a scope',
        (WidgetTester t) async {
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SeamScope(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < 3; i++)
                  SizedBox(
                    width: kSlotWidth,
                    child: SeamSlot<String>(
                      id: 'row.$i',
                      value: const SeamValue<String>.absent(),
                      builder: _text,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));

      final Iterable<SeamBone> bones =
          t.widgetList<SeamBone>(find.byType(SeamBone));
      expect(bones.length, 3);
      // One light means one phase: there is nothing here that *can* drift.
      final SeamController first = bones.first.controller;
      expect(bones.every((SeamBone b) => identical(b.controller, first)), isTrue);

      await t.pump(const Duration(seconds: 3));
    });
  });
}

Widget _text(BuildContext context, String value) => Text(value);

// ---------------------------------------------------------------------------
// Reserving while resolving.
// ---------------------------------------------------------------------------

Widget reserveHarness({
  required SeamValue<String> value,
  required SeamMemory memory,
  bool reserve = true,
  double contentHeight = kContentHeight,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SeamScope(
      memory: memory,
      schedule: const SeamSchedule.always(),
      child: Center(
        child: SizedBox(
          width: kSlotWidth,
          child: SeamSlot<String>(
            id: 'article.body',
            value: value,
            reserveWhileResolving: reserve,
            builder: (BuildContext context, String v) =>
                SizedBox(height: contentHeight, child: Text(v)),
          ),
        ),
      ),
    ),
  );
}

void _reserveTests() {
  group('reserving while resolving', () {
    testWidgets('partial content is held at the measured height',
        (WidgetTester t) async {
      final SeamMemory memory = SeamMemory.inMemory();

      // Measure the full-size content once.
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.fresh('all of it'),
        memory: memory,
      ));
      await t.pump();

      // Streaming arrives short. Without a floor the slot would shrink to 20
      // and drag everything below it up the screen.
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.partial('half'),
        memory: memory,
        contentHeight: 20,
      ));
      await t.pump();

      expect(t.getSize(find.byType(SeamSlot<String>)).height, kContentHeight);
    });

    testWidgets('stale content is held at the measured height too',
        (WidgetTester t) async {
      final SeamMemory memory = SeamMemory.inMemory();
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.fresh('all of it'),
        memory: memory,
      ));
      await t.pump();

      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.stale('older'),
        memory: memory,
        contentHeight: 20,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamSlot<String>)).height, kContentHeight);
    });

    testWidgets('content taller than the reservation is never clipped',
        (WidgetTester t) async {
      final SeamMemory memory = SeamMemory.inMemory();
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.fresh('all of it'),
        memory: memory,
      ));
      await t.pump();

      // A floor, not a fixed height.
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.partial('lots more'),
        memory: memory,
        contentHeight: 200,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamSlot<String>)).height, 200);
    });

    testWidgets('fresh content is never floored', (WidgetTester t) async {
      // Fresh is the truth everything else is measured against; flooring it
      // would let one long render pin the slot tall forever.
      final SeamMemory memory = SeamMemory.inMemory();
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.fresh('all of it'),
        memory: memory,
      ));
      await t.pump();

      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.fresh('shorter now'),
        memory: memory,
        contentHeight: 20,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamSlot<String>)).height, 20);
    });

    testWidgets('reserveWhileResolving: false opts out', (WidgetTester t) async {
      final SeamMemory memory = SeamMemory.inMemory();
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.fresh('all of it'),
        memory: memory,
      ));
      await t.pump();

      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.partial('half'),
        memory: memory,
        reserve: false,
        contentHeight: 20,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamSlot<String>)).height, 20);
    });

    testWidgets('an unmeasured slot reserves nothing', (WidgetTester t) async {
      await t.pumpWidget(reserveHarness(
        value: const SeamValue<String>.partial('half'),
        memory: SeamMemory.inMemory(),
        contentHeight: 20,
      ));
      await t.pump();
      expect(t.getSize(find.byType(SeamSlot<String>)).height, 20);
    });
  });
}
