import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';
import 'shared.dart';

part 'app_database.g.dart';

/// قاعدة البيانات الرئيسية للتطبيق - تعمل Offline بالكامل
/// تستخدم SQLite عبر Drift
@DriftDatabase(tables: [
  Users,
  Roles,
  Permissions,
  RolePermissions,
  Categories,
  Units,
  Products,
  Suppliers,
  Customers,
  Sales,
  SaleItems,
  Purchases,
  PurchaseItems,
  InventoryMovements,
  CashTransactions,
  CustomerPayments,
  SupplierPayments,
  Expenses,
  Withdrawals,
  Returns,
  ReturnItems,
  AuditLogs,
  BackupMetadata,
  Settings,
  Stocktakes,
  StocktakeItems,
], daos: [
  UserDao,
  RoleDao,
  ProductDao,
  CategoryDao,
  UnitDao,
  SupplierDao,
  CustomerDao,
  SaleDao,
  PurchaseDao,
  InventoryMovementDao,
  CashTransactionDao,
  CustomerPaymentDao,
  SupplierPaymentDao,
  ExpenseDao,
  WithdrawalDao,
  ReturnDao,
  AuditLogDao,
  BackupMetadataDao,
  SettingDao,
  StocktakeDao,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _seedDefaults();
      },
      onUpgrade: (m, from, to) async {
        await m.createAll();
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement('PRAGMA journal_mode = WAL');
      },
    );
  }

  /// تهيئة البيانات الافتراضية عند أول تشغيل
  Future<void> _seedDefaults() async {
    // 1) الصلاحيات
    for (final p in _getDefaultPermissions()) {
      await into(permissions).insert(p);
    }
    final allPerms = await select(permissions).get();

    // 2) الأدوار
    final ownerRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'المالك',
      description: const Value('صلاحيات كاملة'),
      isSystemRole: const Value(true),
    ));
    final managerRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'المدير',
      description: const Value('إدارة العمليات والتقارير'),
      isSystemRole: const Value(true),
    ));
    final cashierRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'الكاشير',
      description: const Value('إنشاء مبيعات'),
      isSystemRole: const Value(true),
    ));
    final purchaserRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'المشتري',
      description: const Value('المشتريات والموردون'),
      isSystemRole: const Value(true),
    ));
    final warehouseRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'أمين المخزن',
      description: const Value('المخزون والجرد'),
      isSystemRole: const Value(true),
    ));
    final accountantRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'المحاسب',
      description: const Value('الصندوق والديون والتقارير'),
      isSystemRole: const Value(true),
    ));
    final viewerRoleId = await into(roles).insert(RolesCompanion.insert(
      name: 'مشاهد',
      description: const Value('قراءة فقط'),
      isSystemRole: const Value(true),
    ));

    // 3) ربط الصلاحيات بالأدوار
    // المالك - كل الصلاحيات
    for (final perm in allPerms) {
      await into(rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: ownerRoleId,
        permissionId: perm.id,
      ));
    }

    // المدير - كل الصلاحيات عدا الإعدادات الحساسة والاستعادة
    for (final perm in allPerms) {
      if (perm.code != 'settings.edit' && perm.code != 'backup.restore') {
        await into(rolePermissions).insert(RolePermissionsCompanion.insert(
          roleId: managerRoleId,
          permissionId: perm.id,
        ));
      }
    }

    // الكاشير
    final cashierPermCodes = [
      'sales.view', 'sales.create', 'sales.return', 'sales.discount',
      'customers.view', 'customers.create', 'customers.payment',
      'inventory.view', 'reports.view',
    ];
    for (final code in cashierPermCodes) {
      final perm = allPerms.firstWhere((p) => p.code == code);
      await into(rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: cashierRoleId,
        permissionId: perm.id,
      ));
    }

    // المشتري
    final purchaserPermCodes = [
      'purchase.view', 'purchase.create', 'purchase.edit', 'purchase.return',
      'suppliers.view', 'suppliers.create', 'suppliers.edit', 'suppliers.payment',
      'inventory.view', 'reports.view',
    ];
    for (final code in purchaserPermCodes) {
      final perm = allPerms.firstWhere((p) => p.code == code);
      await into(rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: purchaserRoleId,
        permissionId: perm.id,
      ));
    }

    // أمين المخزن
    final warehousePermCodes = [
      'inventory.view', 'inventory.edit', 'inventory.adjust', 'inventory.stocktake',
      'reports.view', 'reports.inventory',
    ];
    for (final code in warehousePermCodes) {
      final perm = allPerms.firstWhere((p) => p.code == code);
      await into(rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: warehouseRoleId,
        permissionId: perm.id,
      ));
    }

    // المحاسب
    final accountantPermCodes = [
      'cashbox.view', 'cashbox.create', 'cashbox.adjust', 'cashbox.close',
      'customers.view', 'customers.payment',
      'suppliers.view', 'suppliers.payment',
      'reports.view', 'reports.profit', 'reports.cash', 'reports.debts',
      'inventory.view',
    ];
    for (final code in accountantPermCodes) {
      final perm = allPerms.firstWhere((p) => p.code == code);
      await into(rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: accountantRoleId,
        permissionId: perm.id,
      ));
    }

    // المشاهد
    final viewerPermCodes = [
      'sales.view', 'purchase.view', 'inventory.view', 'customers.view',
      'suppliers.view', 'cashbox.view', 'reports.view',
    ];
    for (final code in viewerPermCodes) {
      final perm = allPerms.firstWhere((p) => p.code == code);
      await into(rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: viewerRoleId,
        permissionId: perm.id,
      ));
    }

    // 4) المستخدم الافتراضي - admin/admin123
    await into(users).insert(UsersCompanion.insert(
      username: 'admin',
      displayName: 'المدير العام',
      passwordHash: PasswordHasher.hash('admin123'),
      roleId: ownerRoleId,
      isActive: const Value(true),
    ));

    // 5) الوحدات الافتراضية
    final defaultUnits = [
      UnitsCompanion.insert(name: 'قطعة', symbol: 'ق'),
      UnitsCompanion.insert(name: 'كرتون', symbol: 'ك'),
      UnitsCompanion.insert(name: 'كيلو', symbol: 'كغ'),
      UnitsCompanion.insert(name: 'جرام', symbol: 'غ'),
      UnitsCompanion.insert(name: 'لتر', symbol: 'ل'),
      UnitsCompanion.insert(name: 'متر', symbol: 'م'),
      UnitsCompanion.insert(name: 'باكت', symbol: 'ب'),
      UnitsCompanion.insert(name: 'علبة', symbol: 'ع'),
    ];
    await batch((b) => b.insertAll(units, defaultUnits));

    // 6) التصنيفات الافتراضية
    final defaultCategories = [
      CategoriesCompanion.insert(name: 'مواد غذائية', description: const Value('أغذية معلبة وطازجة')),
      CategoriesCompanion.insert(name: 'مشروبات', description: const Value('عصائر ومشروبات غازية')),
      CategoriesCompanion.insert(name: 'منظفات', description: const Value('مواد تنظيف')),
      CategoriesCompanion.insert(name: 'حلويات', description: const Value('حلويات وبسكويت')),
      CategoriesCompanion.insert(name: 'ألبان', description: const Value('حليب ومشتقاته')),
      CategoriesCompanion.insert(name: 'خبز ومخبوزات', description: const Value('خبز ومعجنات')),
      CategoriesCompanion.insert(name: 'أخرى', description: const Value('منتجات متنوعة')),
    ];
    await batch((b) => b.insertAll(categories, defaultCategories));

    // 7) الإعدادات الافتراضية
    await into(settings).insert(SettingsCompanion.insert(
      storeName: const Value('بقالتي'),
      currency: const Value('ر.ي'),
      preventNegativeStock: const Value(true),
      allowOverpayment: const Value(false),
      cashboxOpeningBalance: const Value(0),
      taxEnabled: const Value(false),
      taxRate: const Value(0),
    ));
  }

  List<PermissionsCompanion> _getDefaultPermissions() {
    return [
      PermissionsCompanion.insert(code: 'sales.view', name: 'عرض المبيعات', module: 'sales'),
      PermissionsCompanion.insert(code: 'sales.create', name: 'إنشاء مبيعات', module: 'sales'),
      PermissionsCompanion.insert(code: 'sales.edit', name: 'تعديل مبيعات', module: 'sales'),
      PermissionsCompanion.insert(code: 'sales.delete', name: 'حذف مبيعات', module: 'sales'),
      PermissionsCompanion.insert(code: 'sales.return', name: 'مرتجع مبيعات', module: 'sales'),
      PermissionsCompanion.insert(code: 'sales.discount', name: 'خصم مبيعات', module: 'sales'),
      PermissionsCompanion.insert(code: 'sales.change_price', name: 'تغيير سعر البيع', module: 'sales'),
      PermissionsCompanion.insert(code: 'purchase.view', name: 'عرض المشتريات', module: 'purchase'),
      PermissionsCompanion.insert(code: 'purchase.create', name: 'إنشاء مشتريات', module: 'purchase'),
      PermissionsCompanion.insert(code: 'purchase.edit', name: 'تعديل مشتريات', module: 'purchase'),
      PermissionsCompanion.insert(code: 'purchase.delete', name: 'حذف مشتريات', module: 'purchase'),
      PermissionsCompanion.insert(code: 'purchase.return', name: 'مرتجع مشتريات', module: 'purchase'),
      PermissionsCompanion.insert(code: 'inventory.view', name: 'عرض المخزون', module: 'inventory'),
      PermissionsCompanion.insert(code: 'inventory.edit', name: 'تعديل المخزون', module: 'inventory'),
      PermissionsCompanion.insert(code: 'inventory.adjust', name: 'تسوية المخزون', module: 'inventory'),
      PermissionsCompanion.insert(code: 'inventory.stocktake', name: 'جرد المخزون', module: 'inventory'),
      PermissionsCompanion.insert(code: 'customers.view', name: 'عرض العملاء', module: 'customers'),
      PermissionsCompanion.insert(code: 'customers.create', name: 'إنشاء عميل', module: 'customers'),
      PermissionsCompanion.insert(code: 'customers.edit', name: 'تعديل عميل', module: 'customers'),
      PermissionsCompanion.insert(code: 'customers.delete', name: 'حذف عميل', module: 'customers'),
      PermissionsCompanion.insert(code: 'customers.payment', name: 'سداد عميل', module: 'customers'),
      PermissionsCompanion.insert(code: 'suppliers.view', name: 'عرض الموردين', module: 'suppliers'),
      PermissionsCompanion.insert(code: 'suppliers.create', name: 'إنشاء مورد', module: 'suppliers'),
      PermissionsCompanion.insert(code: 'suppliers.edit', name: 'تعديل مورد', module: 'suppliers'),
      PermissionsCompanion.insert(code: 'suppliers.delete', name: 'حذف مورد', module: 'suppliers'),
      PermissionsCompanion.insert(code: 'suppliers.payment', name: 'سداد مورد', module: 'suppliers'),
      PermissionsCompanion.insert(code: 'cashbox.view', name: 'عرض الصندوق', module: 'cashbox'),
      PermissionsCompanion.insert(code: 'cashbox.create', name: 'حركة صندوق', module: 'cashbox'),
      PermissionsCompanion.insert(code: 'cashbox.adjust', name: 'تسوية صندوق', module: 'cashbox'),
      PermissionsCompanion.insert(code: 'cashbox.close', name: 'إغلاق يوم', module: 'cashbox'),
      PermissionsCompanion.insert(code: 'reports.view', name: 'عرض التقارير', module: 'reports'),
      PermissionsCompanion.insert(code: 'reports.profit', name: 'تقرير الأرباح', module: 'reports'),
      PermissionsCompanion.insert(code: 'reports.cash', name: 'تقرير الصندوق', module: 'reports'),
      PermissionsCompanion.insert(code: 'reports.debts', name: 'تقرير الديون', module: 'reports'),
      PermissionsCompanion.insert(code: 'reports.inventory', name: 'تقرير المخزون', module: 'reports'),
      PermissionsCompanion.insert(code: 'users.view', name: 'عرض المستخدمين', module: 'users'),
      PermissionsCompanion.insert(code: 'users.create', name: 'إنشاء مستخدم', module: 'users'),
      PermissionsCompanion.insert(code: 'users.edit', name: 'تعديل مستخدم', module: 'users'),
      PermissionsCompanion.insert(code: 'users.delete', name: 'حذف مستخدم', module: 'users'),
      PermissionsCompanion.insert(code: 'settings.view', name: 'عرض الإعدادات', module: 'settings'),
      PermissionsCompanion.insert(code: 'settings.edit', name: 'تعديل الإعدادات', module: 'settings'),
      PermissionsCompanion.insert(code: 'backup.create', name: 'إنشاء نسخة احتياطية', module: 'backup'),
      PermissionsCompanion.insert(code: 'backup.restore', name: 'استعادة نسخة احتياطية', module: 'backup'),
    ];
  }

  /// مسح جميع البيانات (لاستعادة النسخ الاحتياطي)
  Future<void> clearAllData() async {
    await customStatement('PRAGMA foreign_keys = OFF');
    for (final table in allTables) {
      await customUpdate('DELETE FROM ${table.actualTableName}');
    }
    await customStatement('PRAGMA foreign_keys = ON');
  }

  /// نسخ احتياطي: تصدير كل الجداول كـ Map
  Future<Map<String, dynamic>> exportAllData() async {
    final result = <String, dynamic>{};
    for (final table in allTables) {
      final rows = await customSelect('SELECT * FROM ${table.actualTableName}').get();
      result[table.actualTableName] = rows.map((r) => r.data).toList();
    }
    return result;
  }

  /// تنفيذ معاملة (transaction) آمنة
  Future<T> runInTransactionSafe<T>(Future<T> Function() action) {
    return transaction(action);
  }
}

/// تشفير كلمات المرور باستخدام SHA-256 + salt
class PasswordHasher {
  PasswordHasher._();

  /// تشفير كلمة المرور
  /// النتيجة بصيغة: salt$hash
  static String hash(String password) {
    final salt = _generateSalt();
    final hashValue = _hashWithSalt(password, salt);
    return '$salt\$$hashValue';
  }

  /// التحقق من كلمة المرور
  static bool verify(String password, String storedHash) {
    final parts = storedHash.split(r'$');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final hash = parts[1];
    final computedHash = _hashWithSalt(password, salt);
    return computedHash == hash;
  }

  static String _generateSalt() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final randomBytes = utf8.encode('$random${DateTime.now().millisecondsSinceEpoch}');
    return sha256.convert(randomBytes).toString().substring(0, 32);
  }

  static String _hashWithSalt(String password, String salt) {
    final bytes = utf8.encode('$salt$password$salt');
    return sha256.convert(bytes).toString();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'grocery_erp.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        db.execute('PRAGMA foreign_keys = ON');
        db.execute('PRAGMA journal_mode = WAL');
      },
    );
  });
}
