import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'application/providers/auth_provider.dart';
import 'application/service_locator.dart';
import 'core/constants/app_constants.dart';
import 'core/constants/app_theme.dart';
import 'data/database/app_database.dart';
import 'domain/services/accounting_service.dart';
import 'domain/services/audit_service.dart';
import 'domain/services/backup_service.dart';
import 'domain/services/cashbox_service.dart';
import 'domain/services/customers_service.dart';
import 'domain/services/inventory_service.dart';
import 'domain/services/purchases_service.dart';
import 'domain/services/sales_service.dart';
import 'domain/services/suppliers_service.dart';
import 'features/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServiceLocator.initialize();
  runApp(const GroceryErpApp());
}

class GroceryErpApp extends StatefulWidget {
  const GroceryErpApp({super.key});

  @override
  State<GroceryErpApp> createState() => _GroceryErpAppState();
}

class _GroceryErpAppState extends State<GroceryErpApp> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = ServiceLocator.prefs;
    final isDark = prefs.getBool('is_dark_theme') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      _initialized = true;
    });
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
    ServiceLocator.prefs.setBool('is_dark_theme', _themeMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Container(color: Colors.white)),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(ServiceLocator.database, ServiceLocator.prefs),
        ),
        // الخدمات كـ ValueNotifier بسيط (Singleton)
        Provider<AppDatabase>.value(value: ServiceLocator.database),
        Provider<InventoryService>.value(value: ServiceLocator.inventoryService),
        Provider<SalesService>.value(value: ServiceLocator.salesService),
        Provider<PurchasesService>.value(value: ServiceLocator.purchasesService),
        Provider<CustomersService>.value(value: ServiceLocator.customersService),
        Provider<SuppliersService>.value(value: ServiceLocator.suppliersService),
        Provider<CashboxService>.value(value: ServiceLocator.cashboxService),
        Provider<AccountingService>.value(value: ServiceLocator.accountingService),
        Provider<AuditService>.value(value: ServiceLocator.auditService),
        Provider<BackupService>.value(value: ServiceLocator.backupService),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: _themeMode,
        // دعم العربية و RTL
        locale: const Locale('ar'),
        supportedLocales: const [
          Locale('ar'),
          Locale('en'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          );
        },
        home: AppShell(
          themeMode: _themeMode,
          onToggleTheme: _toggleTheme,
        ),
      ),
    );
  }
}
