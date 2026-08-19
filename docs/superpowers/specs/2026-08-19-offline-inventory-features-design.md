# StockLens Offline Inventory Features Design

**Date:** 2026-08-19

**Status:** Approved in chat; awaiting written-spec review

**Target release:** v0.3.0

## Summary

StockLens will add five offline inventory capabilities:

1. Persistent stocktake sessions for full, category, and individually selected product counts.
2. Per-product low-stock thresholds with an in-app alert center and Android notifications.
3. Offline inventory, movement, sales, and profitability reports.
4. Previewed, validated, atomic CSV product imports.
5. Separate cost and selling prices with historical price snapshots on stock transactions.

The work extends the existing SQLite, repository, and service architecture. It does not add accounts, synchronization, a backend, or an internet requirement.

## Goals

- Let users perform reliable physical inventory counts that survive app restarts.
- Make low-stock rules appropriate to each product and surface them inside and outside the app.
- Derive useful business reports entirely from local data.
- Make bulk product migration and maintenance safe and auditable.
- Track cost separately from selling price and preserve the values needed for historical revenue and gross-profit estimates.
- Preserve existing products, images, archives, and transaction history through the database migration.

## Non-goals

- Cloud synchronization or multi-device collaboration.
- User accounts, roles, or per-user transaction attribution.
- Purchase orders, suppliers, batches, expiry dates, or multiple storage locations.
- Editing or deleting historical stock transactions.
- Reconstructing monetary values for transactions created before price snapshots exist.
- Scheduling recurring background inventory scans. Android notifications are triggered by inventory changes made in StockLens.

## Architecture

The existing `AppDatabase` remains the shared SQLite entry point. New feature areas use focused contracts, repositories, and services instead of expanding `LocalProductRepository` into a single inventory subsystem.

### Responsibilities

- `ProductService` continues to manage products, images, archive state, and manual stock adjustments. It also accepts cost price and low-stock threshold values.
- `StocktakeService` creates sessions, records counts, resumes incomplete sessions, validates completion, and reconciles inventory.
- `InventoryReportService` requests aggregate report data for a selected local date range.
- `InventoryImportService` selects, parses, validates, previews, and atomically applies CSV files.
- `LowStockNotificationService` evaluates threshold crossings and delegates Android notification delivery through an adapter that can be replaced in tests.
- Focused SQLite repositories implement stocktake, reporting, and import persistence while sharing `AppDatabase`.
- Screens call services only; UI code does not execute SQL or platform-notification operations.

Notification delivery is a side effect after a successful inventory commit. A platform notification failure does not invalidate inventory data. The in-app alert center is computed from SQLite and remains authoritative.

## Database Schema v3

The database version advances from 2 to 3. Both v1-to-v3 and v2-to-v3 migrations are supported.

### Products

The existing `price` column and existing values represent selling price. The code and UI expose it as `sellingPrice`, while backup restore continues accepting the legacy `price` key.

Add these columns:

- `cost_price REAL NOT NULL DEFAULT 0 CHECK(cost_price >= 0)`
- `low_stock_threshold INTEGER NOT NULL DEFAULT 5 CHECK(low_stock_threshold >= 0)`
- `low_stock_notified INTEGER NOT NULL DEFAULT 0 CHECK(low_stock_notified IN (0, 1))`

`low_stock_notified` prevents duplicate Android notifications. It is set when a crossing notification is successfully attempted and reset once quantity rises above the threshold. The alert center does not depend on this flag.

### Stock transactions

Add these nullable columns:

- `selling_price_snapshot REAL`
- `cost_price_snapshot REAL`
- `source TEXT`
- `source_id TEXT`

New transactions snapshot the product's current prices. Old rows keep `NULL` snapshots and remain valid. `source` identifies values such as `manual`, `csv_import`, and `stocktake`; `source_id` groups an import application or links a reconciliation to a stocktake session.

### Stocktake sessions

Create `stocktake_sessions` with:

