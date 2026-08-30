# Changelog

All notable changes to StockLens are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Upgraded the SQLite database to schema version 4, which reconciles the previously shipped POS and offline-inventory version-3 layouts into one combined schema.

### Fixed

- Preserved existing products, stock transactions, sales orders, and stocktake sessions when upgrading either historical version-3 layout.
- Made creation of the sales, stocktake, and supporting index structures idempotent so migration adds only the missing schema components.

### Verification

- Added real SQLite migration regressions for both historical version-3 database layouts, including close-and-reopen persistence checks.
- Expanded cross-feature backup/restore coverage to include POS orders, stocktake sessions, manual stock changes, and CSV imports in the same database.
- Dart formatting passed, Flutter analysis reported no issues, and all 139 automated tests passed.
- Android release artifacts were not regenerated for this source-only fix.

## [0.3.0] - 2026-08-30

Offline stock control, per-product alerts, local reporting, and atomic CSV imports.

### Added

- Added a complete POS workflow with camera/manual barcode entry, stock-aware cart controls, live totals, confirmation, and atomic checkout.
- Added persistent order history grouped by date with expandable snapshot-based line-item details.
- Added SQLite sales backup/restore and coverage for checkout rollback, historical snapshots, order numbering, and schema migration.
- Added resumable stocktake sessions for full, category, and individually selected product scopes, including autosaved counts, barcode increments, variance review, stale-preview rejection, and atomic reconciliation.
- Added per-product low-stock thresholds, an in-app alert center, and optional Android notifications with duplicate suppression and settings recovery.
- Added offline inventory valuation and movement reports with preset/custom ranges, sales profitability, category totals, fast movers, inactive stock, and legacy-price disclosure.
- Added previewed barcode-based CSV upserts with strict UTF-8 parsing, row-numbered validation, archived conflicts, stale-preview rejection, atomic apply, and shared import audit IDs.
- Added separate cost and selling prices plus historical price snapshots on new stock transactions.
- Added schema-v3 database migrations, stocktake tables, report indexes, and sourced transaction metadata.
- Added cross-feature regression coverage for backup/restore, stocktake state, CSV audit linkage, and historical reports.
- Added an Android release-signing setup assistant with safe local credential handling.

### Changed

- Upgraded the database to schema version 3 with `orders` and `order_items` tables using integer centavos for sale totals.
- Serialized Scan/POS camera ownership through one shared controller so direct tab switches cannot race native camera teardown and startup.
- Upgraded complete backups to format version 2 with pricing fields, transaction snapshots/source metadata, sales orders/items, stocktake sessions, and stocktake items while retaining version-1 and both historical version-2 restore shapes.
- Expanded inventory CSV export with selling price, cost price, low-stock threshold, and archive status.
- Updated the application version to `0.3.0+4`.
- Reduced the packaging assistant to a focused Android-only APK/AAB workflow while preserving interactive metadata, checks, obfuscation, ABI splitting, checksums, and build manifests.
- Restricted the run assistant to connected Android devices and emulators so it cannot accidentally launch an unsupported desktop or browser target.
- Reworked the README as an Android-only project showcase while keeping the technology stack prominent at the top.
- Reduced launcher-icon generation to Android and removed the unused Cupertino icon dependency.

### Removed

- Removed unused iOS, macOS, Linux, Windows, and web platform scaffolding.
- Removed the remote iOS GitHub Actions workflow and its token/API/build client.
- Removed duplicate default Android launcher icons that were not referenced by the manifest.

### Dependencies

- Added `csv` for standards-based quoted CSV parsing.

### Verification

- Dart formatting completed successfully.
- Static analysis completed with no issues.
- All 137 automated tests passed after combining POS/sales and offline-inventory coverage.
- Signed release APK and AAB artifacts were generated with SHA-256 records and verified release manifests.

## [0.2.0] - 2026-08-12

Auditable inventory operations, recoverable product management, and Android data safety.

### Added

