import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seam/seam.dart';

import 'movies.dart';

/// A load sequence to run against the real endpoint.
///
/// Each one performs an actual request; the difference is the shape of the
/// load around it, and therefore which state the list spends its time in.
enum LoadScenario {
  /// Cold start: nothing cached, so the list is bones until the response
  /// lands. What a first visit looks like.
  absent(
    'absent',
    'Cold start — opens as bones and stays there until the response lands, '
        'the way a first visit behaves.',
  ),

  /// Warm start: the cached rows stay on screen, degraded, while the refresh
  /// is in flight.
  stale(
    'stale',
    'Warm start — the cached rows stay readable and degraded while the '
        'refresh runs.',
  ),

  /// Streamed arrival: the response is real, but delivered in chunks so rows
  /// fill in over the bones the way a paginated feed does.
  partial(
    'partial',
    'Streamed arrival — real rows fill in over the bones, a page at a time.',
  ),

  /// No added latency. On a warm connection the response lands inside the
  /// 400 ms hold, and no bone is ever painted.
  fresh(
    'fresh',
    'Fast response — no added latency, so it can land inside the 400 ms hold '
        'and never paint a bone at all.',
  );

  const LoadScenario(this.label, this.description);

  /// Chip label.
  final String label;

  /// One line explaining what this sequence does.
  final String description;
}

/// All four states against a real endpoint, each driven by a real request.
class LiveDemo extends StatefulWidget {
  /// Creates the demo.
  const LiveDemo({
    super.key,
    required this.palette,
    required this.memory,
    required this.repository,
  });

  /// Bone colours, shared across the demos.
  final SeamPalette palette;

  /// Owned by the app so measurements outlive a tab switch.
  final SeamMemory memory;

  /// Owned by the app so its cache survives a tab switch.
  final MovieRepository repository;

  @override
  State<LiveDemo> createState() => _LiveDemoState();
}

class _LiveDemoState extends State<LiveDemo> {
  /// Rows to show before the feed's real length is known.
  static const int _skeletonRows = 8;

  /// Rows revealed per chunk in the streamed scenario.
  static const int _chunk = 6;

  /// Gap between chunks.
  static const Duration _chunkGap = Duration(milliseconds: 260);

  SeamValue<List<Movie>> _state = const SeamValue<List<Movie>>.absent();
  LoadScenario _scenario = LoadScenario.absent;
  Object? _error;
  bool _slowNetwork = true;
  int _loads = 0;

  /// The feed's length, once a response has told us. Lets the skeleton hold
  /// the right number of rows on every load after the first.
  int? _knownTotal;

  /// Guards against an older sequence finishing after a newer one started.
  int _runId = 0;

