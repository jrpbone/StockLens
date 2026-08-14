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
          await _createTransactionsTable(db);
          await _createMetadataTable(db);
        }
        if (oldVersion < 3) await _createSalesTables(db);
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
    await _createSalesTables(db);
  }

  Future<void> _createMetadataTable(Database db) => db.execute('''
    CREATE TABLE app_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  Future<void> _createTransactionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE stock_transactions (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        delta INTEGER NOT NULL,
        reason TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        previous_quantity INTEGER NOT NULL CHECK(previous_quantity >= 0),
        resulting_quantity INTEGER NOT NULL CHECK(resulting_quantity >= 0),
        occurred_at TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_transactions_product_date '
      'ON stock_transactions(product_id, occurred_at DESC)',
    );
  }

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL UNIQUE,
        transaction_date TEXT NOT NULL,
        transaction_time TEXT NOT NULL,
        total_amount_cents INTEGER NOT NULL CHECK(total_amount_cents >= 0),
        total_items INTEGER NOT NULL CHECK(total_items > 0),
        total_quantity INTEGER NOT NULL CHECK(total_quantity > 0),
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_orders_created_at ON orders(created_at DESC)',
    );
    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        sku TEXT NOT NULL,
        barcode TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents >= 0),
        subtotal_cents INTEGER NOT NULL CHECK(subtotal_cents >= 0),
        created_at TEXT NOT NULL,
        FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_order_items_order ON order_items(order_id)',
    );
  }
}
