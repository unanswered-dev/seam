# seam

Loading states that don't lie.

Every skeleton package tells the user two lies. Seam is built to stop telling both.

**Lie 1 — "I know what shape the content will be."** A grey box is a guess about
the size of content that hasn't arrived. When the guess is wrong, the arrival
reflows the layout. This is the most common complaint about skeleton screens,
and generic placeholder boxes cause it.

**Lie 2 — "Loading is a boolean."** That fit one request and one wait. It cannot
express "the title is here, the body is streaming, the image is still decoding",
which is how content actually arrives now.

```dart
SeamSlot<String>(
  id: 'article.body',
  value: vm.body,           // absent | stale | partial | fresh
  builder: (context, body) => Text(body),
)
```

---

## What it does differently

### Bones are measured, not guessed

A slot renders real content at least once. Seam records the size that content
occupied, files it against the constraints it was measured under, and reserves
exactly that space the next time the slot loads. The arrival moves nothing.

```dart
SeamScope(
  memory: SeamMemory.inMemory(),   // or .persistent(store: ...) to survive restarts
  child: MyApp(),
)
```

The first load of a brand-new slot still guesses — there's nothing to measure
yet. In a list, the first row teaches Seam the shape of every row after it.

Two rules stop it from being *confidently* wrong, which would be worse than
guessing:

- geometry recorded at one width is never replayed at another, because text
  rewraps;
- a slot whose observed heights vary more than `varianceTolerance` is treated as
  having no reliable shape, and Seam falls back to a guess.

### Streamed content holds its place

Removing the reflow on arrival is only half of it. Content that arrives in
pieces starts short and grows, which drags everything below it up the screen
and then back down — the same reflow, just spread over a second.

So a slot that has been measured keeps reserving that height until its value is
`fresh`. Streamed text fills into space already held instead of pushing the
page around.

```dart
SeamSlot<String>(
  id: 'article.body',
  value: vm.body,                  // partial while the response streams
  reserveWhileResolving: true,     // the default
  builder: (context, body) => Text(body),
)
```

Three rules keep it honest:

- **`fresh` is never floored.** It is the truth everything else is measured
  against; flooring it would let one long render pin a slot tall forever.
- **It is a floor, not a fixed height.** Content taller than the reservation is
  never clipped.
- **An unmeasured slot reserves nothing.** No invented geometry.

Set `reserveWhileResolving: false` for a slot whose content legitimately
changes size between loads, where a floor would leave visible dead space.

### Loading is a lattice, not a bit

Each slot owns one field and resolves independently. Nothing above it holds the
screen hostage to its slowest source, which is what a streamed response needs.

```dart
SeamSlot<String>(id: 'title', value: vm.title, builder: ...)  // lands at 900ms
SeamSlot<String>(id: 'body',  value: vm.body,  builder: ...)  // still streaming
```

### Four states, because two throw information away

```dart
sealed class SeamValue<T> {
  const factory SeamValue.absent()                        // no data — show a bone
  const factory SeamValue.stale(T value, {DateTime? asOf}) // cached — show it, degraded
  const factory SeamValue.partial(T value, {double? progress}) // streaming
  const factory SeamValue.fresh(T value)                  // current — and measured
}
```

When a cache holds last week's article, showing grey boxes is strictly worse
than showing last week's article. `stale` renders the real value dimmed and
desaturated so it reads as out of date without being hidden. SwiftUI has drawn
this distinction since iOS 14 (`.placeholder` vs `.invalidated`); Flutter had no
vocabulary for it.

Because the type is `sealed`, `switch` over it is exhaustive and the analyzer
tells you when a state is unhandled.

### It knows what time it is

