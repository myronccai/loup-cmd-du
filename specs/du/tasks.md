# Tasks: du

- [x] 1. Options: bundling, long-option prefixes, values, conflicts
  - _Requirements: 6.2, 6.3, 6.4_
- [x] 2. SIZE parsing, block sizes from options and environment, size formatting
  - _Requirements: 3.1, 3.2, 3.3, 3.4_
- [x] 3. `lstat`/`fstatat` through `@repr(C) struct StatBuf`; errno; `unique class DirHandle`
  - _Requirements: 1.1, 6.1_
- [x] 4. Glob matching and `ExcludeList` under an `RwLock`
  - _Requirements: 4.1_
- [x] 5. Walk keys and the `synchronized class Ledger`
  - _Requirements: 1.3, 1.4, 1.5_
- [x] 6. Parallel walker: top level, job queue, workers, harvest
  - _Requirements: 4.2, 4.3, 5.1, 5.2_
- [x] 7. Tree with `unowned` parents; post-order report, depth, -a, -s, -S, -t, -c, -0
  - _Requirements: 1.2, 2.1-2.7_
- [x] 8. `run_du`: operands, errors, exit status
  - _Requirements: 4.4, 6.1_
- [x] 9. Native unit tests and end-to-end tests
  - _Requirements: all_
