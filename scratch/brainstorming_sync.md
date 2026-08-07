# Brainstorming: Sync and the `isSynced` flag

## How Sync Works
The application uses an "offline-first" architecture powered by a local SQLite database (`LocalDatabaseHelper`). 
Users can perform actions (like scanning items, creating cut/bulk orders, rolling over stock) without a network connection. 
When these actions occur, the data is saved locally first.

## The `isSynced` Flag
To track which local changes need to be pushed to the backend server, almost every transactional table in the SQLite database includes an `isSynced` column.

- `isSynced = 1`: The record exists on the backend and the local app is perfectly in sync.
- `isSynced = 0`: The record is newly created or modified locally and **has not yet been sent** to the backend.

### Key Tables Using `isSynced`:
- `tbl_scans`: Tracks scanned inventory items.
- `tbl_sales_orders` & `tbl_sales_order_details`: Tracks orders (including offline-created internal cuts/bulks).
- `tbl_global_settings`: For any local configuration changes.
- `tbl_rollovers`: Tracks end-of-day stock rollovers.

### The Sync Process
When a sync is triggered (either manually via the Sync button or via `SyncBloc` events):
1. The `DeliveryRepository` queries all tables for records where `isSynced == 0`.
2. These records are bundled and pushed to the backend API (`SynchronizeLogisticsUseCase`).
3. Upon a successful API response, the local database is updated, setting `isSynced = 1` for those records.
4. The `SyncBloc` emits a `SyncSuccess` state.

## Challenge: Detecting Unsynced Data in UI
Because SQLite does not natively emit streams when data changes, the UI doesn't automatically "know" when an offline action sets `isSynced = 0`. To build a future-proof widget indicating unsynced data, we must implement a lightweight observation pattern without relying on manual state-flagging across thousands of lines of repository code.
