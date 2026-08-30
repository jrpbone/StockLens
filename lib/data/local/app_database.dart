import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._([this._overridePath]);
  static final instance = AppDatabase._();
  factory AppDatabase.forTesting(String path) => AppDatabase._(path);

  final String? _overridePath;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path =
        _overridePath ?? p.join(await getDatabasesPath(), 'stocklens.db');
    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE products ADD COLUMN archived_at TEXT');
          await _createTransactionsTable(db, includeVersion3Columns: false);
          await _createMetadataTable(db);
        }
        if (oldVersion < 3) await _upgradeToVersion3(db);
      },
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            barcode TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            price REAL NOT NULL CHECK(price >= 0),
            cost_price REAL NOT NULL DEFAULT 0 CHECK(cost_price >= 0),
            low_stock_threshold INTEGER NOT NULL DEFAULT 5 CHECK(low_stock_threshold >= 0),
            low_stock_notified INTEGER NOT NULL DEFAULT 0 CHECK(low_stock_notified IN (0, 1)),
            category TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            quantity INTEGER NOT NULL CHECK(quantity >= 0),
            image_path TEXT,
            archived_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
    await db.execute(
      'CREATE INDEX idx_products_name ON products(name COLLATE NOCASE)',
    );
    await _createTransactionsTable(db);
    await _createMetadataTable(db);
    await _createStocktakeTables(db);
    await _createVersion3Indexes(db);
  }

  Future<void> _createMetadataTable(Database db) => db.execute('''
    CREATE TABLE app_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  Future<void> _createTransactionsTable(
    Database db, {
    bool includeVersion3Columns = true,
  }) async {
    final version3Columns = includeVersion3Columns
        ? '''
        ,selling_price_snapshot REAL
        ,cost_price_snapshot REAL
        ,source TEXT
        ,source_id TEXT'''
        : '';
    await db.execute('''
      CREATE TABLE stock_transactions (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        delta INTEGER NOT NULL,
        reason TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        previous_quantity INTEGER NOT NULL CHECK(previous_quantity >= 0),
        resulting_quantity INTEGER NOT NULL CHECK(resulting_quantity >= 0),
        occurred_at TEXT NOT NULL$version3Columns,
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_transactions_product_date '
      'ON stock_transactions(product_id, occurred_at DESC)',
    );
  }

  Future<void> _upgradeToVersion3(Database db) async {
    await db.execute(
      'ALTER TABLE products ADD COLUMN cost_price REAL NOT NULL DEFAULT 0 '
      'CHECK(cost_price >= 0)',
    );
    await db.execute(
      'ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER NOT NULL '
      'DEFAULT 5 CHECK(low_stock_threshold >= 0)',
    );
    await db.execute(
      'ALTER TABLE products ADD COLUMN low_stock_notified INTEGER NOT NULL '
      'DEFAULT 0 CHECK(low_stock_notified IN (0, 1))',
    );
    await db.execute(
      'ALTER TABLE stock_transactions ADD COLUMN selling_price_snapshot REAL',
    );
    await db.execute(
      'ALTER TABLE stock_transactions ADD COLUMN cost_price_snapshot REAL',
    );
    await db.execute('ALTER TABLE stock_transactions ADD COLUMN source TEXT');
    await db.execute(
      'ALTER TABLE stock_transactions ADD COLUMN source_id TEXT',
    );
    await _createStocktakeTables(db);
    await _createVersion3Indexes(db);
  }

  Future<void> _createStocktakeTables(Database db) async {
    await db.execute('''
      CREATE TABLE stocktake_sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('in_progress', 'completed')),
        scope_description TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE stocktake_items (
        session_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        expected_quantity INTEGER NOT NULL CHECK(expected_quantity >= 0),
        counted_quantity INTEGER CHECK(counted_quantity >= 0),
        updated_at TEXT NOT NULL,
        PRIMARY KEY(session_id, product_id),
        FOREIGN KEY(session_id) REFERENCES stocktake_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createVersion3Indexes(Database db) async {
    await db.execute(
      'CREATE INDEX idx_products_active_low_stock '
      'ON products(archived_at, low_stock_threshold, quantity)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_date_reason '
      'ON stock_transactions(occurred_at DESC, reason)',
    );
    await db.execute(
      'CREATE INDEX idx_stocktake_sessions_status_date '
      'ON stocktake_sessions(status, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_stocktake_items_product ON stocktake_items(product_id)',
    );
  }
}
