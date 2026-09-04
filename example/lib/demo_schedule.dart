import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seam/seam.dart';

/// Idea 4 — the effect knows what time it is.
///
/// Three loads of different lengths against the same schedule. The fast one
/// finishes inside the suppression window and never paints a bone at all,
/// which is the behaviour no other package offers.
class ScheduleDemo extends StatefulWidget {
  /// Creates the demo.
  const ScheduleDemo({super.key, required this.palette, required this.memory});

  /// Bone colours, shared across the demos.
  final SeamPalette palette;

  /// Owned by the app so it outlives a tab switch.
  final SeamMemory memory;

  @override
  State<ScheduleDemo> createState() => _ScheduleDemoState();
}

class _ScheduleDemoState extends State<ScheduleDemo> {
  static const SeamSchedule _schedule = SeamSchedule.nng();

  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  int _duration = 1500;
  // Starts settled: one frame of real content measures every line before the
  // first skeleton appears, so the card never grows as text lands.
  bool _done = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run(1500);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _run(int ms) {
    _ticker?.cancel();
    setState(() {
      _duration = ms;
      _done = false;
    });
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (Timer t) {
      if (!mounted) return t.cancel();
      if (_clock.elapsedMilliseconds >= _duration && !_done) {
        setState(() => _done = true);
        t.cancel();
        return;
      }
      setState(() {});
    });
  }

  SeamPhase get _phase => _done
      ? SeamPhase.settled
      : _schedule.phaseAt(Duration(milliseconds: _clock.elapsedMilliseconds));

  /// Distinct copy per line, so the card reads as content rather than filler.
  String _lines(int i) => switch (i) {
        0 => 'Loaded in $_duration ms.',
        1 => _duration < 400
            ? 'The schedule was still held, so no bone was drawn.'
            : 'The schedule lit at 400 ms and stopped on arrival.',
        _ => 'Space stayed reserved throughout either way.',
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('The effect knows what time it is',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Skeletons only help between about 400 ms and 3 s. Below that a '
          'skeleton is a flash that feels worse than nothing.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _RunButton(
                label: '180 ms', onTap: () => _run(180), active: _duration == 180),
            _RunButton(
                label: '1.5 s', onTap: () => _run(1500), active: _duration == 1500),
            _RunButton(
                label: '6 s', onTap: () => _run(6000), active: _duration == 6000),
          ],
        ),
        const SizedBox(height: 18),
        _PhaseStrip(phase: _phase),
        const SizedBox(height: 10),
        Text(
          '${_done ? _duration : _clock.elapsedMilliseconds} ms · ${_phase.name}',
          style: theme.textTheme.labelMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 16),
        SeamScope(
          palette: widget.palette,
          memory: widget.memory,
          schedule: _schedule,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < 3; i++) ...<Widget>[
                    SeamSlot<String>(
                      id: 'schedule.line$i',
                      value: _done
                          ? SeamValue<String>.fresh(_lines(i))
                          : const SeamValue<String>.absent(),
                      fallbackHeight: 16,
                      builder: (BuildContext c, String v) =>
                          Text(v, style: theme.textTheme.bodyMedium),
                    ),
                    if (i < 2) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _duration == 180
                ? 'At 180 ms the load finishes while the schedule is still '
                    'held, so no bone is ever drawn. The space stays reserved.'
                : _duration == 6000
                    ? 'Past 3 s the phase escalates: a shimmer still looping '
                        'here reads as a hang, not as progress.'
                    : 'A 1.5 s load sits inside the band, which is the only '
                        'window where a skeleton measurably helps.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton(
      {required this.label, required this.onTap, required this.active});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return active
        ? FilledButton(onPressed: onTap, child: Text(label))
        : OutlinedButton(onPressed: onTap, child: Text(label));
  }
}

class _PhaseStrip extends StatelessWidget {
  const _PhaseStrip({required this.phase});

  final SeamPhase phase;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const List<(SeamPhase, String, String)> rows =
        <(SeamPhase, String, String)>[
      (SeamPhase.held, 'held', '0–400ms'),
      (SeamPhase.lit, 'lit', '400ms–3s'),
      (SeamPhase.escalated, 'escalated', '3s+'),
      (SeamPhase.settled, 'settled', 'done'),
    ];

    return Row(
      children: <Widget>[
        for (final (SeamPhase p, String name, String window) in rows)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: p == phase
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: <Widget>[
                  Text(name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight:
                            p == phase ? FontWeight.bold : FontWeight.normal,
                      )),
                  Text(window,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor, fontSize: 9)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