- `id TEXT PRIMARY KEY`
- `name TEXT NOT NULL`
- `status TEXT NOT NULL` with supported values `in_progress` and `completed`
- `scope_description TEXT NOT NULL`
- `notes TEXT NOT NULL DEFAULT ''`
- `created_at TEXT NOT NULL`
- `completed_at TEXT`

### Stocktake items

Create `stocktake_items` with:

- `session_id TEXT NOT NULL`
- `product_id TEXT NOT NULL`
- `expected_quantity INTEGER NOT NULL CHECK(expected_quantity >= 0)`
- `counted_quantity INTEGER CHECK(counted_quantity >= 0)`
- `updated_at TEXT NOT NULL`
- Composite primary key `(session_id, product_id)`
- Cascading foreign keys to the session and product

The item snapshot preserves the quantity expected when the session began. The current product quantity is read again during completion to identify concurrent changes and calculate the final reconciliation delta.

### Indexes

Add indexes for:

- Active products ordered or filtered by low-stock state.
- Stock transactions by date and reason for reports.
- Stocktake sessions by status and creation date.
- Stocktake items by product ID.

## Product Pricing and Thresholds

The product model exposes `sellingPrice`, `costPrice`, and `lowStockThreshold`.

- Existing prices migrate unchanged as selling prices.
- Existing products receive cost price `0` and threshold `5`.
- Add/Edit Product shows Selling Price, Cost Price, and Low-stock Threshold.
- All three values must be non-negative; monetary inputs retain two-decimal validation.
- Product cards continue showing selling price only.
- Product Details shows selling price, cost price, unit margin, current cost value, and potential retail value.
- Unit margin is `selling price - cost price`; negative margins are allowed because both component prices remain valid non-negative amounts.

Every new stock transaction snapshots both prices. Sale reports use snapshots rather than the product's current prices, so later edits do not rewrite history. Transactions with missing snapshots contribute units but not known revenue, cost, or profit; reports disclose the count of such legacy transactions.

## Stocktake Workflow

### Starting a session

From Inventory, the user opens Stocktake and chooses one of these scopes:

- All active products.
- One or more categories.
- Individually selected active products.

At least one product is required. Creating a session inserts the session and all selected item snapshots in one transaction. The generated scope description makes completed sessions understandable without reconstructing the original selection UI.

### Counting

- The session screen shows counted, remaining, and variance summaries.
- Scanning a selected product's barcode increments its count by one.
- A user can directly enter or replace a counted quantity.
- Scanning a product outside the session explains that it is not part of the selected scope and does not silently add it.
- Every count is persisted immediately, so an in-progress session can resume after navigation, process death, or app restart.
- Multiple in-progress sessions are permitted because users may count different scopes independently.

### Completion

Completion is blocked while any item has no counted quantity. A deliberate, separately confirmed action can set every remaining item to zero.

Before applying changes, StockLens reloads current product quantities. If a quantity differs from the original expected snapshot, the review flags it as changed during the count. The displayed reconciliation compares counted quantity with the latest current quantity while retaining the original expected quantity for audit.

After final confirmation, one SQLite transaction:

1. Re-reads and validates every product.
2. Calculates `counted - current` for each item.
3. Updates products with non-zero differences.
4. Creates `Inventory Correction` stock transactions with source `stocktake` and the session ID.
5. Marks the session completed.

Zero-difference items create no stock transaction. Any failure rolls back the entire completion. Completed sessions are read-only.

## Low-stock Alerts

A product is low stock when it is active and `quantity <= lowStockThreshold`. Quantity zero is included. A threshold of zero therefore alerts only when the product is out of stock.

### In-app experience

- The dashboard shows low-stock and out-of-stock totals using product-specific thresholds.
- An alert-center screen lists qualifying products, prioritizing out-of-stock and then the largest threshold deficit.
- Selecting an alert opens Product Details.
- The alert center always reflects current SQLite data and requires no Android notification permission.

### Android notifications

- StockLens requests notification permission in context on Android versions that require it.
- A notification is triggered when a successful product mutation moves quantity from above its threshold to at-or-below it.
- Lowering quantity, raising a threshold, CSV reconciliation, and stocktake reconciliation can all cause a crossing.
- A product does not notify repeatedly while it remains low.
- Raising quantity above the threshold resets its notification state.
- Tapping a notification opens the relevant product when possible, falling back to the alert center if the product is unavailable.
- Permission denial or platform delivery failure never rolls back product data and does not prevent in-app alerts.

