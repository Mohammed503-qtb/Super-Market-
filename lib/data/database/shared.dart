import 'package:drift/drift.dart';
import 'app_database.dart';
import 'tables.dart';

part 'shared.g.dart';

/// DAO المستخدمين
@DriftAccessor(tables: [Users, Roles, RolePermissions, Permissions])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  Future<User?> findByUsername(String username) {
    return (select(users)..where((u) => u.username.equals(username))).getSingleOrNull();
  }

  Future<User?> findById(int id) {
    return (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  }

  Future<List<User>> getAll() => select(users).get();

  Future<List<User>> getActive() =>
      (select(users)..where((u) => u.isActive.equals(true))).get();

  Future<int> insertUser(UsersCompanion user) => into(users).insert(user);

  Future<bool> updateUser(User user) => update(users).replace(user);

  Future<int> deleteUser(int id) =>
      (delete(users)..where((u) => u.id.equals(id))).go();

  Future<void> updateLastLogin(int userId) {
    return (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(lastLoginAt: Value(DateTime.now())),
    );
  }

  /// جلب جميع صلاحيات المستخدم عبر دوره
  Future<List<Permission>> getPermissionsForUser(int userId) async {
    final user = await findById(userId);
    if (user == null) return [];
    final query = select(permissions).join([
      innerJoin(rolePermissions, rolePermissions.permissionId.equalsExp(permissions.id)),
    ])
      ..where(rolePermissions.roleId.equals(user.roleId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(permissions)).toList();
  }

  /// التحقق من صلاحية محددة
  Future<bool> hasPermission(int userId, String permissionCode) async {
    final perms = await getPermissionsForUser(userId);
    return perms.any((p) => p.code == permissionCode);
  }

  /// جلب صلاحيات الدور
  Future<List<Permission>> getPermissionsForRole(int roleId) async {
    final query = select(permissions).join([
      innerJoin(rolePermissions, rolePermissions.permissionId.equalsExp(permissions.id)),
    ])
      ..where(rolePermissions.roleId.equals(roleId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(permissions)).toList();
  }

  Future<void> setRolePermissions(int roleId, List<int> permissionIds) async {
    await (delete(rolePermissions)..where((rp) => rp.roleId.equals(roleId))).go();
    for (final pid in permissionIds) {
      await into(rolePermissions).insert(
        RolePermissionsCompanion.insert(roleId: roleId, permissionId: pid),
      );
    }
  }
}

/// DAO الأدوار
@DriftAccessor(tables: [Roles, Permissions, RolePermissions])
class RoleDao extends DatabaseAccessor<AppDatabase> with _$RoleDaoMixin {
  RoleDao(super.db);

  Future<List<Role>> getAll() => select(roles).get();

  Future<Role?> findById(int id) =>
      (select(roles)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<int> insertRole(RolesCompanion role) => into(roles).insert(role);

  Future<bool> updateRole(Role role) => update(roles).replace(role);

  Future<int> deleteRole(int id) =>
      (delete(roles)..where((r) => r.id.equals(id))).go();

  Future<List<Permission>> getAllPermissions() => select(permissions).get();

  Future<List<Permission>> getPermissionsByModule(String module) =>
      (select(permissions)..where((p) => p.module.equals(module))).get();
}

/// DAO المنتجات
@DriftAccessor(tables: [Products, Categories, Units])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  Future<List<Product>> getAll() => select(products).get();

  Future<Product?> findById(int id) =>
      (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Product?> findByBarcode(String barcode) =>
      (select(products)..where((p) => p.barcode.equals(barcode))).getSingleOrNull();

  Future<List<Product>> search(String query) {
    final pattern = '%$query%';
    return (select(products)
          ..where((p) =>
              p.name.like(pattern) |
              p.barcode.like(pattern) |
              p.sku.like(pattern))
          ..limit(50))
        .get();
  }

  Future<List<Product>> getActive() =>
      (select(products)..where((p) => p.isActive.equals(true))).get();

  Future<List<Product>> getLowStock() {
    return (select(products)
          ..where((p) => p.currentStock.isSmallerOrEqualValue(0)))
        .get();
  }

  /// أصناف وصلت للحد الأدنى للمخزون
  Future<List<Product>> getBelowMinimumStock() async {
    final allProducts = await select(products).get();
    return allProducts
        .where((p) => p.currentStock <= p.minimumStock && p.minimumStock > 0)
        .toList();
  }

  Future<int> insertProduct(ProductsCompanion product) => into(products).insert(product);

  Future<bool> updateProduct(Product product) => update(products).replace(product);

  Future<int> deleteProduct(int id) =>
      (delete(products)..where((p) => p.id.equals(id))).go();

  /// تحديث المخزون والتكلفة المرجحة
  Future<void> updateStock(int productId, num newStock, num newAverageCost) {
    return (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        currentStock: Value(newStock.toDouble()),
        averageCost: Value(newAverageCost.toDouble()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// تحديث السعر فقط
  Future<void> updatePrices(
    int productId, {
    num? purchasePrice,
    num? sellingPrice,
    num? wholesalePrice,
  }) {
    return (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        purchasePrice: purchasePrice != null ? Value(purchasePrice.toDouble()) : const Value.absent(),
        sellingPrice: sellingPrice != null ? Value(sellingPrice.toDouble()) : const Value.absent(),
        wholesalePrice: wholesalePrice != null ? Value(wholesalePrice.toDouble()) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> count() async {
    final count = await customSelect('SELECT COUNT(*) AS c FROM products').getSingle();
    return count.read<int>('c');
  }
}

/// DAO التصنيفات
@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Future<List<Category>> getAll() => select(categories).get();

  Future<List<Category>> getActive() =>
      (select(categories)..where((c) => c.isActive.equals(true))).get();

  Future<Category?> findById(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> insertCategory(CategoriesCompanion category) =>
      into(categories).insert(category);

  Future<bool> updateCategory(Category category) =>
      update(categories).replace(category);

  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();
}

/// DAO الوحدات
@DriftAccessor(tables: [Units])
class UnitDao extends DatabaseAccessor<AppDatabase> with _$UnitDaoMixin {
  UnitDao(super.db);

  Future<List<Unit>> getAll() => select(units).get();

  Future<Unit?> findById(int id) =>
      (select(units)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<int> insertUnit(UnitsCompanion unit) => into(units).insert(unit);

  Future<bool> updateUnit(Unit unit) => update(units).replace(unit);

  Future<int> deleteUnit(int id) =>
      (delete(units)..where((u) => u.id.equals(id))).go();
}

/// DAO الموردين
@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase> with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Future<List<Supplier>> getAll() => select(suppliers).get();

  Future<Supplier?> findById(int id) =>
      (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<Supplier>> search(String query) {
    final pattern = '%$query%';
    return (select(suppliers)
          ..where((s) => s.name.like(pattern) | s.phone.like(pattern))
          ..limit(50))
        .get();
  }

  Future<int> insertSupplier(SuppliersCompanion supplier) =>
      into(suppliers).insert(supplier);

  Future<bool> updateSupplier(Supplier supplier) =>
      update(suppliers).replace(supplier);

  Future<int> deleteSupplier(int id) =>
      (delete(suppliers)..where((s) => s.id.equals(id))).go();

  /// تحديث رصيد المورد
  Future<void> updateBalance(int supplierId, num newBalance) {
    return (update(suppliers)..where((s) => s.id.equals(supplierId))).write(
      SuppliersCompanion(
        currentBalance: Value(newBalance.toDouble()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

/// DAO العملاء
@DriftAccessor(tables: [Customers])
class CustomerDao extends DatabaseAccessor<AppDatabase> with _$CustomerDaoMixin {
  CustomerDao(super.db);

  Future<List<Customer>> getAll() => select(customers).get();

  Future<Customer?> findById(int id) =>
      (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<Customer>> search(String query) {
    final pattern = '%$query%';
    return (select(customers)
          ..where((c) => c.name.like(pattern) | c.phone.like(pattern))
          ..limit(50))
        .get();
  }

  Future<int> insertCustomer(CustomersCompanion customer) =>
      into(customers).insert(customer);

  Future<bool> updateCustomer(Customer customer) =>
      update(customers).replace(customer);

  Future<int> deleteCustomer(int id) =>
      (delete(customers)..where((c) => c.id.equals(id))).go();

  /// تحديث رصيد العميل
  Future<void> updateBalance(int customerId, num newBalance) {
    return (update(customers)..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(
        currentBalance: Value(newBalance.toDouble()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

/// DAO المبيعات
@DriftAccessor(tables: [Sales, SaleItems])
class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
  SaleDao(super.db);

  Future<List<Sale>> getAll() =>
      (select(sales)..orderBy([(s) => OrderingTerm.desc(s.createdAt)])).get();

  Future<List<Sale>> getRecent({int limit = 50}) =>
      (select(sales)
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
            ..limit(limit))
          .get();

  Future<Sale?> findById(int id) =>
      (select(sales)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<Sale?> findByInvoiceNumber(String number) =>
      (select(sales)..where((s) => s.invoiceNumber.equals(number)))
          .getSingleOrNull();

  Future<List<Sale>> getByCustomer(int customerId) =>
      (select(sales)
            ..where((s) => s.customerId.equals(customerId))
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<List<Sale>> getByDateRange(DateTime start, DateTime end) =>
      (select(sales)
            ..where((s) => s.createdAt.isBetweenValues(start, end))
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<int> insertSale(SalesCompanion sale) => into(sales).insert(sale);

  Future<bool> updateSale(Sale sale) => update(sales).replace(sale);

  Future<List<SaleItem>> getItems(int saleId) =>
      (select(saleItems)..where((si) => si.saleId.equals(saleId))).get();

  Future<void> insertItems(List<SaleItemsCompanion> items) async {
    await batch((b) => b.insertAll(saleItems, items));
  }

  /// الحصول على أعلى رقم تسلسلي لليوم
  Future<int> getNextSequenceForToday(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM sales WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<int>('c') + 1;
  }

  /// إجمالي المبيعات لفترة
  Future<num> totalSales(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(total), 0) AS t FROM sales WHERE created_at >= ? AND created_at < ? AND status = ?',
      variables: [Variable(start), Variable(end), Variable<String>('COMPLETED')],
    ).getSingle();
    return result.read<double>('t');
  }

  Future<num> totalCashSales(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(paid_amount), 0) AS t FROM sales WHERE created_at >= ? AND created_at < ? AND status = ?',
      variables: [Variable(start), Variable(end), Variable<String>('COMPLETED')],
    ).getSingle();
    return result.read<double>('t');
  }
}

/// DAO المشتريات
@DriftAccessor(tables: [Purchases, PurchaseItems])
class PurchaseDao extends DatabaseAccessor<AppDatabase> with _$PurchaseDaoMixin {
  PurchaseDao(super.db);

  Future<List<Purchase>> getRecent({int limit = 50}) =>
      (select(purchases)
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
            ..limit(limit))
          .get();

  Future<Purchase?> findById(int id) =>
      (select(purchases)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<List<Purchase>> getBySupplier(int supplierId) =>
      (select(purchases)
            ..where((p) => p.supplierId.equals(supplierId))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
          .get();

  Future<int> insertPurchase(PurchasesCompanion purchase) =>
      into(purchases).insert(purchase);

  Future<bool> updatePurchase(Purchase purchase) =>
      update(purchases).replace(purchase);

  Future<List<PurchaseItem>> getItems(int purchaseId) =>
      (select(purchaseItems)..where((pi) => pi.purchaseId.equals(purchaseId)))
          .get();

  Future<void> insertItems(List<PurchaseItemsCompanion> items) async {
    await batch((b) => b.insertAll(purchaseItems, items));
  }

  Future<int> getNextSequenceForToday(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM purchases WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<int>('c') + 1;
  }

  Future<num> totalPurchases(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(total), 0) AS t FROM purchases WHERE created_at >= ? AND created_at < ? AND status = ?',
      variables: [Variable(start), Variable(end), Variable<String>('COMPLETED')],
    ).getSingle();
    return result.read<double>('t');
  }
}

/// DAO حركات المخزون
@DriftAccessor(tables: [InventoryMovements])
class InventoryMovementDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryMovementDaoMixin {
  InventoryMovementDao(super.db);

  Future<int> insertMovement(InventoryMovementsCompanion movement) =>
      into(inventoryMovements).insert(movement);

  Future<void> insertMovements(List<InventoryMovementsCompanion> moves) async {
    await batch((b) => b.insertAll(inventoryMovements, moves));
  }

  Future<List<InventoryMovement>> getByProduct(int productId) =>
      (select(inventoryMovements)
            ..where((m) => m.productId.equals(productId))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
          .get();

  Future<List<InventoryMovement>> getByDateRange(DateTime start, DateTime end) =>
      (select(inventoryMovements)
            ..where((m) => m.createdAt.isBetweenValues(start, end))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
          .get();

  Future<List<InventoryMovement>> getByReference(
      String referenceType, int referenceId) {
    return (select(inventoryMovements)
          ..where((m) =>
              m.referenceType.equals(referenceType) &
              m.referenceId.equals(referenceId)))
        .get();
  }
}

/// DAO حركات النقد
@DriftAccessor(tables: [CashTransactions])
class CashTransactionDao extends DatabaseAccessor<AppDatabase>
    with _$CashTransactionDaoMixin {
  CashTransactionDao(super.db);

  Future<int> insertTransaction(CashTransactionsCompanion tx) =>
      into(cashTransactions).insert(tx);

  Future<void> insertTransactions(List<CashTransactionsCompanion> txs) async {
    await batch((b) => b.insertAll(cashTransactions, txs));
  }

  Future<List<CashTransaction>> getByDateRange(DateTime start, DateTime end) =>
      (select(cashTransactions)
            ..where((c) => c.createdAt.isBetweenValues(start, end))
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .get();

  Future<num> totalInbound() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM cash_transactions WHERE direction = ?',
      variables: [Variable<String>('IN')],
    ).getSingle();
    return result.read<double>('t');
  }

  Future<num> totalOutbound() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM cash_transactions WHERE direction = ?',
      variables: [Variable<String>('OUT')],
    ).getSingle();
    return result.read<double>('t');
  }

  /// الرصيد المتوقع = الإجمالي الداخل - الخارج
  Future<num> getExpectedBalance(num opening) async {
    final inbound = await totalInbound();
    final outbound = await totalOutbound();
    return opening + inbound - outbound;
  }

  Future<List<CashTransaction>> getRecent({int limit = 50}) =>
      (select(cashTransactions)
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)])
            ..limit(limit))
          .get();
}

/// DAO مدفوعات العملاء
@DriftAccessor(tables: [CustomerPayments])
class CustomerPaymentDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerPaymentDaoMixin {
  CustomerPaymentDao(super.db);

  Future<int> insertPayment(CustomerPaymentsCompanion payment) =>
      into(customerPayments).insert(payment);

  Future<List<CustomerPayment>> getByCustomer(int customerId) =>
      (select(customerPayments)
            ..where((p) => p.customerId.equals(customerId))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
          .get();

  Future<num> totalPaymentsByCustomer(int customerId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM customer_payments WHERE customer_id = ?',
      variables: [Variable(customerId)],
    ).getSingle();
    return result.read<double>('t');
  }

  Future<num> totalPaymentsInRange(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM customer_payments WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<double>('t');
  }
}

/// DAO مدفوعات الموردين
@DriftAccessor(tables: [SupplierPayments])
class SupplierPaymentDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierPaymentDaoMixin {
  SupplierPaymentDao(super.db);

  Future<int> insertPayment(SupplierPaymentsCompanion payment) =>
      into(supplierPayments).insert(payment);

  Future<List<SupplierPayment>> getBySupplier(int supplierId) =>
      (select(supplierPayments)
            ..where((p) => p.supplierId.equals(supplierId))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
          .get();

  Future<num> totalPaymentsBySupplier(int supplierId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM supplier_payments WHERE supplier_id = ?',
      variables: [Variable(supplierId)],
    ).getSingle();
    return result.read<double>('t');
  }

  Future<num> totalPaymentsInRange(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM supplier_payments WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<double>('t');
  }
}

/// DAO المصروفات
@DriftAccessor(tables: [Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Future<int> insertExpense(ExpensesCompanion expense) =>
      into(expenses).insert(expense);

  Future<List<Expense>> getByDateRange(DateTime start, DateTime end) =>
      (select(expenses)
            ..where((e) => e.createdAt.isBetweenValues(start, end))
            ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
          .get();

  Future<num> totalExpensesInRange(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM expenses WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<double>('t');
  }
}

/// DAO السحوبات
@DriftAccessor(tables: [Withdrawals])
class WithdrawalDao extends DatabaseAccessor<AppDatabase>
    with _$WithdrawalDaoMixin {
  WithdrawalDao(super.db);

  Future<int> insertWithdrawal(WithdrawalsCompanion withdrawal) =>
      into(withdrawals).insert(withdrawal);

  Future<List<Withdrawal>> getByDateRange(DateTime start, DateTime end) =>
      (select(withdrawals)
            ..where((w) => w.createdAt.isBetweenValues(start, end))
            ..orderBy([(w) => OrderingTerm.desc(w.createdAt)]))
          .get();

  Future<num> totalWithdrawalsInRange(DateTime start, DateTime end) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM withdrawals WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<double>('t');
  }
}

/// DAO المرتجعات
@DriftAccessor(tables: [Returns, ReturnItems])
class ReturnDao extends DatabaseAccessor<AppDatabase> with _$ReturnDaoMixin {
  ReturnDao(super.db);

  Future<int> insertReturn(ReturnsCompanion ret) => into(returns).insert(ret);

  Future<Return?> findById(int id) =>
      (select(returns)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<Return>> getByType(String returnType) =>
      (select(returns)
            ..where((r) => r.returnType.equals(returnType))
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .get();

  Future<void> insertItems(List<ReturnItemsCompanion> items) async {
    await batch((b) => b.insertAll(returnItems, items));
  }

  Future<List<ReturnItem>> getItems(int returnId) =>
      (select(returnItems)..where((ri) => ri.returnId.equals(returnId))).get();

  Future<int> getNextSequenceForToday(DateTime date, String prefix) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM returns WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<int>('c') + 1;
  }
}

/// DAO سجل التدقيق
@DriftAccessor(tables: [AuditLogs])
class AuditLogDao extends DatabaseAccessor<AppDatabase> with _$AuditLogDaoMixin {
  AuditLogDao(super.db);

  Future<int> insertLog(AuditLogsCompanion log) => into(auditLogs).insert(log);

  Future<List<AuditLog>> getRecent({int limit = 100}) =>
      (select(auditLogs)
            ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
            ..limit(limit))
          .get();

  Future<List<AuditLog>> getByUser(int userId) =>
      (select(auditLogs)
            ..where((a) => a.userId.equals(userId))
            ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
          .get();

  Future<List<AuditLog>> getByModule(String module) =>
      (select(auditLogs)
            ..where((a) => a.module.equals(module))
            ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
          .get();
}

/// DAO بيانات النسخ الاحتياطي
@DriftAccessor(tables: [BackupMetadata])
class BackupMetadataDao extends DatabaseAccessor<AppDatabase>
    with _$BackupMetadataDaoMixin {
  BackupMetadataDao(super.db);

  Future<int> insertMetadata(BackupMetadataCompanion meta) =>
      into(backupMetadata).insert(meta);

  Future<List<BackupMetadataData>> getAll() =>
      (select(backupMetadata)..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .get();

  Future<int> deleteMetadata(int id) =>
      (delete(backupMetadata)..where((b) => b.id.equals(id))).go();
}

/// DAO الإعدادات
@DriftAccessor(tables: [Settings])
class SettingDao extends DatabaseAccessor<AppDatabase> with _$SettingDaoMixin {
  SettingDao(super.db);

  Future<Setting?> getSettings() =>
      (select(settings)..limit(1)).getSingleOrNull();

  Future<int> updateSettings(SettingsCompanion s) =>
      (update(settings)..where((st) => st.id.equals(1))).write(s);
}

/// DAO الجرد
@DriftAccessor(tables: [Stocktakes, StocktakeItems])
class StocktakeDao extends DatabaseAccessor<AppDatabase> with _$StocktakeDaoMixin {
  StocktakeDao(super.db);

  Future<int> insertStocktake(StocktakesCompanion st) => into(stocktakes).insert(st);

  Future<void> insertItems(List<StocktakeItemsCompanion> items) async {
    await batch((b) => b.insertAll(stocktakeItems, items));
  }

  Future<List<Stocktake>> getAll() =>
      (select(stocktakes)..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Future<Stocktake?> findById(int id) =>
      (select(stocktakes)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<StocktakeItem>> getItems(int stocktakeId) =>
      (select(stocktakeItems)..where((si) => si.stocktakeId.equals(stocktakeId)))
          .get();

  Future<int> getNextSequenceForToday(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM stocktakes WHERE created_at >= ? AND created_at < ?',
      variables: [Variable(start), Variable(end)],
    ).getSingle();
    return result.read<int>('c') + 1;
  }
}
