import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة المخزون
/// ----------
/// ثلاثة تبويبات:
/// 1) حركات المخزون — قائمة كرونولوجية بكل حركات المخزون مع فلتر
///    بالفترة ومنتج محدد. يعرض كل صف: التاريخ، اسم المنتج، نوع الحركة
///    (بتسمية عربية ملوّنة)، الكمية (+/-)، الرصيد السابق، الرصيد الجديد، المستخدم.
/// 2) تسوية المخزون — زر يفتح حوار تسوية: اختيار المنتج، إدخال الكمية
///    الفعلية، السبب -> يستدعي InventoryService.adjustStock.
/// 3) الجرد — قائمة بعمليات الجرد السابقة + زر لبدء جرد جديد يحمل كل
///    المنتجات ويدخل المستخدم الكميات الفعلية ثم يحفظ الجرد ويطبّق التسويات.
/// شريط إحصائيات أعلى الشاشة: قيمة المخزون، إجمالي الأصناف، مخزون منخفض، نفذ.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ===== الإحصائيات =====
  num _inventoryValue = 0;
  int _totalProducts = 0;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;

  // ===== بيانات حركات المخزون =====
  final List<InventoryMovement> _movements = [];
  final Map<int, Product> _productsMap = {};
  final Map<int, User> _usersMap = {};
  final List<Product> _allProducts = [];
  Product? _movementsProductFilter;
  DateTime? _movementsStartDate;
  DateTime? _movementsEndDate;
  bool _isLoadingMovements = true;

  // ===== بيانات الجرد =====
  final List<Stocktake> _stocktakes = [];
  bool _isLoadingStocktakes = true;

  // ===== الصلاحيات =====
  bool _canAdjust = false;
  bool _canStocktake = false;
  bool _canViewCost = false;
  int? _currentUserId;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final auth = context.read<AuthProvider>();
    _canAdjust = auth.hasPermission(PermissionCodes.inventoryAdjust);
    _canStocktake = auth.hasPermission(PermissionCodes.inventoryStocktake);
    _canViewCost = auth.hasPermission(PermissionCodes.reportsProfit);
    _currentUserId = auth.currentUser?.id;
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadStats(),
      _loadProductsAndUsers(),
      _loadMovements(),
      _loadStocktakes(),
    ]);
  }

  // =====================
  // تحميل البيانات
  // =====================

  Future<void> _loadStats() async {
    try {
      final db = ServiceLocator.database;
      final products = await db.productDao.getAll();
      final inventoryValue =
          await ServiceLocator.inventoryService.calculateInventoryValue();
      final lowStock = products
          .where((p) =>
              p.currentStock > 0 &&
              p.minimumStock > 0 &&
              p.currentStock <= p.minimumStock)
          .length;
      final outOfStock = products.where((p) => p.currentStock <= 0).length;
      if (!mounted) return;
      setState(() {
        _totalProducts = products.length;
        _inventoryValue = inventoryValue;
        _lowStockCount = lowStock;
        _outOfStockCount = outOfStock;
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الإحصائيات: $e');
    }
  }

  Future<void> _loadProductsAndUsers() async {
    try {
      final db = ServiceLocator.database;
      final products = await db.productDao.getAll();
      final users = await db.userDao.getAll();
      _allProducts
        ..clear()
        ..addAll(products);
      _productsMap
        ..clear()
        ..addEntries(products.map((p) => MapEntry(p.id, p)));
      _usersMap
        ..clear()
        ..addEntries(users.map((u) => MapEntry(u.id, u)));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل البيانات: $e');
    }
  }

  Future<void> _loadMovements() async {
    setState(() => _isLoadingMovements = true);
    try {
      final dao = ServiceLocator.database.inventoryMovementDao;
      // نتعامل مع الفلتر: إذا لم يُحدد طرف نأخذ مدى واسع جداً.
      final start = _movementsStartDate ?? DateTime(2000);
      final end =
          _movementsEndDate?.add(const Duration(days: 1)) ?? DateTime(2100);
      var result = await dao.getByDateRange(start, end);
      if (_movementsProductFilter != null) {
        result = result
            .where((m) => m.productId == _movementsProductFilter!.id)
            .toList();
      }
      _movements
        ..clear()
        ..addAll(result);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الحركات: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMovements = false);
    }
  }

  Future<void> _loadStocktakes() async {
    setState(() => _isLoadingStocktakes = true);
    try {
      final list = await ServiceLocator.database.stocktakeDao.getAll();
      _stocktakes
        ..clear()
        ..addAll(list);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الجرد: $e');
    } finally {
      if (mounted) setState(() => _isLoadingStocktakes = false);
    }
  }

  // =====================
  // تسمية الحركات وألوانها
  // =====================

  static const Map<String, (Color, String)> _movementLabels = {
    MovementTypes.purchaseIn: (AppColors.success, 'وارد شراء'),
    MovementTypes.saleOut: (AppColors.secondary, 'صادر بيع'),
    MovementTypes.saleReturnIn: (AppColors.success, 'مرتجع بيع'),
    MovementTypes.purchaseReturnOut: (AppColors.warning, 'مرتجع شراء'),
    MovementTypes.adjustmentIn: (AppColors.info, 'تسوية موجبة'),
    MovementTypes.adjustmentOut: (AppColors.warning, 'تسوية سالبة'),
    MovementTypes.transferIn: (AppColors.info, 'تحويل وارد'),
    MovementTypes.transferOut: (AppColors.warning, 'تحويل صادر'),
    MovementTypes.openingStock: (AppColors.accent, 'رصيد افتتاحي'),
  };

  (Color, String) _movementInfo(String type) {
    return _movementLabels[type] ?? (AppColors.textSecondaryLight, type);
  }

  bool _isInbound(String type) {
    return type == MovementTypes.purchaseIn ||
        type == MovementTypes.saleReturnIn ||
        type == MovementTypes.adjustmentIn ||
        type == MovementTypes.transferIn ||
        type == MovementTypes.openingStock;
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsRow(),
          Material(
            color: Theme.of(context).cardColor,
            elevation: 0.5,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.swap_vert), text: 'حركات المخزون'),
                Tab(icon: Icon(Icons.tune), text: 'تسوية المخزون'),
                Tab(icon: Icon(Icons.fact_check_outlined), text: 'الجرد'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMovementsTab(),
                _buildAdjustmentTab(),
                _buildStocktakeTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        children: [
          _miniStat(
            'قيمة المخزون',
            _canViewCost ? FormatUtils.formatMoneyAr(_inventoryValue) : '—',
            Icons.account_balance_wallet_outlined,
            AppColors.accent,
          ),
          _miniStat(
            'إجمالي الأصناف',
            '$_totalProducts',
            Icons.inventory_2_outlined,
            AppColors.primary,
          ),
          _miniStat(
            'مخزون منخفض',
            '$_lowStockCount',
            Icons.warning_amber_outlined,
            AppColors.secondary,
          ),
          _miniStat(
            'نفذ المخزون',
            '$_outOfStockCount',
            Icons.error_outline,
            AppColors.error,
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, String value, IconData icon, Color color) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(left: 8),
      child: StatCard(
        title: title,
        value: value,
        icon: icon,
        color: color,
      ),
    );
  }

  // =====================
  // تبويب حركات المخزون
  // =====================

  Widget _buildMovementsTab() {
    return Column(
      children: [
        _buildMovementsFilter(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadMovements,
            child: _isLoadingMovements && _movements.isEmpty
                ? const LoadingIndicator(message: 'جارٍ تحميل الحركات...')
                : _movements.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.swap_vert,
                            message: 'لا توجد حركات مخزون مطابقة',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                        itemCount: _movements.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final m = _movements[i];
                          final product = _productsMap[m.productId];
                          final user =
                              m.userId != null ? _usersMap[m.userId!] : null;
                          return _MovementRow(
                            movement: m,
                            productName: product?.name ?? '—',
                            userDisplayName: user?.displayName,
                            movementInfo: _movementInfo(m.movementType),
                            isInbound: _isInbound(m.movementType),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildMovementsFilter() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButtonFormField<Product?>(
              value: _movementsProductFilter,
              decoration: const InputDecoration(
                labelText: 'تصفية حسب المنتج',
                prefixIcon: Icon(Icons.filter_alt_outlined, size: 20),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<Product?>(
                  value: null,
                  child: Text('كل المنتجات'),
                ),
                ..._allProducts.map(
                  (p) => DropdownMenuItem<Product?>(
                    value: p,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _movementsProductFilter = v);
                _loadMovements();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _dateButton(
                    label: _movementsStartDate != null
                        ? FormatUtils.formatDate(_movementsStartDate!)
                        : 'من تاريخ',
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dateButton(
                    label: _movementsEndDate != null
                        ? FormatUtils.formatDate(_movementsEndDate!)
                        : 'إلى تاريخ',
                    onTap: () => _pickDate(false),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'مسح الفلتر',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _movementsStartDate = null;
                      _movementsEndDate = null;
                      _movementsProductFilter = null;
                    });
                    _loadMovements();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial =
        isStart ? (_movementsStartDate ?? now) : (_movementsEndDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _movementsStartDate = picked;
      } else {
        _movementsEndDate = picked;
      }
    });
    _loadMovements();
  }

  Widget _dateButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // تبويب تسوية المخزون
  // =====================

  Widget _buildAdjustmentTab() {
    if (!_canAdjust) {
      return const EmptyState(
        icon: Icons.lock_outline,
        message: 'ليس لديك صلاحية تنفيذ تسويات المخزون',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: AppColors.info.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.info),
                      const SizedBox(width: 8),
                      Text(
                        'تسوية المخزون',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'استخدم هذه الأداة لتعديل الكمية الفعلية لأي صنف. '
                    'سيتم تسجيل الفرق (زيادة أو نقص) كحركة تسوية في سجل المخزون. '
                    'استخدمها عند وجود فروقات ناتجة عن تلف أو فقد أو خطأ في الإدخال.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openAdjustmentDialog,
            icon: const Icon(Icons.tune),
            label: const Text('بدء تسوية جديدة'),
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'آخر التسويات',
            icon: Icons.history,
          ),
          const SizedBox(height: 8),
          _recentAdjustments(),
        ],
      ),
    );
  }

  Widget _recentAdjustments() {
    final recent = _movements
        .where((m) =>
            m.movementType == MovementTypes.adjustmentIn ||
            m.movementType == MovementTypes.adjustmentOut)
        .take(20)
        .toList();
    if (recent.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: EmptyState(
            icon: Icons.history,
            message: 'لا توجد تسويات سابقة',
          ),
        ),
      );
    }
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: recent.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final m = recent[i];
          final product = _productsMap[m.productId];
          final user = m.userId != null ? _usersMap[m.userId!] : null;
          return _MovementRow(
            movement: m,
            productName: product?.name ?? '—',
            userDisplayName: user?.displayName,
            movementInfo: _movementInfo(m.movementType),
            isInbound: _isInbound(m.movementType),
          );
        },
      ),
    );
  }

  Future<void> _openAdjustmentDialog() async {
    if (_allProducts.isEmpty) {
      await _loadProductsAndUsers();
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdjustmentDialog(
        products: _allProducts,
        userId: _currentUserId,
      ),
    );
    if (result == true) {
      await Future.wait([
        _loadStats(),
        _loadMovements(),
      ]);
    }
  }

  // =====================
  // تبويب الجرد
  // =====================

  Widget _buildStocktakeTab() {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadStocktakes,
          child: _isLoadingStocktakes && _stocktakes.isEmpty
              ? const LoadingIndicator(message: 'جارٍ تحميل عمليات الجرد...')
              : _stocktakes.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        EmptyState(
                          icon: Icons.fact_check_outlined,
                          message: 'لا توجد عمليات جرد بعد',
                          actionLabel: _canStocktake ? 'بدء جرد جديد' : null,
                          onAction: _canStocktake ? _openStocktakeDialog : null,
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                      itemCount: _stocktakes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final st = _stocktakes[i];
                        final user = _usersMap[st.userId];
                        return _StocktakeCard(
                          stocktake: st,
                          userDisplayName: user?.displayName ?? '—',
                          onTap: () => _viewStocktakeDetails(st),
                        );
                      },
                    ),
        ),
        if (_canStocktake)
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _openStocktakeDialog,
              icon: const Icon(Icons.add),
              label: const Text('بدء جرد جديد'),
            ),
          ),
      ],
    );
  }

  Future<void> _openStocktakeDialog() async {
    if (_allProducts.isEmpty) {
      await _loadProductsAndUsers();
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StocktakeDialog(
        products: _allProducts,
        userId: _currentUserId,
        canViewCost: _canViewCost,
      ),
    );
    if (result == true) {
      await Future.wait([
        _loadStats(),
        _loadStocktakes(),
        _loadMovements(),
      ]);
    }
  }

  Future<void> _viewStocktakeDetails(Stocktake st) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StocktakeDetailDialog(stocktake: st),
    );
  }
}