No recurring background task or network service is introduced.

## Offline Reports

Reports support Today, last 7 days, last 30 days, custom local date range, and all-time filters. Inclusive date boundaries are converted consistently before repository queries.

### Current inventory metrics

These use active products only and are not affected by the historical date filter:

- Total units on hand.
- Current inventory cost value: sum of `quantity * costPrice`.
- Potential retail value: sum of `quantity * sellingPrice`.
- Potential gross margin: retail value minus cost value.
- Low-stock and out-of-stock counts.
- Category-level quantity, cost value, and retail value.

### Historical movement metrics

These use transactions in the selected range, including products later archived:

- Units sold from transactions whose reason is `Sale` and delta is negative.
- Recorded revenue using absolute sold quantity times selling-price snapshot.
- Recorded cost of goods using absolute sold quantity times cost-price snapshot.
- Estimated gross profit as recorded revenue minus recorded cost.
- Damaged and expired units from their matching removal reasons.
- Net stock movement.
- Fast-moving products ranked by units sold.
- Inactive products with stock on hand and no transactions in the selected range.
- Count of legacy sale units without complete price snapshots.

Permanently deleted products and their cascaded history cannot appear in reports, matching current deletion semantics.

## CSV Import

### Input format

CSV matching is case-insensitive for headers and accepts these canonical columns:

- `barcode` (required for every row)
- `name` (required for new products)
- `selling_price`
- `cost_price`
- `category`
- `quantity`
- `low_stock_threshold`
- `description`

Legacy `price` is accepted as an alias for `selling_price`. UTF-8 CSV with standard quoted fields is supported through a dedicated CSV parser rather than manual string splitting.

### Semantics

- Barcode is the upsert key.
- A new barcode creates a product. Missing optional text fields use current product-creation defaults; blank quantity becomes zero; blank prices become zero; blank threshold becomes five.
- A matching barcode updates only fields whose CSV cells are explicitly populated.
- Blank quantity preserves stock for an existing product.
- An explicit quantity, including zero, reconciles existing stock to that value.
- Every non-zero stock difference creates an `Inventory Correction` transaction with source `csv_import` and a shared import ID.
- Imports do not restore or silently modify archived products. A barcode belonging to an archived product is reported as a blocking conflict.
- Images are not imported through CSV.

### Preview and apply

After file selection, StockLens displays counts and row details for:

- New products.
- Product-detail updates.
- Stock changes.
- Unchanged rows.
- Blocking errors.

Blocking errors include missing required values, invalid or negative numbers, duplicate barcodes within the file, unsupported headers when required data cannot be resolved, and archived-product conflicts. The user cannot apply until the file has no blocking errors.

Immediately before apply, the service re-reads affected barcodes and verifies that the preview assumptions still match. A mismatch aborts and asks the user to generate a fresh preview. A single database transaction then applies every product and stock-transaction change. Partial imports are never committed.

## Data Flow

### Manual inventory mutation

1. UI validates user input and calls `ProductService`.
2. Repository commits the product and transaction change.
3. Service evaluates the before-and-after low-stock state.
4. Alert state is persisted and Android delivery is attempted when a crossing occurred.
5. Screens refresh from SQLite.

### Stocktake completion

1. UI requests a reconciliation preview from `StocktakeService`.
2. Service compares original snapshots, current quantities, and counted quantities.
3. User confirms the displayed differences and concurrent-change warnings.
4. Repository atomically updates products, adds linked transactions, and completes the session.
5. Notification evaluation runs for affected products after commit.

### CSV import

1. UI selects a file and calls `InventoryImportService`.
2. Parser maps headers and produces typed candidate rows.
3. Service combines candidates with current products to create a preview.
4. User confirms a preview without blocking errors.
5. Service revalidates and repository applies all changes atomically.
6. Notification evaluation runs for affected products after commit.

