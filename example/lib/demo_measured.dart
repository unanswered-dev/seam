import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seam/seam.dart';

import 'shift_meter.dart';

/// Idea 1 — bones measured from real content, shown against bones that guess.
///
/// Both columns load identical data on identical timing. The only difference is
/// the memory: the left one is given [SeamMemory.none] so it can never learn a
/// shape, the right one remembers what it measured. The counters underneath
/// each column total how far the content below them was pushed.
class MeasuredDemo extends StatefulWidget {
  /// Creates the demo.
  const MeasuredDemo({super.key, required this.palette});

  /// Bone colours, shared across the demos.
  final SeamPalette palette;

  @override
  State<MeasuredDemo> createState() => _MeasuredDemoState();
}

class _MeasuredDemoState extends State<MeasuredDemo> {
  static const String _body =
      'Real content is three lines tall here. A placeholder that guessed one '
      'line will be short by two, and everything below it jumps when the text '
      'lands.';

  // The right-hand column keeps what it measures; the left cannot.
  final SeamMemory _remembering = SeamMemory.inMemory();
  static const SeamMemory _forgetful = SeamMemory.none();

  SeamValue<String> _title = const SeamValue<String>.absent();
  SeamValue<String> _body_ = const SeamValue<String>.absent();

  double _guessedShift = 0;
  double _measuredShift = 0;
  int _loads = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Warm the right-hand memory once so the very first tap already shows the
    // difference. Without this, load 1 legitimately jumps on both sides.
    _title = const SeamValue<String>.fresh('Measured, not guessed');
    _body_ = const SeamValue<String>.fresh(_body);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    _timer?.cancel();
    setState(() {
      _loads++;
      _guessedShift = 0;
      _measuredShift = 0;
      _title = const SeamValue<String>.absent();
      _body_ = const SeamValue<String>.absent();
    });
    _timer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() {
        _title = const SeamValue<String>.fresh('Measured, not guessed');
        _body_ = const SeamValue<String>.fresh(_body);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Bones measured, not guessed', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Identical data, identical timing. Only the memory differs. Watch the '
          'orange line under each column when the text lands.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        // Both columns are equalised with IntrinsicHeight, which asks the
        // placeholder for its intrinsic height. Bones answer that from the
        // memory during layout, so this no longer throws.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _Column(
                  label: 'Guesses every time',
                  sublabel: 'SeamMemory.none()',
                  memory: _forgetful,
                  palette: widget.palette,
                  title: _title,
                  body: _body_,
                  shift: _guessedShift,
                  bad: true,
                  onShift: (double d) => setState(() => _guessedShift += d),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Column(
                  label: 'Remembers the shape',
                  sublabel: 'SeamMemory.inMemory()',
                  memory: _remembering,
                  palette: widget.palette,
                  title: _title,
                  body: _body_,
                  shift: _measuredShift,
                  bad: false,
                  onShift: (double d) => setState(() => _measuredShift += d),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(_loads <= 1 ? 'Load' : 'Load again ($_loads)'),
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.label,
    required this.sublabel,
    required this.memory,
    required this.palette,
    required this.title,
    required this.body,
    required this.shift,
    required this.bad,
    required this.onShift,
  });

  final String label;
  final String sublabel;
  final SeamMemory memory;
  final SeamPalette palette;
  final SeamValue<String> title;
  final SeamValue<String> body;
  final double shift;
  final bool bad;
  final ValueChanged<double> onShift;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = bad ? const Color(0xFFA83A26) : const Color(0xFF276B51);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelLarge?.copyWith(color: tone)),
        Text(
          sublabel,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.hintColor,
          ),
        ),
        const SizedBox(height: 10),
        SeamScope(
          memory: memory,
          palette: palette,
          // Geometry is the variable under test here, not timing.
          schedule: const SeamSchedule.always(),
          child: ShiftMeter(
            onShift: onShift,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SeamSlot<String>(
                  id: 'measured.title',
                  value: title,
                  fallbackHeight: 18,
                  builder: (BuildContext c, String v) =>
                      Text(v, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: 10),
                SeamSlot<String>(
                  id: 'measured.body',
                  value: body,
                  // A deliberately optimistic guess: one line for three.
                  fallbackHeight: 16,
                  builder: (BuildContext c, String v) =>
                      Text(v, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
        // Everything below here is what gets pushed.
        Container(height: 3, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          'shifted ${shift.round()} px',
          style: theme.textTheme.labelMedium?.copyWith(
            color: tone,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
