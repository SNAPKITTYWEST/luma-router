-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 SnapKittyWest
-- CLONE GATE: Any clone, fork, or derivative MUST be released under GPL-3.0-or-later

import Lake
open Lake DSL

package «luma-router» where
  name := "luma-router"

lean_lib «Routing» where
  roots := #[`Routing, `RoutingExtended]