- Added persistent stock transaction history containing the quantity delta, reason, optional note, previous and resulting quantities, and timestamp.
- Added an on-product stock history timeline and an initial-stock record for newly created products.
- Added archival with confirmation, an Archived Products screen, restoration, and separately confirmed permanent deletion.
- Added portable JSON backup and restore for products, embedded product images, archive state, and complete stock history.
- Added CSV inventory export for active and archived products through the Android share sheet.
- Added permanent app-managed storage for selected product images, replacement cleanup, and image removal.
- Added manual barcode entry, scan-success haptics, and scan-success sound.
- Added Android upload-keystore configuration, ignored signing secrets, and release-signing setup documentation.
- Added a secure PowerShell signing setup assistant with local random-password generation, overwrite protection, and keystore verification.
- Added real SQLite repository tests for atomic adjustments, negative-stock rollback, archive and restore, cascading deletion, backup recovery, and v1-to-v2 migration.

### Changed

- Upgraded the database to schema version 2 with archive metadata and a foreign-keyed `stock_transactions` table.
- Made stock quantity read-only while editing a product so inventory changes cannot bypass the transaction history.
- Replaced the example Android namespace and application ID with `com.jrpbone.stocklens`.
- Removed the Android release build's insecure fallback to the debug signing key.
- Made the build assistant default to debug mode until release signing is configured, while rejecting explicit unsigned release requests with setup guidance.
- Updated the application version to `0.2.0+3`.

### Dependencies

- Added `path_provider` for managed image and export locations.
- Added `file_picker` for selecting backup files to restore.
- Added `share_plus` for Android backup and CSV sharing.
- Added `sqflite_common_ffi` as a development dependency for database integration tests.

### Verification

- Dart formatting completed successfully.
- Static analysis completed with no issues.
- All 10 automated tests passed.
- Android debug APK, debug AAB, and production-signed release AAB generation completed successfully.
- The release AAB signature was verified and its SHA-256 checksum was recorded by the build assistant.
- PowerShell build-assistant syntax validation completed successfully.
- Physical Android scanner and permission validation remains pending because no Android device was connected.

## [0.1.1] - 2026-08-12

Automated verification and cross-platform development builds.

### Added

- Added a GitHub Actions workflow that checks formatting, runs static analysis and automated tests, and builds an installable Android debug APK on pushes, pull requests, and manual runs.
- Added downloadable CI artifacts containing the debug APK and its SHA-256 checksum, retained for 14 days.
- Added cancellation of superseded CI runs on the same Git reference.
- Added a numbered in-script menu for selecting `android`, `ios`, or `both` targets, while retaining `-Target` for non-interactive automation.
- Added standalone unsigned iOS `.app` archives for iOS-only and combined builds performed on macOS with Xcode.
- Added a manually dispatched macOS GitHub Actions workflow for unsigned iOS builds.
- Added Windows/Linux remote iOS dispatch, status monitoring, artifact download, and SHA-256 verification directly through the GitHub REST API.

### Changed

