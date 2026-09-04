import 'package:flutter/material.dart';
import 'package:seam/seam.dart';

import 'demo_lattice.dart';
import 'demo_live.dart';
import 'demo_measured.dart';
import 'demo_schedule.dart';
import 'demo_states.dart';
import 'movies.dart';

void main() => runApp(const SeamExampleApp());

/// One tab per idea the package is built on.
class SeamExampleApp extends StatelessWidget {
  /// Creates the example app.
  const SeamExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFB0741C)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFFF0AE4A),
        brightness: Brightness.dark,
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int _index = 0;

  // Owned here, not inside each demo. Swapping tabs disposes the demo's
  // State — and with it any memory the demo created — so a slot measured on
  // one visit would be a guess again on the next.
  final SeamMemory _latticeMemory = SeamMemory.inMemory();
  final SeamMemory _statesMemory = SeamMemory.inMemory();
  final SeamMemory _scheduleMemory = SeamMemory.inMemory();
  final SeamMemory _liveMemory = SeamMemory.inMemory();

  // Held here so its cache survives a tab switch — without that the stale
  // state is unreachable, because every visit would be a cold start.
  final MovieRepository _repository = MovieRepository();

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Bones tinted to the brand colour rather than neutral grey.
    // SeamPalette.from derives the lit end from the unlit one.
    final SeamPalette palette = SeamPalette.from(
      isDark ? const Color(0xFF4A3A1E) : const Color(0xFFE8D5AE),
      lift: isDark ? 0.22 : 0.55,
    );

    final List<Widget> pages = <Widget>[
      MeasuredDemo(palette: palette),
      LatticeDemo(palette: palette, memory: _latticeMemory),
      StatesDemo(palette: palette, memory: _statesMemory),
      ScheduleDemo(palette: palette, memory: _scheduleMemory),
      LiveDemo(
        palette: palette,
        memory: _liveMemory,
        repository: _repository,
      ),
    ];

    const List<String> titles = <String>[
      '1 · Measured bones',
      '2 · Lattice',
      '3 · Four states',
      '4 · Schedule',
      '5 · Live data',
    ];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.straighten_outlined),
            selectedIcon: Icon(Icons.straighten),
            label: 'Measured',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Lattice',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers),
            label: 'States',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud),
            label: 'Live',
          ),
        ],
      ),
    );
  }
}
