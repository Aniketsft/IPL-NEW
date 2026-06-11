# Offline-First App Development Workflow

> [!TIP]
> **Core Rule**: UI *never* talks to Network. UI talks to Local DB. Background Worker talks to Network and updates Local DB.

## Phase 1: Data Modeling & Schema
1. **Entity Definition**: Define standard Dart models with manual `fromJson` and `toSqlMap` factories. **Do NOT use `@freezed`** as the package is not installed globally across the project. Match existing DTOs like `ProductMasterDto`.
2. **Local Schema**: Add table to `LocalDatabaseHelper`. 
   - *Best Practice*: Stop manual versioning! Use automated schema migration tools (like `sqflite_migration` or Floor).
   - Ensure all tables have `isSynced`, `createdAt`, `updatedAt`, and `deviceId` columns.

## Phase 2: The Sync Engine
1. **Pull (Read)**: 
   - Fetch all required records from backend.
   - Replace or Upsert into SQLite.
2. **Push (Write/Outbox Pattern)**:
   - When user takes action -> Write to SQLite (`isSynced = 0`).
   - Background isolate checks for `isSynced == 0` -> Pushes to Backend.
   - On success -> Update SQLite (`isSynced = 1`).
   - *NEVER* block the UI for a network call.

## Phase 3: Data Access (Repository)
1. **Local Only**: Repositories only return data from SQLite.
2. **Reactive DB**: Use Streams (or Stream-based queries) from SQLite. When background sync updates the DB, the Stream automatically emits new data to the UI.
3. **Strict Global Sync**: Individual UI screens must **NEVER** unless i say so trigger API calls (like `_syncProducts()`) on initialization (`initState` / `didChangeDependencies`). The ONLY way data should be brought into the application is through the global **Sync Button** (orchestrated via `DeliveryRepository.synchronize()`).

## Phase 4: State Management & UI
1. **No `setState`**: Stop using `setState` for complex logic. Use BLoC or Riverpod.
2. **State Flow**:
   - BLoC listens to Repository Stream.
   - UI listens to BLoC State.
3. **Theming**: Use standardized Theme tokens (e.g., `Theme.of(context).colorScheme`). Do not hardcode colors like `orange` or manual `isDark` checks.

## Phase 5: Workflow Orchestration & @task-intelligence
1. **Generate Boilerplate**: 
   - Use `build_runner` heavily. 
   - Write scripts to auto-generate BLoC, Repository, and SQL queries for a new feature.
2. **Token Budgeting**: Keep agent prompts focused on one phase at a time (e.g., "Only write the SQLite schema for Customer", then "Only write the BLoC").

## Important: Global vs Context-Specific Data (e.g., Products vs Stock)
> [!WARNING]
> Always verify if existing master data tables (like `tbl_products` populated by `delivery_repository.dart`) contain context-specific fields you need.
> Example: `tbl_products` stores global master product details, but a SQL query might require site-specific stock levels (`QTYSTU_0` where `STOFCY_0 = @SiteCode`). 
> If you need site-specific data, you must either extend the master sync to include it (e.g., a `tbl_product_stock` table) or isolate the context (e.g., `tbl_si_products`). Do not assume the global master has everything!

**Architecture Decision (Sales Invoice)**: 
Isolate Sales Invoice Context: All SQLite tables for Sales Invoice will be separated to avoid conflicts with global tables (like `tbl_products` used by Delivery). Use `tbl_si_...` prefixes.

**Reference Implementation (Sales Invoice Product Selection)**:
- **Backend API**: Used Dapper to execute exact custom SQL queries (`LEFT JOIN` on `ITMMASTER` and `ZSTKBYLOC`) returning `SalesInvoiceProductDto`.
- **Frontend Sync**: Handled via `SalesInvoiceProductRepository.syncSalesInvoiceProducts` which completely clears and replaces `tbl_si_products` based on the fetched `sitecode`.
- **UI Stream**: Data is bound to the UI using a continuous SQLite stream (`Stream.periodic` fetching from `db.query`) with dynamically fetched dropdown filters for Warehouse.

## Checklist for New Features
- [ ] Model created with code-gen?
- [ ] SQLite table added with sync flags?
- [ ] Outbox queue handles offline actions?
- [ ] Sync logic handles conflict resolution (Server-wins or Client-wins)?
- [ ] BLoC written?
- [ ] UI built with proper Theme tokens?
