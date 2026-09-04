## 0.1.0

First release.

- `SeamValue<T>` — a sealed four-state loading model (`absent`, `stale`,
  `partial`, `fresh`) replacing the usual boolean.
- `SeamMemory` — records the geometry real content occupied and reserves it on
  the next load, so the arrival causes no reflow. Filed against the constraints
  it was measured under; declines to predict slots whose height varies too much.
  In-memory by default, optionally persistent behind an injectable `SeamStore`.
- `SeamSchedule` — suppresses the effect below 400 ms and escalates past 3 s,
  per Nielsen Norman Group's finding on when skeletons help.
- `SeamScope` / `SeamController` — one ticker and one light per screen. The
  ticker stops when nothing is lit.
- `SeamPalette` — bone colours, set once on the scope or overridden per slot.
  Resolution is slot, then scope, then platform brightness.
- `SeamSlot` / `SeamBone` — per-field resolution; bones repaint rather than
  rebuild and cost no `saveLayer`.
