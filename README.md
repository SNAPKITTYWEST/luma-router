<!--
  SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (c) 2026 SnapKittyWest
  Ahmad Ali Parr / Bel Esprit D'Accord Irrevocable Trust
  CLONE GATE: Any clone, fork, or derivative of this node
  MUST be released under GPL-3.0-or-later. No closed-source use.
-->

# Luma Router

Deterministic multi-modal creative AI routing system with formal specification in Lean 4 and executable implementation in MATLAB.

## Architecture

```
Input Task
    ↓
TaskType Classification
    ↓
Multi-Objective Scoring: min(w·cost + w·latency + w·quality_deficit + w·audio_penalty)
    ↓
Provider Selection (Veo | Seedream | Kling | ElevenLabs)
    ↓
Context Ledger Commit (snapshot versioning, conflict detection)
    ↓
Parallel Execution (video + audio branches with frozen context)
    ↓
Lip-Sync Verification (canonical timing manifest)
    ↓
Audit Trail
```

## Model Registry

| Model | Type | Cost | Quality | Audio |
|-------|------|------|---------|-------|
| Google Veo 3 | Video | $0.40/sec (std), $0.15/sec (fast) | 0.92 | ✅ |
| ByteDance Seedream 4.5 | Image | $0.04/image | 0.88 | ❌ |
| Kling 3.0 | Video | ~$0.50/sec (credit) | 0.85 | ✅ |
| ElevenLabs | Aggregator | $0.35+/sec | 0.90 | ✅ native |

## Formal Specification (Lean 4)

```
lean/
  Routing.lean          — Core types, 7 invariants, routing algorithm, fallback
  RoutingExtended.lean  — CreativeTask, ModelProfile, cost functions,
                          multi-objective dispatch, model registry
```

**Key invariants:**
1. `hasCompleteCoverage` — every task type has at least one route
2. `hasNoConflictingRoutes` — one task → one model deterministically
3. `allModelsExist` — all referenced models exist in the pool
4. `prioritiesValid` — all priorities ≥ 0
5. `hasTraceability` — routed request can be traced back
6. `loadBalanced` — no model overloaded beyond threshold
7. `deterministicRouting` — same input → same output

**Objective function:**
```
M* = argmin_M ( w_cost·C(M,T) + w_latency·L(M,T) + w_quality·Q_deficit + w_audio·P(M,a) )
```

## MATLAB Implementation

```
matlab/
  LumaRouter.m          — Main router class (nested ContextLedger, AssetGraph)
  LipSyncCoordinator.m  — Timing manifest generation + lip-sync verification
  demo.m                — Complete end-to-end pipeline demo
  routing_tests.m       — 15-test test suite
```

## Running

### MATLAB
```matlab
% Run tests
routing_tests

% Run demo
demo

% Standalone test
LumaRouter.runTests()
```

### Lean 4
```bash
lake build
```

## Key Design Properties

| Property | Meaning | Enforced By |
|----------|---------|-------------|
| Completeness | Every task type has a route | `hasCompleteCoverage` + fallback |
| Non-conflict | One task → one model | `hasNoConflictingRoutes` |
| Determinism | Same input → same output | Pure function + policy |
| Load balance | No model overload | `loadBalanced` threshold |
| Fallback | Never drop requests | `routeWithFallback` |
| Provenance | Full audit trail | `ContextLedger` snapshots |
| Lip-sync | Audio-video alignment | `LipSyncCoordinator` + `verifyLipSync` |

## License

GPL-3.0-or-later. CLONE GATE: any fork must open-source under GPL-3.0+.
Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr / Bel Esprit D'Accord Irrevocable Trust.
