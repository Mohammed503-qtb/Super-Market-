import 'package:flutter/material.dart';

import '../../application/service_locator.dart';
import '../../domain/services/accounting_service.dart';
import '../shared/widgets.dart';

/// لوحة التحكم - نظرة شاملة على نشاط المتجر
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardSummary? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await ServiceLocator.accountingService.getDashboardSummary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingIndicator(message: 'جارٍ تحميل البيانات...');
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    if (_summary == null) return const EmptyState(message: 'لا توجد بيانات');

    final s = _summary!;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // عنوان اليوم
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.today, color: AppColors.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ملخص اليوم',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          FormatUtils.formatDateAr(DateTime.now()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // بطاقات الإحصائيات الرئيسية
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: [
              StatCard(
                title: 'مبيعات اليوم',
                value: FormatUtils.formatMoneyAr(s.dailySales),
                icon: Icons.point_of_sale,
                color: AppColors.success,
              ),
              StatCard(
                title: 'مشتريات اليوم',
                value: FormatUtils.formatMoneyAr(s.dailyPurchases),
                icon: Icons.shopping_cart,
                color: AppColors.secondary,
              ),
              StatCard(
                title: 'مصروفات اليوم',
                value: FormatUtils.formatMoneyAr(s.dailyExpenses),
                icon: Icons.money_off,
                color: AppColors.error,
              ),
              StatCard(
                title: 'صافي الربح اليوم',
                value: FormatUtils.formatMoneyAr(s.netProfit),
                icon: Icons.trending_up,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // بطاقات الصندوق والديون
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: [
              StatCard(
                title: 'رصيد الصندوق المتوقع',
                value: FormatUtils.formatMoneyAr(s.expectedCash),
                icon: Icons.account_balance_wallet,
                color: AppColors.accent,
              ),
              StatCard(
                title: 'ديون العملاء',
                value: FormatUtils.formatMoneyAr(s.totalCustomerDebt),
                icon: Icons.people_alt,
                color: AppColors.warning,
              ),
              StatCard(
                title: 'ديون للموردين',
                value: FormatUtils.formatMoneyAr(s.totalSupplierDebt),
                icon: Icons.local_shipping,
                color: AppColors.info,
              ),
              StatCard(
                title: 'قيمة المخزون',
                value: FormatUtils.formatMoneyAr(s.inventoryValue),
                icon: Icons.warehouse,
                color: AppColors.success,
              ),
              StatCard(
                title: 'عدد الفواتير اليوم',
                value: '${s.invoiceCount}',
                icon: Icons.receipt,
                color: AppColors.primary,
              ),
              StatCard(
                title: 'أصناف ناقصة',
                value: '${s.lowStockCount}',
                icon: Icons.warning_amber,
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // إجماليات تاريخية
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'الإجماليات التاريخية',
                    icon: Icons.history,
                    action: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadData,
                    ),
                  ),
                  const Divider(height: 24),
                  InfoRow(
                    label: 'إجمالي المبيعات',
                    value: FormatUtils.formatMoneyAr(s.totalSalesAllTime),
                    icon: Icons.trending_up,
                    valueColor: AppColors.success,
                  ),
                  InfoRow(
                    label: 'إجمالي المشتريات',
                    value: FormatUtils.formatMoneyAr(s.totalPurchasesAllTime),
                    icon: Icons.trending_down,
                    valueColor: AppColors.secondary,
                  ),
                  InfoRow(
                    label: 'الرصيد الافتتاحي للصندوق',
                    value: FormatUtils.formatMoneyAr(s.openingBalance),
                    icon: Icons.account_balance,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // إجراءات سريعة
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'إجراءات سريعة', icon: Icons.flash_on),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.0,
                    children: [
                      ActionButton(
                        icon: Icons.point_of_sale,
                        label: 'كاشير',
                        onTap: () => _navigateTo(1),
                      ),
                      ActionButton(
                        icon: Icons.add_shopping_cart,
                        label: 'مشتريات',
                        color: AppColors.secondary,
                        onTap: () => _navigateTo(3),
                      ),
                      ActionButton(
                        icon: Icons.inventory,
                        label: 'منتج جديد',
                        color: AppColors.accent,
                        onTap: () => _navigateTo(4),
                      ),
                      ActionButton(
                        icon: Icons.person_add,
                        label: 'عميل',
                        color: AppColors.info,
                        onTap: () => _navigateTo(6),
                      ),
                      ActionButton(
                        icon: Icons.money_off,
                        label: 'مصروف',
                        color: AppColors.error,
                        onTap: () => _navigateTo(8),
                      ),
                      ActionButton(
                        icon: Icons.assessment,
                        label: 'تقارير',
                        color: AppColors.primary,
                        onTap: () => _navigateTo(9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateTo(int index) {
    // استخدام MainShell parent للتنقل - أبسط طريقة عبر GlobalKey
    // هنا نستخدم Navigator لفتح الشاشة مباشرة
    Scaffold.of(context).openDrawer();
  }
}
