import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seam/seam.dart';

/// Idea 2 — loading is a lattice, not a bit.
///
/// The same four fields arrive on the same schedule in both modes. With one
/// boolean, every field waits for the slowest; with a lattice, each resolves
/// the moment its own data lands.
class LatticeDemo extends StatefulWidget {
  /// Creates the demo.
  const LatticeDemo({super.key, required this.palette, required this.memory});

  /// Bone colours, shared across the demos.
  final SeamPalette palette;

  /// Owned by the app so it outlives a tab switch.
  final SeamMemory memory;

  @override
  State<LatticeDemo> createState() => _LatticeDemoState();
}

class _LatticeDemoState extends State<LatticeDemo> {
  static const String _body =
      'The body streams in a few words at a time, so it spends most of the '
      'load in the partial state rather than flipping from nothing to '
      'everything.';

  static const int _avatarAt = 600;
  static const int _titleAt = 900;
  static const int _bodyFrom = 1400;
  static const int _bodyTo = 2200;
  static const int _statsAt = 2600;

  // Opens on the boolean model deliberately: show the problem first, then let
  // the switch to a lattice be the thing the viewer does.
  bool _lattice = false;
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;

  /// One frame of real content, so every slot is measured before the first
  /// skeleton is ever shown. Without it the opening load has nothing to
  /// reserve against and the card grows as the text lands.
  bool _priming = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _priming = false);
      _run();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _run() {
    _ticker?.cancel();
    _clock
      ..reset()
      ..start();
    // A coarse ticker is enough: the demo only needs to re-derive which fields
    // have landed, not to animate anything. The light has its own ticker.
    _ticker = Timer.periodic(const Duration(milliseconds: 60), (Timer t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (_clock.elapsedMilliseconds > _statsAt + 400) t.cancel();
    });
  }

  int get _ms => _clock.elapsedMilliseconds;

  /// In boolean mode every field is gated on the slowest one.
  bool get _allIn => _ms >= _statsAt;

  SeamValue<String> _gate(int at, String value) {
    if (_priming) return SeamValue<String>.fresh(value);
    if (_lattice) {
      return _ms >= at
          ? SeamValue<String>.fresh(value)
          : const SeamValue<String>.absent();
    }
    return _allIn
        ? SeamValue<String>.fresh(value)
        : const SeamValue<String>.absent();
  }

  SeamValue<String> get _bodyValue {
    if (_priming) return const SeamValue<String>.fresh(_body);
    if (!_lattice) {
      return _allIn
          ? const SeamValue<String>.fresh(_body)
          : const SeamValue<String>.absent();
    }
    if (_ms < _bodyFrom) return const SeamValue<String>.absent();
    if (_ms >= _bodyTo) return const SeamValue<String>.fresh(_body);
    final double p = (_ms - _bodyFrom) / (_bodyTo - _bodyFrom);
    return SeamValue<String>.partial(
      _body.substring(0, (_body.length * p).round()),
      progress: p,
    );
  }

  int get _resolved {
    if (!_lattice) return _allIn ? 4 : 0;
    int n = 0;
    if (_ms >= _avatarAt) n++;
    if (_ms >= _titleAt) n++;
    if (_ms >= _bodyTo) n++;
    if (_ms >= _statsAt) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Loading is a lattice, not a bit',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Same arrival times in both modes. One boolean makes every field wait '
          'for the slowest source.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text('One boolean')),
            ButtonSegment<bool>(value: true, label: Text('A lattice')),
          ],
          selected: <bool>{_lattice},
          onSelectionChanged: (Set<bool> s) {
            setState(() => _lattice = s.first);
            _run();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Text('${_ms.clamp(0, 9999)} ms',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures()
                  ],
                )),
            const Spacer(),
            Text('resolved $_resolved/4',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _resolved / 4),
        const SizedBox(height: 20),
        SeamScope(
          palette: widget.palette,
          memory: widget.memory,
          schedule: const SeamSchedule.always(),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 44,
                        child: SeamSlot<String>(
                          id: 'lattice.avatar',
                          value: _gate(_avatarAt, 'SM'),
                          fallbackHeight: 44,
                          borderRadius: BorderRadius.circular(22),
                          builder: (BuildContext c, String v) => CircleAvatar(
                            radius: 22,
                            backgroundColor: theme.colorScheme.primary,
                            child: Text(v,
                                style: TextStyle(
                                    color: theme.colorScheme.onPrimary)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SeamSlot<String>(
                          id: 'lattice.title',
                          value: _gate(_titleAt, 'Sana Mir'),
                          fallbackHeight: 20,
                          builder: (BuildContext c, String v) =>
                              Text(v, style: theme.textTheme.titleMedium),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SeamSlot<String>(
                    id: 'lattice.body',
                    value: _bodyValue,
                    fallbackHeight: 54,
                    builder: (BuildContext c, String v) =>
                        Text(v, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(height: 16),
                  SeamSlot<String>(
                    id: 'lattice.stats',
                    value: _gate(_statsAt, '124 · 38 · 9'),
                    fallbackHeight: 20,
                    builder: (BuildContext c, String v) => Text(v,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _Timeline(ms: _ms, lattice: _lattice),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh),
            label: const Text('Replay'),
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.ms, required this.lattice});

  final int ms;
  final bool lattice;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const List<(String, int)> marks = <(String, int)>[
      ('avatar', 600),
      ('title', 900),
      ('body', 2200),
      ('stats', 2600),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final (String name, int at) in marks)
          Builder(builder: (BuildContext c) {
            // In boolean mode nothing counts as landed until the last source.
            final bool landed = lattice ? ms >= at : ms >= 2600;
            return Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                landed ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: landed ? theme.colorScheme.primary : theme.hintColor,
              ),
              label: Text('$name ${at}ms',
                  style: theme.textTheme.labelSmall),
            );
          }),
      ],
    );
  }
}
