# Task Assignment: R2. Finance, Shift Logic & Calculation Edge Cases Review

## Project Directory: F:\Projects\aperture-grafik
## Requirements Source: F:\Projects\aperture-grafik\ORIGINAL_REQUEST.md
## Working Directory: F:\Projects\aperture-grafik\.agents\explorer_r2_finance

### Objectives
Audit finance and shift calculation logic across the codebase:
1. Audit shift calculations: hourly rates, fixed shifts, duration calculations.
2. Overnight time math: shifts crossing midnight (e.g., 22:00 -> 06:00), multi-day spans, DST transitions, negative duration guards.
3. Coefficient & rate overrides: custom shift coefficients (e.g. 1.5x, 2.0x, weekend rates), custom hourly overrides.
4. Manual earnings precedence: verify when and how manual earnings override calculated earnings, and vice versa.
5. Advance & salary cycle countdowns: pay periods (semi-monthly, monthly, bi-weekly), cutoff dates, advance deductions, remainder payouts.
6. Rounding & timezone edge cases: double vs integer cents/kopecks, floating-point precision loss, UTC vs local DateTime handling, leap years, month boundaries.
7. Identify concrete code locations, file paths, line numbers, and provide code snippets for both problems and recommended fixes.
8. Rate each finding by priority: P0 Critical, P1 High, P2 Medium, P3 Polish.

Deliver your comprehensive findings report in F:\Projects\aperture-grafik\.agents\explorer_r2_finance\report.md and send a completion message with summary.
