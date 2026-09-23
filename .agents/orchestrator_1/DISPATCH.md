## 2026-09-23T13:42:53Z

Execute a comprehensive full-scope code and architecture review of the Aperture Grafik offline-first Android Flutter application:
1. R1. Architecture & Layering Integrity: Audit cross-layer boundaries (presentation -> application -> domain <- data), ensure strict separation of concerns, no leaky database or UI abstractions, and clean Riverpod state lifecycle management without memory leaks.
2. R2. Finance, Shift Logic & Calculation Edge Cases: Audit shift calculations, overnight time math, coefficient & rate overrides, manual earnings precedence, advance/salary cycle countdowns, and potential edge-case rounding or timezone issues.
3. R3. UI/UX, Anti-Overlap & Material 3 Compliance: Inspect screens, bottom sheets, and dialogs for text wrapping, overflow immunity on compact viewports and high DPI scaling, and adherence to coffee-shop Material 3 styling.
4. R4. Data Persistence, Backup & Privacy: Verify SQLite database transactions, schema migration safety, UTF-8 clean JSON backup import/export schema validation, and on-device privacy guarantees.

Acceptance Criteria:
- Run and verify automated test suite (`flutter test`) in F:\Projects\aperture-grafik with 100% pass rate.
- Run static analyzer (`flutter analyze`) in F:\Projects\aperture-grafik reporting 0 issues.
- Produce a detailed actionable review report (saved to F:\Projects\aperture-grafik\REVIEW_REPORT.md and referenced in your handoff) with concrete code snippets, categorized findings, and priority rankings (P0 Critical, P1 High, P2 Medium, P3 Polish).
