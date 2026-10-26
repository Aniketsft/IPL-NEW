# Patterns: Offline Sync, Deadlock Prevention & Catch-Weight Precision

## 1. Sqflite Transaction Deadlock Prevention
- **Issue**: Calling `LocalDatabaseHelper.instance.getDefaultBank()` (which queries `database` directly) while inside an open write transaction `await db.transaction((txn) async { ... })` locks SQLite and hangs the app (`Warning database has been locked for 0:00:10.000000`).
- **Rule**: ALWAYS execute helper queries that access the main `Database` handle *before* opening `db.transaction(...)`, or query exclusively through the `txn` handle.

## 2. Catch-Weight & Decimal Quantity Precision
- **Issue**: Weighted products (Unit: `KG`) stored with 3 decimal places (e.g. `0.858` KG) rounded to `"0.86"` when formatted with `toStringAsFixed(2)`. Then `enteredQty (0.86) > remaining (0.858)` triggered false exceeding errors and blocked returns.
- **Rule**:
  1. Use dynamic 3-decimal formatting `_formatQty` stripping trailing zeros.
  2. Apply `_resolveEffectiveQty(entered, remaining)` with a `0.005` epsilon tolerance: if `(entered - remaining).abs() <= 0.005`, clamp `entered = remaining` so returning 100% of the line always succeeds.

## 3. Safe SQLite Migrations
- **Rule**: Never run raw `ALTER TABLE table ADD COLUMN ...` in initialization or upgrade blocks without checking `PRAGMA table_info(table)`. Use `LocalDatabaseHelper._safeAddColumn` to avoid duplicate column crashes and Android logcat noise.