// =====================================================
// صف حركة المخزون
// =====================================================
class _MovementRow extends StatelessWidget {
  final InventoryMovement movement;
  final String productName;
  final String? userDisplayName;
  final (Color, String) movementInfo;
  final bool isInbound;

  const _MovementRow({
    required this.movement,
    required this.productName,
    required this.userDisplayName,
    required this.movementInfo,
    required this.isInbound,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = movementInfo;
    final qtyText = isInbound
        ? '+${FormatUtils.formatQuantity(movement.quantity)}'
        : '-${FormatUtils.formatQuantity(movement.quantity)}';
    final qtyColor = isInbound ? AppColors.success : AppColors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        productName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (movement.reason != null && movement.reason!.isNotEmpty)
                  Text(
                    movement.reason!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _meta(FormatUtils.formatDateTime(movement.createdAt),
                        Icons.access_time),
                    if (userDisplayName != null)
                      _meta(userDisplayName!, Icons.person_outline),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                qtyText,
                style: TextStyle(
                  color: qtyColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${FormatUtils.formatQuantity(movement.previousStock)} '
                '← ${FormatUtils.formatQuantity(movement.newStock)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondaryLight),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}

// =====================================================
// بطاقة الجرد (في تبويب الجرد)
// =====================================================
class _StocktakeCard extends StatelessWidget {
  final Stocktake stocktake;
  final String userDisplayName;
  final VoidCallback onTap;

  const _StocktakeCard({
    required this.stocktake,
    required this.userDisplayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffColor = stocktake.totalDifferenceValue < 0
        ? AppColors.error
        : stocktake.totalDifferenceValue > 0
            ? AppColors.success
            : AppColors.textSecondaryLight;
    final diffSign = stocktake.totalDifferenceValue < 0 ? '-' : '';
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fact_check,
                    color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stocktake.stocktakeNumber,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      children: [
                        _meta(FormatUtils.formatDateTime(stocktake.createdAt),
                            Icons.access_time),
                        _meta(userDisplayName, Icons.person_outline),
                      ],
                    ),
                    if (stocktake.notes != null && stocktake.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          stocktake.notes!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$diffSign${FormatUtils.formatMoneyAr(stocktake.totalDifferenceValue.abs())}',
                    style: TextStyle(
                      color: diffColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const StatusBadge(status: 'COMPLETED'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondaryLight),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}

// =====================================================
// حوار تسوية المخزون
// =====================================================
class _AdjustmentDialog extends StatefulWidget {
  final List<Product> products;
  final int? userId;

  const _AdjustmentDialog({
    required this.products,
    required this.userId,
  });

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualQuantityController = TextEditingController();
  final _reasonController = TextEditingController();
  Product? _selectedProduct;
  bool _saving = false;

  @override
  void dispose() {
    _actualQuantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double? get _actualQty => double.tryParse(_actualQuantityController.text);
  double get _currentStock => _selectedProduct?.currentStock ?? 0;
  double get _diff {
    final actual = _actualQty;
    if (actual == null || _selectedProduct == null) return 0;
    return actual - _currentStock;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      showErrorSnackBar(context, 'اختر المنتج أولاً');
      return;
    }
    if (widget.userId == null) {
      showErrorSnackBar(context, 'لا يوجد مستخدم حالي');
      return;
    }
    final qty = _actualQty;
    if (qty == null) {
      showErrorSnackBar(context, 'أدخل كمية صحيحة');
      return;
    }

    setState(() => _saving = true);
    try {
      final reason = _reasonController.text.trim();
      await ServiceLocator.inventoryService.adjustStock(
        productId: _selectedProduct!.id,
        actualQuantity: qty,
        userId: widget.userId!,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      showSuccessSnackBar(context, 'تم تنفيذ التسوية بنجاح');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تنفيذ التسوية: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tune, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('تسوية مخزون'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<Product>(
                  value: _selectedProduct,
                  decoration: const InputDecoration(
                    labelText: 'المنتج *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  items: widget.products
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child:
                                Text(p.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedProduct = v;
                    _actualQuantityController.clear();
                  }),
                  validator: (v) => v == null ? 'اختر المنتج' : null,
                ),
                const SizedBox(height: 12),
                if (_selectedProduct != null) ...[
                  Card(
                    color: AppColors.info.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 18, color: AppColors.info),
                              const SizedBox(width: 6),
                              Text(
                                'المخزون الحالي: ${FormatUtils.formatQuantity(_currentStock)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (_actualQty != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _diff == 0
                                  ? 'الفرق: لا يوجد'
                                  : 'الفرق: ${FormatUtils.formatQuantity(_diff.abs())} '
                                      '(${_diff > 0 ? "زيادة" : "نقص"})',
                              style: TextStyle(
                                color: _diff > 0
                                    ? AppColors.success
                                    : _diff < 0
                                        ? AppColors.error
                                        : AppColors.textSecondaryLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _actualQuantityController,
                  decoration: const InputDecoration(
                    labelText: 'الكمية الفعلية *',
                    prefixIcon: Icon(Icons.scale),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null) return 'أدخل كمية صحيحة';
                    if (n < 0) return 'الكمية لا يمكن أن تكون سالبة';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'سبب التسوية',
                    prefixIcon: Icon(Icons.note_outlined),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check),
          label: const Text('تنفيذ التسوية'),
        ),
      ],
    );
  }
}

// =====================================================
// حوار الجرد الجديد
// =====================================================
class _StocktakeDialog extends StatefulWidget {
  final List<Product> products;
  final int? userId;
  final bool canViewCost;

  const _StocktakeDialog({
    required this.products,
    required this.userId,
    required this.canViewCost,
  });

  @override
  State<_StocktakeDialog> createState() => _StocktakeDialogState();
}

class _StocktakeDialogState extends State<_StocktakeDialog> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<int, TextEditingController> _actualQtyControllers = {};
  bool _saving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    for (final p in widget.products) {
      _actualQtyControllers[p.id] =
          TextEditingController(text: p.currentStock.toString());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    for (final c in _actualQtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Product> get _filteredProducts {
    if (_search.isEmpty) return widget.products;
    final q = _search.toLowerCase();
    return widget.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.barcode?.toLowerCase().contains(q) ?? false) ||
            (p.sku?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  int get _diffCount {
    var count = 0;
    for (final p in widget.products) {
      final sys = p.currentStock;
      final actual =
          double.tryParse(_actualQtyControllers[p.id]?.text ?? '') ?? sys;
      if ((actual - sys) != 0) count++;
    }
    return count;
  }

  num get _totalDiffValue {
    num total = 0;
    for (final p in widget.products) {
      final sys = p.currentStock;
      final actual =
          double.tryParse(_actualQtyControllers[p.id]?.text ?? '') ?? sys;
      final diff = actual - sys;
      total += diff * p.averageCost;
    }
    return total;
  }

  Future<void> _submit() async {
    if (widget.userId == null) {
      showErrorSnackBar(context, 'لا يوجد مستخدم حالي');
      return;
    }
    final userId = widget.userId!;
    final db = ServiceLocator.database;
    final now = DateTime.now();

    final diffCount = _diffCount;
    final totalDiffValue = _totalDiffValue;

    final confirmed = await showConfirmDialog(
      context,
      title: 'تأكيد الجرد',
      message: diffCount == 0
          ? 'لا توجد فروقات لمعالجتها. هل تريد حفظ الجرد بدون أي تسوية؟'
          : 'سيتم حفظ الجرد وتطبيق $diffCount تسوية على المخزون.\n'
              'إجمالي فرق القيمة: ${FormatUtils.formatMoneyAr(totalDiffValue.abs())}'
              '${totalDiffValue < 0 ? " (نقص)" : totalDiffValue > 0 ? " (زيادة)" : ""}.\n'
              'هل تريد المتابعة؟',
      confirmText: 'متابعة',
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      await db.runInTransactionSafe(() async {
        // 1) توليد رقم الجرد
        final seq = await db.stocktakeDao.getNextSequenceForToday(now);
        final stocktakeNumber =
            CommonUtils.generateInvoiceNumber('STK', now, seq);

        // 2) إدخال سجل الجرد
        final stocktakeId = await db.stocktakeDao.insertStocktake(
          StocktakesCompanion.insert(
            stocktakeNumber: stocktakeNumber,
            userId: userId,
            totalDifferenceValue: Value(totalDiffValue.toDouble()),
            status: const Value('COMPLETED'),
            notes: _notesController.text.trim().isEmpty
                ? const Value.absent()
                : Value<String?>(_notesController.text.trim()),
          ),
        );

        // 3) إدخال عناصر الجرد
        final items = <StocktakeItemsCompanion>[];
        for (final p in widget.products) {
          final sys = p.currentStock;
          final actualStr = _actualQtyControllers[p.id]?.text ?? '';
          final actual = double.tryParse(actualStr) ?? sys;
          final diff = actual - sys;
          final diffValue = diff * p.averageCost;
          items.add(StocktakeItemsCompanion.insert(
            stocktakeId: stocktakeId,
            productId: p.id,
            systemQuantity: sys,
            actualQuantity: actual,
            difference: diff,
            unitCost: Value(p.averageCost),
            differenceValue: Value(diffValue),
            reason: const Value.absent(),
          ));
        }
        await db.stocktakeDao.insertItems(items);

        // 4) تطبيق التسويات على المخزون عبر InventoryService
        for (final p in widget.products) {
          final sys = p.currentStock;
          final actualStr = _actualQtyControllers[p.id]?.text ?? '';
          final actual = double.tryParse(actualStr) ?? sys;
          if (actual == sys) continue;
          await ServiceLocator.inventoryService.adjustStock(
            productId: p.id,
            actualQuantity: actual,
            userId: userId,
            reason: 'تسوية جرد - $stocktakeNumber',
          );
        }
      });
      if (!mounted) return;
      showSuccessSnackBar(context, 'تم حفظ الجرد بنجاح');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل حفظ الجرد: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 900,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('جرد مخزون جديد'),
            actions: [
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                child:
                    const Text('إلغاء', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          body: Column(
            children: [
              // بطاقة الملخص
              Container(
                width: double.infinity,
                color: AppColors.primary.withValues(alpha: 0.05),
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _summaryChip(
                      'إجمالي الأصناف',
                      '${widget.products.length}',
                      Icons.inventory_2_outlined,
                      AppColors.primary,
                    ),
                    _summaryChip(
                      'أصناف بفروقات',
                      '$_diffCount',
                      Icons.compare_arrows,
                      _diffCount > 0 ? AppColors.warning : AppColors.success,
                    ),
                    if (widget.canViewCost)
                      _summaryChip(
                        'إجمالي فرق القيمة',
                        '${FormatUtils.formatMoneyAr(_totalDiffValue.abs())}'
                            '${_totalDiffValue < 0 ? " (نقص)" : _totalDiffValue > 0 ? " (زيادة)" : ""}',
                        Icons.account_balance_wallet_outlined,
                        _totalDiffValue < 0
                            ? AppColors.error
                            : _totalDiffValue > 0
                                ? AppColors.success
                                : AppColors.textSecondaryLight,
                      ),
                  ],
                ),
              ),
              // البحث
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: SearchField(
                  controller: _searchController,
                  hintText: 'ابحث باسم المنتج أو الباركود أو SKU...',
                  onChanged: () => setState(() {
                    _search = _searchController.text;
                  }),
                  onClear: () => setState(() {
                    _search = '';
                  }),
                ),
              ),
              // ملاحظات
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات الجرد (اختياري)',
                    prefixIcon: Icon(Icons.note_outlined),
                    isDense: true,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 4),
              // رأس الجدول
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: theme.dividerColor.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Expanded(
                        flex: 4,
                        child: Text('المنتج',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('كمية النظام',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('الكمية الفعلية',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('الفرق',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              // قائمة المنتجات
              Expanded(
                child: _filteredProducts.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        message: 'لا توجد منتجات مطابقة',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, i) {
                          final p = _filteredProducts[i];
                          final sys = p.currentStock;
                          final actualStr =
                              _actualQtyControllers[p.id]?.text ?? '';
                          final actual = double.tryParse(actualStr) ?? sys;
                          final diff = actual - sys;
                          return _StocktakeProductRow(
                            product: p,
                            systemQty: sys,
                            controller: _actualQtyControllers[p.id]!,
                            diff: diff,
                            onChanged: () => setState(() {}),
                          );
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text('حفظ وتطبيق التسويات'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(color: color, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StocktakeProductRow extends StatelessWidget {
  final Product product;
  final double systemQty;
  final TextEditingController controller;
  final double diff;
  final VoidCallback onChanged;

  const _StocktakeProductRow({
    required this.product,
    required this.systemQty,
    required this.controller,
    required this.diff,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffColor = diff > 0
        ? AppColors.success
        : diff < 0
            ? AppColors.error
            : AppColors.textSecondaryLight;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.barcode != null && product.barcode!.isNotEmpty)
                    Text(
                      product.barcode!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondaryLight),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                FormatUtils.formatQuantity(systemQty),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                onChanged: (_) => onChanged(),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                diff == 0
                    ? '—'
                    : '${diff > 0 ? "+" : ""}${FormatUtils.formatQuantity(diff)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: diffColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// حوار تفاصيل الجرد
// =====================================================
class _StocktakeDetailDialog extends StatefulWidget {
  final Stocktake stocktake;

  const _StocktakeDetailDialog({required this.stocktake});

  @override
  State<_StocktakeDetailDialog> createState() => _StocktakeDetailDialogState();
}

class _StocktakeDetailDialogState extends State<_StocktakeDetailDialog> {
  final List<StocktakeItem> _items = [];
  final Map<int, Product> _productsMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final db = ServiceLocator.database;
      final items = await db.stocktakeDao.getItems(widget.stocktake.id);
      final products = await db.productDao.getAll();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _productsMap
          ..clear()
          ..addEntries(products.map((p) => MapEntry(p.id, p)));
        _loading = false;
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل التفاصيل: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 900,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Scaffold(
          appBar: AppBar(
            title: Text('تفاصيل الجرد: ${widget.stocktake.stocktakeNumber}'),
            actions: [
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: _loading
              ? const LoadingIndicator(message: 'جارٍ تحميل التفاصيل...')
              : Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InfoRow(
                              label: 'التاريخ',
                              value: FormatUtils.formatDateTime(
                                  widget.stocktake.createdAt),
                              icon: Icons.access_time,
                            ),
                            InfoRow(
                              label: 'الحالة',
                              value: 'مكتمل',
                              icon: Icons.check_circle_outline,
                              valueColor: AppColors.success,
                            ),
                            InfoRow(
                              label: 'إجمالي فرق القيمة',
                              value: FormatUtils.formatMoneyAr(
                                  widget.stocktake.totalDifferenceValue),
                              icon: Icons.account_balance_wallet_outlined,
                              valueColor: widget
                                          .stocktake.totalDifferenceValue <
                                      0
                                  ? AppColors.error
                                  : widget.stocktake.totalDifferenceValue > 0
                                      ? AppColors.success
                                      : null,
                            ),
                            if (widget.stocktake.notes != null &&
                                widget.stocktake.notes!.isNotEmpty)
                              InfoRow(
                                label: 'ملاحظات',
                                value: widget.stocktake.notes!,
                                icon: Icons.note_outlined,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _items.isEmpty
                          ? const EmptyState(
                              icon: Icons.fact_check_outlined,
                              message: 'لا توجد عناصر في هذا الجرد',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = _items[i];
                                return _StocktakeItemRow(
                                  item: item,
                                  productName:
                                      _productsMap[item.productId]?.name ?? '—',
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StocktakeItemRow extends StatelessWidget {
  final StocktakeItem item;
  final String productName;

  const _StocktakeItemRow({required this.item, required this.productName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffColor = item.difference > 0
        ? AppColors.success
        : item.difference < 0
            ? AppColors.error
            : AppColors.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: diffColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'النظام: ${FormatUtils.formatQuantity(item.systemQuantity)} '
                  '→ الفعلي: ${FormatUtils.formatQuantity(item.actualQuantity)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondaryLight),
                ),
                if (item.reason != null && item.reason!.isNotEmpty)
                  Text(
                    item.reason!,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.difference == 0
                    ? '—'
                    : '${item.difference > 0 ? "+" : ""}${FormatUtils.formatQuantity(item.difference)}',
                style: TextStyle(
                  color: diffColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                FormatUtils.formatMoneyAr(item.differenceValue),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondaryLight),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