Skeletons only improve perceived performance inside a band — roughly 400 ms to
3 s ([NN/g](https://www.nngroup.com/articles/skeleton-screens/)). Below it the
skeleton is a flash that feels worse than nothing. Above it, it stops
reassuring. Every other package starts at 0 ms and loops forever.

```dart
SeamScope(
  schedule: const SeamSchedule.nng(),   // the default
  child: MyApp(),
)
```

| Phase | Window | Behaviour |
|---|---|---|
| `held` | 0 – 400 ms | Space reserved, nothing painted. Fast loads never flash. |
| `lit` | 400 ms – 3 s | The effect runs. |
| `escalated` | 3 s + | Light slows; surface something more informative. |
| `settled` | — | Content is current. The ticker stops. |

Use `SeamSchedule.always()` to opt out and behave like every other package.

### One light, one ticker, no `saveLayer`

The convention is a gradient swept by a `ShaderMask` per widget. That costs a
`saveLayer` each — one of the most expensive raster operations — and because
each widget animates on its own `AnimationController`, the sweeps drift out of
phase. Twenty-five rows means twenty-five offscreen buffers and twenty-five
independent light sources over one screen.

Seam holds one phase per scope. Each bone asks how bright it should be given
where it sits on screen, and fills itself with a solid colour. No mask, no
offscreen buffer, nothing that *can* drift. Bones repaint; they never rebuild.

The ticker only runs while something is actually lit.

---

## Install

```yaml
dependencies:
  seam: ^0.1.0
```

## Usage

A scope is optional. A slot with no scope above it falls back to its own
controller, so adoption never starts with a root-level edit:

```dart
SeamSlot<String>(
  id: 'greeting',
  value: const SeamValue.absent(),
  builder: (context, value) => Text(value),
)
```

Add a scope to share one light and one ticker across the screen, and to give
measurement somewhere to live:

```dart
SeamScope(
  memory: SeamMemory.inMemory(),
  light: const SeamLight.ambient(),      // or .sweep() for the familiar look
  schedule: const SeamSchedule.nng(),
  child: MyApp(),
)
```

### Colouring bones

A bone is a single solid fill interpolated from `base` to `highlight` by how
brightly the light falls on it — there's no gradient and no mask — so those two
colours fully describe the effect.

Theme every bone at once from the scope:

```dart
SeamScope(
  palette: SeamPalette.from(const Color(0xFFB0741C)),  // derives the highlight
  child: MyApp(),
)
```

Or set both ends explicitly:

```dart
const SeamPalette(
  base: Color(0xFF2D333B),
  highlight: Color(0xFF3F4752),
)
```

Override for one slot:

```dart
SeamSlot<String>(
  id: 'avatar',
  value: vm.avatar,
  baseColor: Colors.teal.shade100,
  highlightColor: Colors.teal.shade50,
  builder: ...,
)
```

Resolution order is **slot → scope → platform brightness**. With nothing set,
bones follow `SeamPalette.light()` / `SeamPalette.dark()` automatically. A slot
may override just one end and inherit the other.

To follow your app's theme, build the palette from it:

```dart
SeamScope(
  palette: SeamPalette.from(
    Theme.of(context).colorScheme.surfaceContainerHighest,
    lift: 0.18,
  ),
  child: ...,
)
```

### Persisting measurements

The core package has no storage dependency. Implement `SeamStore` over whatever
you already use:

```dart
class PrefsStore implements SeamStore {
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString('seam');

  @override
  Future<void> write(String data) async =>
      (await SharedPreferences.getInstance()).setString('seam', data);
}

final memory = SeamMemory.persistent(store: PrefsStore());
await memory.load();   // once, during startup
```

With persistence, the *first* load of a session is already accurate.

### Choosing slot ids

Ids must be stable across builds and unique per distinct shape. In a list,
prefer one id per **kind** of row (`'feed.row.title'`), not one per item — the
point is to learn the shape rows share.

---

## Known limitations

**Performance claims here are architectural, not measured.** Bones cost no
`saveLayer` and share one ticker by construction, but the package has not been
profiled against `shimmer` on a real device.

## Status

`0.1.0`. The value model, measurement, schedule and single-ticker renderer are
implemented and tested. Not yet built:

- the single-draw-call renderer (bones currently paint individually — still zero
  `saveLayer`, but not yet one batched pass);
- the staggered dissolve on arrival;
- a `skeletonizer` adapter.

## License

MIT
