---
paths:
  - "Tests/**"
  - "Benchmarks/**"
---

# Tests

- swift-testing only (`import Testing`, `@Test`, `#expect`, `#require`). XCTest isn't available with the Command Line Tools.
- Group related tests in a `@Suite` struct. Name tests after behaviour: `@Test func reCopyingMovesItemToTop()`.
- Parameterise with `@Test(arguments:)` instead of copy-pasted cases.
- Pasteboard tests use a private pasteboard: `NSPasteboard.withUniqueName()`, released in `deinit` or a `defer` with `releaseGlobally()`. Never touch `NSPasteboard.general` in tests.
- Database tests use an in-memory or temporary `DatabaseQueue` created per test. No shared state between tests.
- Inject time (`Clock`, `Date` providers) instead of sleeping. A test that sleeps is a bug.
- Nothing that needs a TCC grant (Accessibility, PostEvent, screen recording) runs in the test suite; hide it behind a protocol and test the logic with a fake.
- Performance assertions in unit tests are coarse guards only (10x headroom). Real measurements live in `Benchmarks/`.
- Fixtures: small, synthetic, checked into `Tests/<Target>/Fixtures/`. Never real clipboard data.