- Moved the delivery roadmap from the showcase README into `TODO.md`.
- Restored the README hero with project branding and prominent Flutter, Dart, SQLite, Android, and Material 3 technology badges.
- Corrected both PowerShell assistants to resolve the project root from the `tools` directory.
- Updated the application version to `0.1.1+2`.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` completed successfully.
- Static analysis completed with no issues.
- All 2 automated tests passed.
- Android debug APK generation completed successfully.
- The generated `0.1.1+2` APK passed Android signature verification using the debug certificate.

## [0.1.0] - 2026-08-11

Initial MVP release.

### Added

- Generated and integrated a custom StockLens launcher icon across Android, iOS, web, Windows, and macOS targets.
- Added the canonical 1024px icon source at `assets/branding/stocklens_icon.png`.
- Added `TODO.md` with a prioritized backlog for release hardening, inventory operations, accounts, synchronization, reporting, UX, engineering quality, and future integrations.
- Added `build_stocklens.ps1`, an interactive packaging assistant for application metadata, versioning, quality checks, APK/AAB creation, obfuscation, ABI splitting, checksums, and build manifests. It does not require or connect to a phone.
- Added preflight symbolic-link checks to both PowerShell assistants, including guided Developer Mode setup and automatic capability retry before Flutter runs.
- Changed the Windows symbolic-link preflight to use Dart's native `Link.createSync`, matching Flutter and avoiding false failures from Windows PowerShell 5.1.
- Flutter application initialization and reusable Material 3 light theme.
- Responsive home dashboard with StockLens branding, product counts, low-stock counts, and quick actions.
- Bottom navigation for Home, Scan, Inventory, and Search.
- Null-safe `Product` model containing ID, barcode, name, price, category, description, quantity, optional image path, and timestamps.
- Product JSON serialization, deserialization, and `copyWith` support, including explicit nullable image updates.
- SQLite database with a `products` table, non-negative price and quantity constraints, a unique barcode constraint, and a case-insensitive product-name index.
- Repository interface separating UI and business logic from local persistence.
- SQLite repository implementation that can later be replaced by an API-backed repository.
- Product service for initialization, lookup, creation, editing, and guarded stock adjustments.
- First-run sample data for Coca-Cola 1.5L, Lucky Me Pancit Canton, Safeguard Soap, and Century Tuna.
- Inventory screen with product cards, optional thumbnails, price, category, quantity, and stock status.
- Live inventory search by product name, barcode, or category.
- Category filtering.
- Inventory sorting by name A–Z, name Z–A, price ascending, price descending, lowest stock, highest stock, and newest.
- Floating Add Product action from the inventory screen.
- Add Product form supporting manual and scanner-provided barcodes.
- Validation for required barcodes and names, non-negative numeric prices, and non-negative integer quantities.
- Duplicate-barcode error handling.
- Optional product-image selection from the device photo library.
- Product Details screen with image, Philippine Peso price formatting, barcode, category, stock, description, and stock badge.
- Edit Product workflow for all product fields.
- Confirmation warning before changing an existing barcode.
- Manual product search with live results.
- Barcode scanner using `mobile_scanner`, common-format detection, camera preview, scan overlay, flashlight control, camera switching, and tap-to-focus.
- Duplicate-scan cooldown to prevent rapid repeated barcode handling.
- Barcode lookup navigation to Product Details when a product exists.
- Unknown-barcode dialog with cancellation or Add Product navigation and automatic barcode insertion.
- Camera permission-denied and camera-start error states.
- Stock adjustment dialog supporting addition and removal.
- Adjustment reasons: Restock, Sale, Damaged Item, Expired Item, Inventory Correction, and Other.
- Negative-stock prevention and save-failure feedback.
- Reusable product card, product image, search bar, stock badge, and asynchronous error-state widgets.
- Android camera permission and optional-camera feature declaration.
- iOS camera and photo-library usage descriptions.
- Product model unit test and home dashboard widget test.

### Changed

- Replaced the default Flutter counter application with StockLens.
- Updated the Android application label to `StockLens`.
- Updated the package description to describe the barcode inventory system.
- Set the application version to `0.1.0+1`.
- Redesigned the README as a GitHub showcase with release badges, feature highlights, architecture diagrams, setup instructions, verification status, and a public roadmap.
- Added `run_stocklens.ps1`, a Windows launcher with Flutter detection, package restoration, optional device selection, and passthrough arguments for `flutter run`.

### Dependencies

- Added `sqflite` for local SQLite storage.
- Added `path` for database path construction.
- Added `intl` for Philippine Peso formatting.
- Added `mobile_scanner` for barcode scanning.
- Added `image_picker` for product image selection.
- Added `uuid` for locally generated product identifiers.
- Added `flutter_launcher_icons` as a development dependency for reproducible platform icon generation.

### Verification

- `flutter analyze` completed with no issues.
- `flutter test` completed successfully with 2 passing tests.
- Android debug APK generation was attempted but could not proceed because the development machine did not have an Android SDK installed.

### Known Limitations

- No remote backend, synchronization, authentication, or authorization.
- No persisted stock transaction history despite adjustment-reason selection.
- Product images reference local device files.
- No product deletion workflow.
- Barcode scanning has not yet been validated on a physical Android device.