### Reports

1. UI supplies a report range to `InventoryReportService`.
2. Repository executes focused aggregate queries.
3. Service combines results into immutable report models.
4. UI formats Philippine Peso and local dates without recalculating business totals.

## Navigation and Screens

- Inventory app-bar actions expose Stocktake, Reports, Data & Backups, and Archived Products without adding another bottom-navigation destination.
- Stocktake has session list, scope selection, active counting, and completion review screens.
- Reports uses summary cards and compact ranked/category lists with a date-range selector.
- Data & Backups adds Import Inventory CSV beside existing backup and export actions.
- The dashboard low-stock card opens the alert center.
- Product form and details screens incorporate pricing and threshold fields while keeping primary scan and adjust-stock paths unchanged.

## Error Handling

- Domain validation errors have specific user-facing messages instead of generic failure notices.
- Unique-barcode conflicts remain typed exceptions.
- Stocktake completion and CSV apply translate transactional conflicts into a refresh-and-review flow.
- CSV parsing reports row numbers and field-level causes without exposing stack traces.
- Notification permission denial is remembered by Android; StockLens continues showing in-app alerts and offers a route to system settings when appropriate.
- Report query failures show retryable error states and do not mutate data.
- Database migration failure follows SQLite's atomic upgrade behavior and does not intentionally delete or recreate the database.

## Backup and Export Compatibility

- The complete JSON backup format increments its format version and includes all product fields, new transaction fields, stocktake sessions, and stocktake items.
- Restoring older backups supplies cost `0`, threshold `5`, cleared notification state, and null transaction snapshots/source fields.
- Restoring a new backup restores inventory and stocktake audit data transactionally.
- Notification state is cleared after restore and recomputed from inventory to avoid delivering stale alerts.
- Inventory CSV export adds `selling_price`, `cost_price`, and `low_stock_threshold`, while continuing to include active and archived product status.

## Testing Strategy

### Models and validation

- Product and transaction JSON round trips for all new fields.
- Non-negative cost, price, quantity, and threshold validation.
- Legacy backup and CSV aliases.

### Database and repositories

- Clean v3 schema creation.
- v1-to-v3 and v2-to-v3 migrations without product or history loss.
- Stocktake creation, resume, count persistence, completion, concurrent-change handling, and full rollback on failure.
- Price snapshots and source linkage on manual, CSV, and stocktake transactions.
- Report aggregates, local date boundaries, archived history, legacy missing-price totals, and category rankings.
- Atomic CSV upserts and rollback.

### Services

- Threshold crossing, duplicate suppression, reset, threshold-edit crossing, denied permission, and delivery failure through a fake notification adapter.
- CSV quoted values, blank versus explicit zero, duplicate rows, preview classification, stale-preview rejection, and archived conflicts.
- Sale snapshots remaining unchanged after product price edits.
- Backup and restore compatibility for old and new formats.

### Widgets

- Updated product form validation.
- Alert-center loading, ordering, empty, and navigation states.
- Stocktake scope, counting, remaining-item protection, resume, and completion review states.
- Report date selection, summary, legacy-data disclosure, empty, and error states.
- CSV import preview summaries, errors, and apply confirmation.

### Final verification

- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`
- Signed release APK build.
- Signed release AAB build.
- Changelog and README updates for the new workflows and release commands.

## Acceptance Criteria

- Existing v1 and v2 databases upgrade without losing products or stock history.
- Users can create, interrupt, resume, and atomically complete partial or full stocktakes.
- Per-product thresholds drive both the dashboard alert center and non-duplicating offline Android notifications.
- Reports calculate current valuation and historical movement locally, with transparent handling of legacy transactions lacking price snapshots.
- Users can preview and atomically apply barcode-based CSV upserts; blank stock is preserved and explicit stock changes are audited.
- Cost and selling prices appear in product workflows, and Sale transactions retain historical price snapshots.
- JSON backup/restore and CSV export remain compatible with existing user data.
- The application retains no runtime dependency on a server, account, or internet connection.
- Formatting, analysis, automated tests, signed release APK, and signed release AAB all pass.
