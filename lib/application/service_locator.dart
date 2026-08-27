import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/app_database.dart';
import '../domain/services/inventory_service.dart';
import '../domain/services/sales_service.dart';
import '../domain/services/purchases_service.dart';
import '../domain/services/customers_service.dart';
import '../domain/services/suppliers_service.dart';
import '../domain/services/cashbox_service.dart';
import '../domain/services/accounting_service.dart';
import '../domain/services/audit_service.dart';
import '../domain/services/backup_service.dart';

/// حاوية الخدمات (Service Locator / Dependency Injection)
/// تُهيّأ مرة واحدة عند بدء التطبيق
class ServiceLocator {
  static AppDatabase? _database;
  static SharedPreferences? _prefs;
  static AuditService? _auditService;
  static InventoryService? _inventoryService;
  static SalesService? _salesService;
  static PurchasesService? _purchasesService;
  static CustomersService? _customersService;
  static SuppliersService? _suppliersService;
  static CashboxService? _cashboxService;
  static AccountingService? _accountingService;
  static BackupService? _backupService;

  static Future<void> initialize() async {
    _database = AppDatabase();
    _prefs = await SharedPreferences.getInstance();

    _auditService = AuditService(_database!);
    _inventoryService = InventoryService(_database!);
    _salesService = SalesService(_database!, _inventoryService!, _auditService!);
    _purchasesService = PurchasesService(_database!, _inventoryService!, _auditService!);
    _customersService = CustomersService(_database!, _auditService!);
    _suppliersService = SuppliersService(_database!, _auditService!);
    _cashboxService = CashboxService(_database!, _auditService!);
    _accountingService = AccountingService(_database!, _inventoryService!);
    _backupService = BackupService(_database!, _auditService!);
  }

  static AppDatabase get database => _database!;
  static SharedPreferences get prefs => _prefs!;
  static AuditService get auditService => _auditService!;
  static InventoryService get inventoryService => _inventoryService!;
  static SalesService get salesService => _salesService!;
  static PurchasesService get purchasesService => _purchasesService!;
  static CustomersService get customersService => _customersService!;
  static SuppliersService get suppliersService => _suppliersService!;
  static CashboxService get cashboxService => _cashboxService!;
  static AccountingService get accountingService => _accountingService!;
  static BackupService get backupService => _backupService!;

  static Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
