import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../dashboard/dashboard_screen.dart';
import '../shared/widgets.dart';
import '../sales/pos_screen.dart';
import '../sales/sales_list_screen.dart';
import '../purchases/purchases_list_screen.dart';
import '../inventory/products_screen.dart';
import '../inventory/inventory_screen.dart';
import '../customers/customers_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../cashbox/cashbox_screen.dart';
import '../reports/reports_screen.dart';
import '../users/users_screen.dart';
import '../settings/settings_screen.dart';
import '../backup/backup_screen.dart';

/// الهيكل الرئيسي للتطبيق بعد تسجيل الدخول
class MainShell extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const MainShell({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  final _screens = <Widget>[
    const DashboardScreen(),
    const PosScreen(),
    const SalesListScreen(),
    const PurchasesListScreen(),
    const ProductsScreen(),
    const InventoryScreen(),
    const CustomersScreen(),
    const SuppliersScreen(),
    const CashboxScreen(),
    const ReportsScreen(),
    const UsersScreen(),
    const SettingsScreen(),
    const BackupScreen(),
  ];

  final _titles = <String>[
    'لوحة التحكم',
    'الكاشير',
    'المبيعات',
    'المشتريات',
    'المنتجات',
    'المخزون',
    'العملاء',
    'الموردون',
    'الصندوق',
    'التقارير',
    'المستخدمون',
    'الإعدادات',
    'النسخ الاحتياطي',
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: widget.onToggleTheme,
            tooltip: 'تبديل الوضع',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) async {
              if (value == 'logout') {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'تسجيل الخروج',
                  message: 'هل أنت متأكد من تسجيل الخروج؟',
                );
                if (confirmed == true) {
                  await auth.logout();
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        auth.currentDisplayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('تسجيل الخروج'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.storefront, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    AppConstants.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'مرحباً، ${auth.currentDisplayName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(Icons.dashboard_outlined, 'لوحة التحكم', 0),
            _buildDrawerItem(Icons.point_of_sale, 'الكاشير', 1),
            _buildDrawerItem(Icons.receipt_long_outlined, 'المبيعات', 2),
            _buildDrawerItem(Icons.shopping_cart_outlined, 'المشتريات', 3),
            _buildDrawerItem(Icons.inventory_2_outlined, 'المنتجات', 4),
            _buildDrawerItem(Icons.warehouse_outlined, 'المخزون', 5),
            _buildDrawerItem(Icons.people_alt_outlined, 'العملاء', 6),
            _buildDrawerItem(Icons.local_shipping_outlined, 'الموردون', 7),
            _buildDrawerItem(Icons.account_balance_wallet_outlined, 'الصندوق', 8),
            _buildDrawerItem(Icons.assessment_outlined, 'التقارير', 9),
            _buildDrawerItem(Icons.manage_accounts_outlined, 'المستخدمون', 10),
            _buildDrawerItem(Icons.settings_outlined, 'الإعدادات', 11),
            _buildDrawerItem(Icons.backup_outlined, 'النسخ الاحتياطي', 12),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('تسجيل الخروج',
                  style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'تسجيل الخروج',
                  message: 'هل أنت متأكد من تسجيل الخروج؟',
                );
                if (confirmed == true) {
                  await auth.logout();
                }
              },
            ),
          ],
        ),
      ),
      body: _screens[_selectedIndex],
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.primary : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primary : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }
}
