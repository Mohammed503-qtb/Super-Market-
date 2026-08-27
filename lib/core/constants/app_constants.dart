import 'package:flutter/material.dart';

/// ألوان التطبيق - نظام ألوان احترافي بدون أزرق/إنديغو
class AppColors {
  AppColors._();

  // Primary - أخضر زمردي احترافي مناسب للبقالة
  static const Color primary = Color(0xFF10B981);
  static const Color primaryDark = Color(0xFF047857);
  static const Color primaryLight = Color(0xFF6EE7B7);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Secondary - برتقالي دافئ
  static const Color secondary = Color(0xFFF59E0B);
  static const Color secondaryDark = Color(0xFFB45309);
  static const Color onSecondary = Color(0xFFFFFFFF);

  // Accent
  static const Color accent = Color(0xFF8B5CF6);

  // Status colors
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFFACC15);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF06B6D4);

  // Light theme
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color dividerLight = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFCBD5E1);

  // Dark theme
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color dividerDark = Color(0xFF334155);
  static const Color borderDark = Color(0xFF475569);
}

/// ثوابت التطبيق العامة
class AppConstants {
  AppConstants._();

  static const String appName = 'نظام البقالة المحاسبي';
  static const String appShortName = 'بقالتي';
  static const String appVersion = '1.0.0';
  static const String defaultCurrency = 'ر.ي';
  static const String defaultCurrencyCode = 'YER';
  static const String defaultLanguageCode = 'ar';

  // قيود النظام
  static const int invoiceNumberPadding = 5;
  static const double maxDiscountPercent = 100.0;
  static const int paginationSize = 50;
  static const int searchDebounceMs = 300;

  // أنواع الحركات
  static const String invoicePrefixSale = 'SAL';
  static const String invoicePrefixPurchase = 'PUR';
}

/// أنواع الحركات المالية والمخزنية
class MovementTypes {
  MovementTypes._();

  // Inventory Movements
  static const String purchaseIn = 'PURCHASE_IN';
  static const String saleOut = 'SALE_OUT';
  static const String saleReturnIn = 'SALE_RETURN_IN';
  static const String purchaseReturnOut = 'PURCHASE_RETURN_OUT';
  static const String adjustmentIn = 'ADJUSTMENT_IN';
  static const String adjustmentOut = 'ADJUSTMENT_OUT';
  static const String transferIn = 'TRANSFER_IN';
  static const String transferOut = 'TRANSFER_OUT';
  static const String openingStock = 'OPENING_STOCK';

  // Cash Transaction sources
  static const String sourceSale = 'SALE';
  static const String sourcePurchase = 'PURCHASE';
  static const String sourceCustomerPayment = 'CUSTOMER_PAYMENT';
  static const String sourceSupplierPayment = 'SUPPLIER_PAYMENT';
  static const String sourceExpense = 'EXPENSE';
  static const String sourceWithdrawal = 'WITHDRAWAL';
  static const String sourceDeposit = 'DEPOSIT';
  static const String sourceOpeningBalance = 'OPENING_BALANCE';
  static const String sourceReturn = 'RETURN';
  static const String sourceAdjustment = 'ADJUSTMENT';
}

/// حالات الفاتورة
class InvoiceStatus {
  InvoiceStatus._();
  static const String draft = 'DRAFT';
  static const String completed = 'COMPLETED';
  static const String cancelled = 'CANCELLED';
  static const String returned = 'RETURNED';
  static const String partiallyReturned = 'PARTIALLY_RETURNED';
}

/// طرق الدفع
class PaymentType {
  PaymentType._();
  static const String cash = 'CASH';
  static const String credit = 'CREDIT';
  static const String mixed = 'MIXED';
}

/// اتجاه حركة النقد
class CashDirection {
  CashDirection._();
  static const String inbound = 'IN'; // دخل
  static const String outbound = 'OUT'; // صرف
}

/// رموز الصلاحيات
class PermissionCodes {
  PermissionCodes._();

  // المبيعات
  static const String salesView = 'sales.view';
  static const String salesCreate = 'sales.create';
  static const String salesEdit = 'sales.edit';
  static const String salesDelete = 'sales.delete';
  static const String salesReturn = 'sales.return';
  static const String salesDiscount = 'sales.discount';
  static const String salesChangePrice = 'sales.change_price';

  // المشتريات
  static const String purchaseView = 'purchase.view';
  static const String purchaseCreate = 'purchase.create';
  static const String purchaseEdit = 'purchase.edit';
  static const String purchaseDelete = 'purchase.delete';
  static const String purchaseReturn = 'purchase.return';

  // المخزون
  static const String inventoryView = 'inventory.view';
  static const String inventoryEdit = 'inventory.edit';
  static const String inventoryAdjust = 'inventory.adjust';
  static const String inventoryStocktake = 'inventory.stocktake';

  // العملاء
  static const String customersView = 'customers.view';
  static const String customersCreate = 'customers.create';
  static const String customersEdit = 'customers.edit';
  static const String customersDelete = 'customers.delete';
  static const String customersPayment = 'customers.payment';

  // الموردون
  static const String suppliersView = 'suppliers.view';
  static const String suppliersCreate = 'suppliers.create';
  static const String suppliersEdit = 'suppliers.edit';
  static const String suppliersDelete = 'suppliers.delete';
  static const String suppliersPayment = 'suppliers.payment';

  // الصندوق
  static const String cashboxView = 'cashbox.view';
  static const String cashboxCreate = 'cashbox.create';
  static const String cashboxAdjust = 'cashbox.adjust';
  static const String cashboxClose = 'cashbox.close';

  // التقارير
  static const String reportsView = 'reports.view';
  static const String reportsProfit = 'reports.profit';
  static const String reportsCash = 'reports.cash';
  static const String reportsDebts = 'reports.debts';
  static const String reportsInventory = 'reports.inventory';

  // المستخدمون
  static const String usersView = 'users.view';
  static const String usersCreate = 'users.create';
  static const String usersEdit = 'users.edit';
  static const String usersDelete = 'users.delete';

  // الإعدادات
  static const String settingsView = 'settings.view';
  static const String settingsEdit = 'settings.edit';

  // النسخ الاحتياطي
  static const String backupCreate = 'backup.create';
  static const String backupRestore = 'backup.restore';
}
