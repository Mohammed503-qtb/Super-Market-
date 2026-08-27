import 'package:drift/drift.dart';

/// المستخدمون
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 3, max: 50)();
  TextColumn get displayName => text().withLength(min: 1, max: 100)();
  TextColumn get passwordHash => text()();
  IntColumn get roleId => integer().references(Roles, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
}

/// الأدوار
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get description => text().nullable()();
  BoolColumn get isSystemRole => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// الصلاحيات
class Permissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 3, max: 50)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get module => text().withLength(min: 1, max: 50)();
  TextColumn get description => text().nullable()();
}

/// ربط الصلاحيات بالأدوار
class RolePermissions extends Table {
  IntColumn get roleId => integer().references(Roles, #id, onDelete: KeyAction.cascade)();
  IntColumn get permissionId => integer().references(Permissions, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

/// التصنيفات
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// الوحدات
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get symbol => text().withLength(min: 1, max: 10)();
}

/// المنتجات
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get barcode => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get unitId => integer().nullable().references(Units, #id, onDelete: KeyAction.setNull)();
  RealColumn get purchasePrice => real().withDefault(const Constant(0))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  RealColumn get wholesalePrice => real().withDefault(const Constant(0))();
  RealColumn get minimumSellingPrice => real().withDefault(const Constant(0))();
  RealColumn get minimumStock => real().withDefault(const Constant(0))();
  RealColumn get currentStock => real().withDefault(const Constant(0))();
  RealColumn get averageCost => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// الموردون
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  RealColumn get currentBalance => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// العملاء
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  RealColumn get currentBalance => real().withDefault(const Constant(0))();
  RealColumn get creditLimit => real().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// المبيعات
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().withLength(min: 5, max: 50)();
  IntColumn get customerId => integer().nullable().references(Customers, #id, onDelete: KeyAction.setNull)();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  RealColumn get remainingAmount => real().withDefault(const Constant(0))();
  TextColumn get paymentType => text().withDefault(const Constant('CASH'))();
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// عناصر البيع
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
}

/// المشتريات
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().withLength(min: 5, max: 50)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id, onDelete: KeyAction.setNull)();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  RealColumn get remainingAmount => real().withDefault(const Constant(0))();
  TextColumn get paymentType => text().withDefault(const Constant('CASH'))();
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// عناصر الشراء
class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get total => real()();
}

/// حركات المخزون
class InventoryMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  TextColumn get movementType => text()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  RealColumn get quantity => real()();
  RealColumn get previousStock => real().withDefault(const Constant(0))();
  RealColumn get newStock => real().withDefault(const Constant(0))();
  RealColumn get unitCost => real().withDefault(const Constant(0))();
  IntColumn get userId => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// حركات النقد
class CashTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get transactionType => text()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  RealColumn get amount => real()();
  TextColumn get direction => text()(); // IN / OUT
  TextColumn get description => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// مدفوعات العملاء
class CustomerPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id, onDelete: KeyAction.restrict)();
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();
  IntColumn get referenceId => integer().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// مدفوعات الموردين
class SupplierPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();
  IntColumn get referenceId => integer().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// المصروفات
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text()();
  RealColumn get amount => real()();
  TextColumn get description => text().nullable()();
  TextColumn get paymentMethod => text().withDefault(const Constant('CASH'))();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// السحوبات
class Withdrawals extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  TextColumn get reason => text().nullable()();
  TextColumn get withdrawalType => text().withDefault(const Constant('OWNER'))();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// المرتجعات (بيع وشراء)
class Returns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().withLength(min: 5, max: 50)();
  TextColumn get returnType => text()(); // SALE_RETURN / PURCHASE_RETURN
  IntColumn get referenceInvoiceId => integer()(); // معرف فاتورة البيع أو الشراء الأصلية
  IntColumn get customerId => integer().nullable().references(Customers, #id, onDelete: KeyAction.setNull)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id, onDelete: KeyAction.setNull)();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get cashReturn => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// عناصر المرتجع
class ReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(Returns, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
}

/// سجل التدقيق
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  TextColumn get action => text()();
  TextColumn get module => text().nullable()();
  TextColumn get entityType => text().nullable()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// بيانات النسخ الاحتياطي
class BackupMetadata extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fileName => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get databaseVersion => integer().withDefault(const Constant(1))();
  IntColumn get size => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
}

/// الإعدادات
class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get storeName => text().withDefault(const Constant('بقالتي'))();
  TextColumn get storeAddress => text().nullable()();
  TextColumn get storePhone => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('ر.ي'))();
  TextColumn get logoPath => text().nullable()();
  BoolColumn get preventNegativeStock => boolean().withDefault(const Constant(true))();
  BoolColumn get allowOverpayment => boolean().withDefault(const Constant(false))();
  RealColumn get cashboxOpeningBalance => real().withDefault(const Constant(0))();
  BoolColumn get taxEnabled => boolean().withDefault(const Constant(false))();
  RealColumn get taxRate => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// الجرد
class Stocktakes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get stocktakeNumber => text().withLength(min: 5, max: 50)();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.restrict)();
  RealColumn get totalDifferenceValue => real().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// عناصر الجرد
class StocktakeItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get stocktakeId => integer().references(Stocktakes, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.restrict)();
  RealColumn get systemQuantity => real()();
  RealColumn get actualQuantity => real()();
  RealColumn get difference => real()();
  RealColumn get unitCost => real().withDefault(const Constant(0))();
  RealColumn get differenceValue => real().withDefault(const Constant(0))();
  TextColumn get reason => text().nullable()();
}
