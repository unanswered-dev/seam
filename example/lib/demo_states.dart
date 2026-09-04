import 'package:flutter/material.dart';
import 'package:seam/seam.dart';

/// Idea 3 — four states, because two throw information away.
///
/// All four are on screen at once, pinned, so the difference between them is
/// visible rather than described. The one that matters most is `stale`: a
/// cached value shown degraded beats a grey box, because the reader can act on
/// it immediately.
class StatesDemo extends StatelessWidget {
  /// Creates the demo.
  const StatesDemo({super.key, required this.palette, required this.memory});

  /// Bone colours, shared across the demos.
  final SeamPalette palette;

  /// Owned by the app so it outlives a tab switch.
  final SeamMemory memory;

  static const String _full =
      'Skeleton screens only help between about 400 ms and 3 s. Outside that '
      'band they are neutral at best.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime sixDaysAgo =
        DateTime.now().subtract(const Duration(days: 6));

    return SeamScope(
      palette: palette,
      memory: memory,
      schedule: const SeamSchedule.always(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Four states, not two', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'A boolean can only express the first and the last of these.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          _StateCard(
            name: 'absent',
            note: 'No data. A bone — the measured shape, if one is known.',
            tone: theme.hintColor,
            value: const SeamValue<String>.absent(),
            slotId: 'states.absent',
          ),
          _StateCard(
            name: 'stale',
            note: 'Cached and out of date. Shown degraded, not hidden. The '
                'reader can act on it now.',
            tone: const Color(0xFF37608F),
            value: SeamValue<String>.stale(
              'Older copy: $_full',
              asOf: sixDaysAgo,
            ),
            slotId: 'states.stale',
            badge: 'CACHED · 6 days ago',
          ),
          _StateCard(
            name: 'partial',
            note: 'Still arriving. Rendered as far as it has got.',
            tone: theme.colorScheme.primary,
            value: SeamValue<String>.partial(
              _full.substring(0, 58),
              progress: 0.45,
            ),
            slotId: 'states.partial',
          ),
          _StateCard(
            name: 'fresh',
            note: 'Current and complete. The effect stops, and this is the '
                'only state Seam measures geometry from.',
            tone: const Color(0xFF276B51),
            value: const SeamValue<String>.fresh(_full),
            slotId: 'states.fresh',
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.name,
    required this.note,
    required this.tone,
    required this.value,
    required this.slotId,
    this.badge,
  });

  final String name;
  final String note;
  final Color tone;
  final SeamValue<String> value;
  final String slotId;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: tone, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(
                  'SeamValue.$name',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: tone, fontFamily: 'monospace'),
                ),
                if (badge != null) ...<Widget>[
                  const Spacer(),
                  Text(badge!,
                      style: theme.textTheme.labelSmall?.copyWith(color: tone)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SeamSlot<String>(
              id: slotId,
              value: value,
              fallbackHeight: 46,
              builder: (BuildContext c, String v) =>
                  Text(v, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 10),
            Text(note, style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}