  final Stopwatch _clock = Stopwatch();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run(LoadScenario.absent);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Runs [scenario] for real: hits the endpoint and drives the list through
  /// the states that sequence produces.
  Future<void> _run(LoadScenario scenario) async {
    final int id = ++_runId;
    _tick?.cancel();
    _clock
      ..reset()
      ..start();
    // A light ticker so the elapsed readout moves; the effect has its own.
    _tick = Timer.periodic(const Duration(milliseconds: 100), (Timer t) {
      if (!mounted || id != _runId) return t.cancel();
      setState(() {});
    });

    final List<Movie>? cached = widget.repository.cached;

    setState(() {
      _scenario = scenario;
      _error = null;
      _loads++;
      // The opening state is the whole difference between these sequences.
      _state = switch (scenario) {
        // Pretend we have never been here: bones, even though a cache exists.
        LoadScenario.absent ||
        LoadScenario.partial ||
        LoadScenario.fresh =>
          const SeamValue<List<Movie>>.absent(),
        LoadScenario.stale => cached == null
            ? const SeamValue<List<Movie>>.absent()
            : SeamValue<List<Movie>>.stale(
                cached,
                asOf: widget.repository.cachedAt,
              ),
      };
    });

    try {
      final List<Movie> movies = await widget.repository.fetch(
        // The fast sequence is only meaningful without padding.
        extraLatency: (scenario == LoadScenario.fresh || !_slowNetwork)
            ? Duration.zero
            : const Duration(milliseconds: 1400),
      );
      if (!mounted || id != _runId) return;

      _knownTotal = movies.length;

      if (scenario == LoadScenario.partial) {
        // Real rows, delivered a page at a time over the bones already
        // holding their place.
        for (int shown = _chunk; shown < movies.length; shown += _chunk) {
          if (!mounted || id != _runId) return;
          setState(() {
            _state = SeamValue<List<Movie>>.partial(
              movies.sublist(0, shown),
              progress: shown / movies.length,
            );
          });
          await Future<void>.delayed(_chunkGap);
        }
      }

      if (!mounted || id != _runId) return;
      setState(() => _state = SeamValue<List<Movie>>.fresh(movies));
    } catch (error) {
      if (!mounted || id != _runId) return;
      setState(() {
        _error = error;
        _state = cached == null
            ? const SeamValue<List<Movie>>.absent()
            : SeamValue<List<Movie>>.stale(
                cached,
                asOf: widget.repository.cachedAt,
              );
      });
    } finally {
      if (mounted && id == _runId) {
        _tick?.cancel();
        _clock.stop();
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Movie>? movies = _state.valueOrNull;

    // Rows the feed has not delivered yet still hold their place, so a
    // streamed arrival fills in rather than growing the list.
    final int count = switch (_state) {
      SeamFresh<List<Movie>>(:final List<Movie> value) => value.length,
      SeamStale<List<Movie>>(:final List<Movie> value) => value.length,
      _ => _knownTotal ?? _skeletonRows,
    };

    return SeamScope(
      palette: widget.palette,
      memory: widget.memory,
      schedule: const SeamSchedule.nng(),
      child: Column(
        children: <Widget>[
          _Header(
            state: _state,
            scenario: _scenario,
            error: _error,
            loads: _loads,
            elapsedMs: _clock.elapsedMilliseconds,
            slowNetwork: _slowNetwork,
            onRun: _run,
            onToggleNetwork: (bool v) => setState(() => _slowNetwork = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: count,
              separatorBuilder: (BuildContext _, int _) =>
                  const Divider(height: 1, indent: 80),
              itemBuilder: (BuildContext context, int i) {
                final Movie? movie =
                    (movies != null && i < movies.length) ? movies[i] : null;
                return _MovieRow(index: i, movie: movie, listState: _state);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.scenario,
    required this.error,
    required this.loads,
    required this.elapsedMs,
    required this.slowNetwork,
    required this.onRun,
    required this.onToggleNetwork,
  });

  final SeamValue<List<Movie>> state;
  final LoadScenario scenario;
  final Object? error;
  final int loads;
  final int elapsedMs;
  final bool slowNetwork;
  final ValueChanged<LoadScenario> onRun;
  final ValueChanged<bool> onToggleNetwork;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final (String label, Color tone) = switch (state) {
      SeamAbsent<List<Movie>>() => ('absent · waiting', theme.hintColor),
      SeamStale<List<Movie>>(:final List<Movie> value) => (
          'stale · ${value.length} cached, refreshing',
          const Color(0xFF37608F)
        ),
      SeamPartial<List<Movie>>(:final List<Movie> value) => (
          'partial · ${value.length} rows in',
          theme.colorScheme.primary
        ),
      SeamFresh<List<Movie>>(:final List<Movie> value) => (
          'fresh · ${value.length} films',
          const Color(0xFF276B51)
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('api.sampleapis.com/movies/horror',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontFamily: 'monospace', color: theme.hintColor)),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: theme.textTheme.labelLarge?.copyWith(color: tone)),
              ),
              Text('$elapsedMs ms · load $loads',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.hintColor,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures()
                    ],
                  )),
            ],
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 6),
            Text('Could not reach the feed. Showing what was cached.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 8),
          // Each chip runs a real request; the sequence around it differs.
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final LoadScenario s in LoadScenario.values) ...<Widget>[
                  ChoiceChip(
                    label: Text(s.label),
                    selected: scenario == s,
                    onSelected: (_) => onRun(s),
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(scenario.description,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => onRun(scenario),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Run again'),
              ),
              const SizedBox(width: 8),
              Switch(
                value: slowNetwork,
                // The fast sequence defines itself by having no padding.
                onChanged: scenario == LoadScenario.fresh
                    ? null
                    : onToggleNetwork,
              ),
              Flexible(
                child:
                    Text('+1.4 s latency', style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovieRow extends StatelessWidget {
  const _MovieRow({
    required this.index,
    required this.movie,
    required this.listState,
  });

  final int index;
  final Movie? movie;
  final SeamValue<List<Movie>> listState;

  /// Projects the list's state onto one field of one row.
  ///
  /// Rows the feed has not reached yet stay `absent` even while the list as a
  /// whole is `partial` — which is exactly what a paginated feed looks like.
  SeamValue<String> _field(String? value) {
    if (value == null) return const SeamValue<String>.absent();
    return switch (listState) {
      SeamAbsent<List<Movie>>() => const SeamValue<String>.absent(),
      SeamStale<List<Movie>>(:final DateTime? asOf) =>
        SeamValue<String>.stale(value, asOf: asOf),
      // A row that has actually arrived is complete, even though the list
      // around it is not.
      SeamPartial<List<Movie>>() => SeamValue<String>.fresh(value),
      SeamFresh<List<Movie>>() => SeamValue<String>.fresh(value),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Posters share one slot id: every row is the same 2:3 box, so the
          // shape learned from the first row is right for all of them.
          SizedBox(
            width: 48,
            child: SeamSlot<String>(
              id: 'movie.poster',
              value: _field(movie?.posterUrl),
              fallbackHeight: 72,
              borderRadius: BorderRadius.circular(4),
              builder: (BuildContext c, String url) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    // A fixed box means a decoding image never reflows the row.
                    errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                        ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.movie_outlined,
                          size: 20, color: theme.hintColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Titles get a per-row id. Their lengths vary far too much for
                // one shared shape to be honest about — and when a slot's
                // observed heights spread past varianceTolerance, Seam declines
                // to predict at all rather than assert a median that is wrong
                // for most rows.
                SeamSlot<String>(
                  id: 'movie.title.$index',
                  value: _field(movie?.title),
                  fallbackHeight: 20,
                  builder: (BuildContext c, String title) => Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                SeamSlot<String>(
                  id: 'movie.meta',
                  value: _field(movie == null ? null : '#${movie!.id}'),
                  fallbackHeight: 14,
                  fallbackWidth: 72,
                  builder: (BuildContext c, String meta) => Text(
                    meta,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
