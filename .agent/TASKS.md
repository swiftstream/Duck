# Active Tasks

Only approved executable work belongs here. Current implementation facts are in [Project Memory](PROJECT_MEMORY.md); completed milestones are in [Task Archive](TASKS_ARCHIVE.md). Future priorities belong in [TODO](TODO.md).

## Current state

The Duck 1.1.0 engineering scope is complete and independently accepted. Canonical bounded pooling, refresh-scoped Observation, physical native retirement and final deterministic compatibility are closed. Source and retirement regressions are committed at `e2304c4007b5b0896f4c94b7f4bc6426299185b7` and `53e360d13441617482f7fb6a708adc5d28c40aa4`. The final full suites passed 859/31 on Swift 6.3.3 and 870/31 on Swift 6.4; independent final audit CLEAN. No new implementation task is authorized.

The exact release snapshot `226c2fd5e31f7ab1b2c13cd982375839e30f4cb0` is independently accepted, including both Xcode example dependency floors, fresh first-time-user Xcode integration, and focused README correction. The maintainer removed temporary example edits, pushed master (branch CI passed), and published the annotated tag `1.1.0` on that commit. Its original tag filter excluded unprefixed versions. Preserve the tag and correct the moving branch's release naming policy and CI; require exact tagged-commit CI via the recovery route in [Release Publication](RELEASE_PUBLICATION.md), followed by remote consumers and separate GitHub Release authorization. No new Product work or broad local test rerun is authorized.

Observation precision and comprehensive large-workload validation are reserved for 1.2, not active implementation. Post-release artifact/cache inventory is a separate future task. No automatic cleanup, timing runs, new platform work, or publication is authorized by this state.
