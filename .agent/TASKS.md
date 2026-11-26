# Active Tasks

Only approved executable work belongs here. Current implementation facts are in [Project Memory](PROJECT_MEMORY.md); completed milestones are in [Task Archive](TASKS_ARCHIVE.md). Future priorities belong in [TODO](TODO.md).

## Current state

The Duck 1.1.0 engineering scope is complete and independently accepted. Canonical bounded pooling, refresh-scoped Observation, physical native retirement and final deterministic compatibility are closed. Source and retirement regressions are committed at `e2304c4007b5b0896f4c94b7f4bc6426299185b7` and `53e360d13441617482f7fb6a708adc5d28c40aa4`. The final full suites passed 859/31 on Swift 6.3.3 and 870/31 on Swift 6.4; independent final audit CLEAN. No new implementation task is authorized.

The maintainer approved local closure and the 1.1.0 public documentation snapshot, but not push, semantic tag or remote release. Both Xcode example dependency floors and their README are synchronized at `82524824c380cf6479c508044548469e3f9ad129`; unrelated SwiftUI signing/bundle edits remain unstaged. Fresh first-time-user Xcode integration execution is complete against that commit. Independent U0 evidence adjudication and exact release-snapshot rebind remain required before branch publication under [Release Publication](RELEASE_PUBLICATION.md). Do not reopen the accepted Product or repeat its test matrix solely for prose changes.

Observation precision and comprehensive large-workload validation are reserved for v1.2, not active implementation. Post-release artifact/cache inventory is a separate future task. No automatic cleanup, timing runs, new platform work, or publication is authorized by this state.
