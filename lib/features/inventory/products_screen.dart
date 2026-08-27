import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة إدارة المنتجات
/// -------------------
/// - قائمة المنتجات مع بحث فوري (الاسم / الباركود / SKU).
/// - كل صف يعرض: الاسم، الباركود، التصنيف، الوحدة، سعر الشراء، سعر البيع،
///   المخزون الحالي (ملون: أحمر ≤ 0، كهرماني ≤ الحد الأدنى، أخضر غير ذلك)،
///   والتكلفة المتوسطة (للأدوار التي تملك صلاحية الأرباح فقط).
/// - زر "إضافة منتج" (FAB) يتطلب صلاحية inventory.edit.
/// - تعديل/حذف منتج — الحذف مرفوض إذا كان الصنف مبيع/مشترى مسبقاً.
/// - نموذج المنتج يحتوي على كل الحقول + الرصيد الافتتاحي وتكلفته (عند الإنشاء فقط).
/// - إدارة التصنيفات والوحدات كحواريات منفصلة داخل نفس الملف.
/// - تخطيط متجاوب: شبكة بطاقات على الشاشات العريضة، قائمة على الهواتف.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<Product> _products = [];
  final Map<int, Category> _categoriesMap = {};
  final Map<int, Unit> _unitsMap = {};
  final List<Category> _categories = [];
  final List<Unit> _units = [];

  // ===== حالة الواجهة =====
  bool _isLoading = true;
  String _searchQuery = '';

  // ===== الصلاحيات =====
  bool _canEdit = false;
  bool _canViewCost = false;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _loadAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canEdit = auth.hasPermission(PermissionCodes.inventoryEdit);
    _canViewCost = auth.hasPermission(PermissionCodes.reportsProfit);
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadCategories(),
      _loadUnits(),
    ]);
    await _refreshProducts();
  }

  Future<void> _loadCategories() async {
    final cats = await ServiceLocator.database.categoryDao.getAll();
    _categories
      ..clear()
      ..addAll(cats);
    _categoriesMap
      ..clear()
      ..addEntries(cats.map((c) => MapEntry(c.id, c)));
  }

  Future<void> _loadUnits() async {
    final list = await ServiceLocator.database.unitDao.getAll();
    _units
      ..clear()
      ..addAll(list);
    _unitsMap
      ..clear()
      ..addEntries(list.map((u) => MapEntry(u.id, u)));
  }

  Future<void> _refreshProducts() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final db = ServiceLocator.database;
      List<Product> result;
      if (_searchQuery.trim().isNotEmpty) {
        result = await db.productDao.search(_searchQuery.trim());
      } else {
        result = await db.productDao.getAll();
      }
      _products
        ..clear()
        ..addAll(result);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل المنتجات: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () {
        _searchQuery = _searchController.text;
        _refreshProducts();
      },
    );
  }

  // =====================
  // إحصائيات سريعة
  // =====================

  int get _outOfStockCount =>
      _products.where((p) => p.currentStock <= 0).length;
  int get _lowStockCount => _products
      .where((p) => p.currentStock > 0 && p.currentStock <= p.minimumStock)
      .length;
  num get _inventoryValue =>
      _products.fold<num>(0, (s, p) => s + p.currentStock * p.averageCost);

  // =====================
  // لون المخزون
  // =====================

  Color _stockColor(Product p) {
    if (p.currentStock <= 0) return AppColors.error;
    if (p.minimumStock > 0 && p.currentStock <= p.minimumStock) {
      return AppColors.secondary;
    }
    return AppColors.success;
  }

  String _stockLabel(Product p) {
    if (p.currentStock <= 0) return 'نفذ المخزون';
    if (p.minimumStock > 0 && p.currentStock <= p.minimumStock) {
      return 'مخزون منخفض';
    }
    return 'متاح';
  }

  String _categoryName(int? id) {
    if (id == null) return '—';
    return _categoriesMap[id]?.name ?? '—';
  }

  String _unitSymbol(int? id) {
    if (id == null) return '';
    return _unitsMap[id]?.symbol ?? _unitsMap[id]?.name ?? '';
  }

  // =====================
  // نموذج المنتج
  // =====================

  Future<void> _openProductForm({Product? product}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductFormDialog(
        product: product,
        categories: _categories,
        units: _units,
        canViewCost: _canViewCost,
      ),
    );
    if (result == true) {
      await _refreshProducts();
    }
  }

  // =====================
  // حذف المنتج
  // =====================

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف المنتج',
      message:
          'هل أنت متأكد من حذف "${product.name}"؟ لا يمكن التراجع عن هذه العملية.',
      confirmText: 'حذف',
      isDanger: true,
    );
    if (confirmed != true) return;

    try {
      final hasTransactions = await _hasSalesOrPurchases(product.id);
      if (hasTransactions) {
        if (mounted) {
          showErrorSnackBar(
            context,
            'لا يمكن حذف المنتج لأنه مرتبط بمبيعات أو مشتريات. '
            'يمكنك تعطيله بدلاً من ذلك.',
          );
        }
        return;
      }

      await ServiceLocator.database.productDao.deleteProduct(product.id);
      if (mounted) {
        showSuccessSnackBar(context, 'تم حذف المنتج بنجاح');
      }
      await _refreshProducts();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل الحذف: $e');
      }
    }
  }

  /// التحقق إذا كان المنتج له مبيعات أو مشتريات مسجلة
  Future<bool> _hasSalesOrPurchases(int productId) async {
    final db = ServiceLocator.database;
    final saleCount = await db.customSelect(
      'SELECT COUNT(*) AS c FROM sale_items WHERE product_id = ?',
      variables: [Variable<int>(productId)],
    ).getSingle();
    final purchaseCount = await db.customSelect(
      'SELECT COUNT(*) AS c FROM purchase_items WHERE product_id = ?',
      variables: [Variable<int>(productId)],
    ).getSingle();
    return saleCount.read<int>('c') > 0 || purchaseCount.read<int>('c') > 0;
  }

  // =====================
  // حواريات التصنيفات والوحدات
  // =====================

  Future<void> _openCategoriesDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _CategoriesManagerDialog(),
    );
    await _loadCategories();
    await _refreshProducts();
  }

  Future<void> _openUnitsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _UnitsManagerDialog(),
    );
    await _loadUnits();
    await _refreshProducts();
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: [
          IconButton(
            tooltip: 'إدارة التصنيفات',
            icon: const Icon(Icons.category_outlined),
            onPressed: _openCategoriesDialog,
          ),
          IconButton(
            tooltip: 'إدارة الوحدات',
            icon: const Icon(Icons.straighten_outlined),
            onPressed: _openUnitsDialog,
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openProductForm(),
              icon: const Icon(Icons.add),
              label: const Text('منتج جديد'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildSearchAndStats()),
            if (_isLoading && _products.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل المنتجات...'),
              )
            else if (_products.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: _searchQuery.isNotEmpty
                      ? 'لا توجد منتجات مطابقة لبحثك'
                      : 'لا توجد منتجات بعد',
                  actionLabel: _canEdit ? 'إضافة منتج' : null,
                  onAction: _canEdit ? () => _openProductForm() : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                sliver: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (wide) {
                      return SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.05,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _ProductCard(
                            product: _products[i],
                            categoryName:
                                _categoryName(_products[i].categoryId),
                            unitSymbol: _unitSymbol(_products[i].unitId),
                            stockColor: _stockColor(_products[i]),
                            stockLabel: _stockLabel(_products[i]),
                            canEdit: _canEdit,
                            canViewCost: _canViewCost,
                            onEdit: () =>
                                _openProductForm(product: _products[i]),
                            onDelete: () => _confirmDelete(_products[i]),
                          ),
                          childCount: _products.length,
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _ProductTile(
                          product: _products[i],
                          categoryName: _categoryName(_products[i].categoryId),
                          unitSymbol: _unitSymbol(_products[i].unitId),
                          stockColor: _stockColor(_products[i]),
                          stockLabel: _stockLabel(_products[i]),
                          canEdit: _canEdit,
                          canViewCost: _canViewCost,
                          onEdit: () => _openProductForm(product: _products[i]),
                          onDelete: () => _confirmDelete(_products[i]),
                        ),
                        childCount: _products.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          SearchField(
            controller: _searchController,
            hintText: 'ابحث بالاسم، الباركود أو SKU...',
            onChanged: _onSearchChanged,
            onClear: () {
              _searchQuery = '';
              _refreshProducts();
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _miniStat(
                  'إجمالي الأصناف',
                  '${_products.length}',
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
                if (_canViewCost)
                  _miniStat(
                    'قيمة المخزون',
                    FormatUtils.formatMoneyAr(_inventoryValue),
                    Icons.account_balance_wallet_outlined,
                    AppColors.accent,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(left: 8),
      child: StatCard(
        title: title,
        value: value,
        icon: icon,
        color: color,
      ),
    );
  }
}

// =====================================================
// بطاقة المنتج (للشاشات العريضة)
// =====================================================
class _ProductCard extends StatelessWidget {
  final Product product;
  final String categoryName;
  final String unitSymbol;
  final Color stockColor;
  final String stockLabel;
  final bool canEdit;
  final bool canViewCost;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.categoryName,
    required this.unitSymbol,
    required this.stockColor,
    required this.stockLabel,
    required this.canEdit,
    required this.canViewCost,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (product.barcode != null &&
                              product.barcode!.isNotEmpty)
                            _chip(
                              Icons.qr_code_2,
                              product.barcode!,
                              AppColors.info,
                            ),
                          if (product.sku != null && product.sku!.isNotEmpty)
                            _chip(Icons.tag, product.sku!, AppColors.accent),
                          _chip(Icons.category_outlined, categoryName,
                              AppColors.primary),
                          if (unitSymbol.isNotEmpty)
                            _chip(Icons.straighten, unitSymbol,
                                AppColors.secondary),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!product.isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          AppColors.textSecondaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'معطّل',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 18),
            // المخزون
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: stockColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory, color: stockColor, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    stockLabel,
                    style: TextStyle(
                      color: stockColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${FormatUtils.formatQuantity(product.currentStock)} '
                    '${unitSymbol.isEmpty ? '' : unitSymbol}',
                    style: TextStyle(
                      color: stockColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // الأسعار
            Row(
              children: [
                Expanded(
                  child: _priceBlock(
                    'سعر البيع',
                    FormatUtils.formatMoneyAr(product.sellingPrice),
                    AppColors.primary,
                  ),
                ),
                if (canViewCost) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _priceBlock(
                      'سعر الشراء',
                      FormatUtils.formatMoneyAr(product.purchasePrice),
                      AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _priceBlock(
                      'التكلفة المتوسطة',
                      FormatUtils.formatMoneyAr(product.averageCost),
                      AppColors.accent,
                    ),
                  ),
                ],
              ],
            ),
            if (canViewCost && product.wholesalePrice > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _priceBlock(
                      'سعر الجملة',
                      FormatUtils.formatMoneyAr(product.wholesalePrice),
                      AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _priceBlock(
                      'الحد الأدنى للسعر',
                      FormatUtils.formatMoneyAr(product.minimumSellingPrice),
                      AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canEdit)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('تعديل'),
                  ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.error),
                    label: const Text('حذف',
                        style: TextStyle(color: AppColors.error)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _priceBlock(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// صف المنتج (للهواتف)
// =====================================================
class _ProductTile extends StatelessWidget {
  final Product product;
  final String categoryName;
  final String unitSymbol;
  final Color stockColor;
  final String stockLabel;
  final bool canEdit;
  final bool canViewCost;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductTile({
    required this.product,
    required this.categoryName,
    required this.unitSymbol,
    required this.stockColor,
    required this.stockLabel,
    required this.canEdit,
    required this.canViewCost,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canEdit ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (product.barcode != null &&
                                product.barcode!.isNotEmpty)
                              Text(
                                'باركود: ${product.barcode}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryLight),
                              ),
                            Text(
                              'التصنيف: $categoryName',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondaryLight),
                            ),
                            if (unitSymbol.isNotEmpty)
                              Text(
                                'الوحدة: $unitSymbol',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryLight),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!product.isActive)
                    const Text(
                      'معطّل',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: stockColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory, color: stockColor, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$stockLabel: '
                              '${FormatUtils.formatQuantity(product.currentStock)}'
                              '${unitSymbol.isEmpty ? '' : ' $unitSymbol'}',
                              style: TextStyle(
                                color: stockColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'البيع: ${FormatUtils.formatMoneyAr(product.sellingPrice)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (canViewCost)
                    Expanded(
                      child: Text(
                        'التكلفة: ${FormatUtils.formatMoneyAr(product.averageCost)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  if (canEdit) ...[
                    IconButton(
                      tooltip: 'تعديل',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      tooltip: 'حذف',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error),
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// نموذج إضافة/تعديل منتج
// =====================================================
class _ProductFormDialog extends StatefulWidget {
  final Product? product;
  final List<Category> categories;
  final List<Unit> units;
  final bool canViewCost;

  const _ProductFormDialog({
    this.product,
    required this.categories,
    required this.units,
    required this.canViewCost,
  });

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _sellingPriceCtrl;
  late final TextEditingController _wholesalePriceCtrl;
  late final TextEditingController _minimumSellingPriceCtrl;
  late final TextEditingController _minimumStockCtrl;
  late final TextEditingController _openingStockCtrl;
  late final TextEditingController _openingStockCostCtrl;

  int? _categoryId;
  int? _unitId;
  bool _isActive = true;
  bool _saving = false;
  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _skuCtrl = TextEditingController(text: p?.sku ?? '');
    _purchasePriceCtrl = TextEditingController(
      text: p == null ? '' : _formatNum(p.purchasePrice),
    );
    _sellingPriceCtrl = TextEditingController(
      text: p == null ? '' : _formatNum(p.sellingPrice),
    );
    _wholesalePriceCtrl = TextEditingController(
      text: p == null ? '' : _formatNum(p.wholesalePrice),
    );
    _minimumSellingPriceCtrl = TextEditingController(
      text: p == null ? '' : _formatNum(p.minimumSellingPrice),
    );
    _minimumStockCtrl = TextEditingController(
      text: p == null ? '' : _formatNum(p.minimumStock),
    );
    _openingStockCtrl = TextEditingController(text: '0');
    _openingStockCostCtrl = TextEditingController(
      text: p == null ? '0' : _formatNum(p.purchasePrice),
    );
    _categoryId = p?.categoryId;
    _unitId = p?.unitId;
    _isActive = p?.isActive ?? true;
  }

  String _formatNum(num v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _skuCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _wholesalePriceCtrl.dispose();
    _minimumSellingPriceCtrl.dispose();
    _minimumStockCtrl.dispose();
    _openingStockCtrl.dispose();
    _openingStockCostCtrl.dispose();
    super.dispose();
  }

  double _parseNum(String s) {
    final v = num.tryParse(s.trim());
    return (v ?? 0).toDouble();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final db = ServiceLocator.database;
      final userId = context.read<AuthProvider>().currentUser!.id;

      final name = _nameCtrl.text.trim();
      final barcode =
          _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim();
      final sku = _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim();
      final purchasePrice = _parseNum(_purchasePriceCtrl.text);
      final sellingPrice = _parseNum(_sellingPriceCtrl.text);
      final wholesalePrice = _parseNum(_wholesalePriceCtrl.text);
      final minimumSellingPrice = _parseNum(_minimumSellingPriceCtrl.text);
      final minimumStock = _parseNum(_minimumStockCtrl.text);

      if (sellingPrice <= 0) {
        throw const FormatException('سعر البيع يجب أن يكون أكبر من صفر');
      }

      if (_isEdit) {
        final existing = widget.product!;
        final updated = existing.copyWith(
          name: name,
          barcode: Value(barcode),
          sku: Value(sku),
          categoryId: Value(_categoryId),
          unitId: Value(_unitId),
          purchasePrice: purchasePrice,
          sellingPrice: sellingPrice,
          wholesalePrice: wholesalePrice,
          minimumSellingPrice: minimumSellingPrice,
          minimumStock: minimumStock,
          isActive: _isActive,
          updatedAt: DateTime.now(),
        );
        await db.productDao.updateProduct(updated);
        if (mounted) {
          showSuccessSnackBar(context, 'تم تحديث المنتج بنجاح');
          Navigator.of(context).pop(true);
        }
      } else {
        final openingQty = _parseNum(_openingStockCtrl.text);
        final openingCost = _parseNum(_openingStockCostCtrl.text);

        final productId = await db.productDao.insertProduct(
          ProductsCompanion.insert(
            name: name,
            barcode: Value(barcode),
            sku: Value(sku),
            categoryId: Value(_categoryId),
            unitId: Value(_unitId),
            purchasePrice: Value(purchasePrice),
            sellingPrice: Value(sellingPrice),
            wholesalePrice: Value(wholesalePrice),
            minimumSellingPrice: Value(minimumSellingPrice),
            minimumStock: Value(minimumStock),
            isActive: Value(_isActive),
          ),
        );

        // إذا كان هناك رصيد افتتاحي، نطبقه عبر خدمة المخزون لتحديث
        // التكلفة المرجحة وتسجيل حركة المخزون.
        if (openingQty > 0) {
          await ServiceLocator.inventoryService.setOpeningStock(
            productId: productId,
            quantity: openingQty,
            unitCost: openingCost > 0 ? openingCost : purchasePrice,
            userId: userId,
          );
        }
        if (mounted) {
          showSuccessSnackBar(context, 'تم إنشاء المنتج بنجاح');
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل الحفظ: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 800 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _isEdit
            ? _buildScaffold('تعديل المنتج')
            : _buildScaffold('منتج جديد'),
      ),
    );
  }

  Widget _buildScaffold(String title) {
    final wide = MediaQuery.of(context).size.width >= 700;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== معلومات أساسية =====
              const SectionHeader(
                title: 'معلومات أساسية',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 8),
              _field(_nameCtrl, 'اسم المنتج *', 'مثال: أرز بسمتي 5كغ',
                  validator: (v) =>
                      Validators.required(v, fieldName: 'اسم المنتتج')),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      _barcodeCtrl,
                      'الباركود',
                      ' اختياري',
                      validator: Validators.barcode,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9\-]')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      _skuCtrl,
                      'SKU / رمز الصنف',
                      'اختياري',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildCategoryDropdown()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildUnitDropdown()),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                title: const Text('المنتج نشط (متاح للبيع)'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // ===== الأسعار =====
              SectionHeader(
                title: widget.canViewCost ? 'الأسعار والتكلفة' : 'الأسعار',
                icon: Icons.price_change_outlined,
              ),
              const SizedBox(height: 8),
              _buildPricesGrid(wide),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // ===== المخزون =====
              const SectionHeader(
                title: 'المخزون',
                icon: Icons.inventory_outlined,
              ),
              const SizedBox(height: 8),
              _field(
                _minimumStockCtrl,
                'حد المخزون الأدنى (تنبيه عند النقص)',
                '0',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory,
                              color: AppColors.info, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'الرصيد الافتتاحي',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.info),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'سيتم إنشاء حركة مخزون افتتاحي وتحديث التكلفة المتوسطة تلقائياً.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondaryLight),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        _openingStockCtrl,
                        'الكمية الافتتاحية',
                        '0',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$')),
                        ],
                      ),
                    ),
                    if (widget.canViewCost) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          _openingStockCostCtrl,
                          'تكلفة الوحدة الافتتاحية',
                          '0',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*$')),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 24),

              // ===== أزرار الحفظ =====
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                      label: const Text('إلغاء'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء المنتج'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPricesGrid(bool wide) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 3 : 2;
        final children = <Widget>[
          _field(
            _sellingPriceCtrl,
            'سعر البيع *',
            '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                Validators.positiveNonZero(v, fieldName: 'سعر البيع'),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
          ),
          if (widget.canViewCost)
            _field(
              _purchasePriceCtrl,
              'سعر الشراء',
              '0',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
            ),
          _field(
            _wholesalePriceCtrl,
            'سعر الجملة',
            '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
          ),
          _field(
            _minimumSellingPriceCtrl,
            'الحد الأدنى لسعر البيع',
            '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
          ),
        ];
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((w) => SizedBox(
                    width: (c.maxWidth - 12 * (cols - 1)) / cols,
                    child: w,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<int>(
      value: _categoryId,
      decoration: const InputDecoration(
        labelText: 'التصنيف',
        prefixIcon: Icon(Icons.category_outlined),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<int>(
          value: null,
          child: Text('— بدون تصنيف —'),
        ),
        ...widget.categories.map(
          (c) => DropdownMenuItem<int>(
            value: c.id,
            child: Text(c.name),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _categoryId = v),
    );
  }

  Widget _buildUnitDropdown() {
    return DropdownButtonFormField<int>(
      value: _unitId,
      decoration: const InputDecoration(
        labelText: 'الوحدة',
        prefixIcon: Icon(Icons.straighten_outlined),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<int>(
          value: null,
          child: Text('— بدون وحدة —'),
        ),
        ...widget.units.map(
          (u) => DropdownMenuItem<int>(
            value: u.id,
            child: Text('${u.name} (${u.symbol})'),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _unitId = v),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
    );
  }
}

// =====================================================
// إدارة التصنيفات
// =====================================================
class _CategoriesManagerDialog extends StatefulWidget {
  const _CategoriesManagerDialog();

  @override
  State<_CategoriesManagerDialog> createState() =>
      _CategoriesManagerDialogState();
}

class _CategoriesManagerDialogState extends State<_CategoriesManagerDialog> {
  final List<Category> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ServiceLocator.database.categoryDao.getAll();
      _items
        ..clear()
        ..addAll(list);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل التصنيفات: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({Category? cat}) async {
    final nameCtrl = TextEditingController(text: cat?.name ?? '');
    final descCtrl = TextEditingController(text: cat?.description ?? '');
    final isActive = ValueNotifier<bool>(cat?.isActive ?? true);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat == null ? 'إضافة تصنيف' : 'تعديل تصنيف'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم التصنيف *',
                    isDense: true,
                  ),
                  validator: (v) =>
                      Validators.required(v, fieldName: 'اسم التصنيف'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الوصف',
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<bool>(
                  valueListenable: isActive,
                  builder: (_, v, __) => SwitchListTile.adaptive(
                    title: const Text('نشط'),
                    value: v,
                    onChanged: (n) => isActive.value = n,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final db = ServiceLocator.database;
                if (cat == null) {
                  await db.categoryDao
                      .insertCategory(CategoriesCompanion.insert(
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty
                        ? const Value.absent()
                        : Value(descCtrl.text.trim()),
                    isActive: Value(isActive.value),
                  ));
                } else {
                  await db.categoryDao.updateCategory(cat.copyWith(
                    name: nameCtrl.text.trim(),
                    description: Value(descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim()),
                    isActive: isActive.value,
                  ));
                }
                if (ctx.mounted) Navigator.of(ctx).pop(true);
                if (mounted) {
                  showSuccessSnackBar(
                      context, cat == null ? 'تمت الإضافة' : 'تم التحديث');
                }
              } catch (e) {
                if (mounted) {
                  showErrorSnackBar(context, 'فشل الحفظ: $e');
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true) await _load();
  }

  Future<void> _delete(Category cat) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف التصنيف',
      message: 'هل تريد حذف "${cat.name}"؟ المنتجات المرتبطة ستصبح بدون تصنيف.',
      isDanger: true,
      confirmText: 'حذف',
    );
    if (confirmed != true) return;
    try {
      await ServiceLocator.database.categoryDao.deleteCategory(cat.id);
      if (mounted) showSuccessSnackBar(context, 'تم الحذف');
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل الحذف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة التصنيفات'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add),
            label: const Text('تصنيف جديد'),
          ),
          body: _loading
              ? const LoadingIndicator()
              : _items.isEmpty
                  ? EmptyState(
                      message: 'لا توجد تصنيفات بعد',
                      actionLabel: 'إضافة تصنيف',
                      onAction: () => _addOrEdit(),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = _items[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.12),
                            child: const Icon(Icons.category,
                                color: AppColors.primary),
                          ),
                          title: Text(c.name),
                          subtitle: c.description == null
                              ? null
                              : Text(
                                  c.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!c.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.textSecondaryLight
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'معطّل',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                              IconButton(
                                tooltip: 'تعديل',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _addOrEdit(cat: c),
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: AppColors.error),
                                onPressed: () => _delete(c),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

// =====================================================
// إدارة الوحدات
// =====================================================
class _UnitsManagerDialog extends StatefulWidget {
  const _UnitsManagerDialog();

  @override
  State<_UnitsManagerDialog> createState() => _UnitsManagerDialogState();
}

class _UnitsManagerDialogState extends State<_UnitsManagerDialog> {
  final List<Unit> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ServiceLocator.database.unitDao.getAll();
      _items
        ..clear()
        ..addAll(list);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الوحدات: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({Unit? unit}) async {
    final nameCtrl = TextEditingController(text: unit?.name ?? '');
    final symbolCtrl = TextEditingController(text: unit?.symbol ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(unit == null ? 'إضافة وحدة' : 'تعديل وحدة'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الوحدة *',
                    hintText: 'مثال: كيلو',
                    isDense: true,
                  ),
                  validator: (v) =>
                      Validators.required(v, fieldName: 'اسم الوحدة'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: symbolCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الرمز *',
                    hintText: 'مثال: كغ',
                    isDense: true,
                  ),
                  validator: (v) => Validators.required(v, fieldName: 'الرمز'),
                  maxLength: 10,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final db = ServiceLocator.database;
                if (unit == null) {
                  await db.unitDao.insertUnit(UnitsCompanion.insert(
                    name: nameCtrl.text.trim(),
                    symbol: symbolCtrl.text.trim(),
                  ));
                } else {
                  await db.unitDao.updateUnit(unit.copyWith(
                    name: nameCtrl.text.trim(),
                    symbol: symbolCtrl.text.trim(),
                  ));
                }
                if (ctx.mounted) Navigator.of(ctx).pop(true);
                if (mounted) {
                  showSuccessSnackBar(
                      context, unit == null ? 'تمت الإضافة' : 'تم التحديث');
                }
              } catch (e) {
                if (mounted) {
                  showErrorSnackBar(context, 'فشل الحفظ: $e');
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true) await _load();
  }

  Future<void> _delete(Unit unit) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف الوحدة',
      message: 'هل تريد حذف "${unit.name}"؟ المنتجات المرتبطة ستصبح بدون وحدة.',
      isDanger: true,
      confirmText: 'حذف',
    );
    if (confirmed != true) return;
    try {
      await ServiceLocator.database.unitDao.deleteUnit(unit.id);
      if (mounted) showSuccessSnackBar(context, 'تم الحذف');
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل الحذف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة الوحدات'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                tooltip: 'إغلاق',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add),
            label: const Text('وحدة جديدة'),
          ),
          body: _loading
              ? const LoadingIndicator()
              : _items.isEmpty
                  ? EmptyState(
                      message: 'لا توجد وحدات بعد',
                      actionLabel: 'إضافة وحدة',
                      onAction: () => _addOrEdit(),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final u = _items[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.secondary.withValues(alpha: 0.12),
                            child: const Icon(Icons.straighten,
                                color: AppColors.secondary),
                          ),
                          title: Text(u.name),
                          subtitle: Text(
                            'الرمز: ${u.symbol}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'تعديل',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _addOrEdit(unit: u),
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: AppColors.error),
                                onPressed: () => _delete(u),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
