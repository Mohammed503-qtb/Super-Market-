# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-27

### Added
- ✅ نظام مصادقة كامل (تسجيل دخول/خروج، جلسة محفوظة)
- ✅ 7 أدوار افتراضية (مالك، مدير، كاشير، مشتري، أمين مخزن، محاسب، مشاهد)
- ✅ 43 صلاحية موزعة على 10 وحدات
- ✅ نظام منتجات مع باركود، SKU، تصنيفات، وحدات
- ✅ مخزون مع حركات كاملة وتكلفة مرجحة (Weighted Average Cost)
- ✅ مبيعات (POS) مع سلة، خصومات، دفع نقدي/آجل/مختلط
- ✅ مشتريات من الموردين مع دفع آجل
- ✅ إدارة عملاء وموردين مع كشوف حساب
- ✅ صندوق كامل (مصروفات، سحوبات، إيداعات، إغلاق يوم)
- ✅ تقارير شاملة (5 أنواع)
- ✅ مرتجعات بيع وشراء
- ✅ جرد مخزون كامل
- ✅ نسخ احتياطي واستعادة محلي
- ✅ سجل تدقيق (Audit Log) لكل العمليات الحساسة
- ✅ دعم العربية و RTL
- ✅ الوضع الفاتح والداكن
- ✅ معاملات ذرية لكل العمليات المالية
- ✅ منع أخطاء floating-point باستخدام Decimal

### Technical
- Flutter 3.27.0 + Dart 3.6.0
- Drift ORM (SQLite) - 26 جدول
- Provider لإدارة الحالة
- Architecture: Clean Architecture (core/data/domain/application/features)

### Security
- تشفير كلمات المرور SHA-256 + salt
- الصلاحيات تُفْرض على مستوى المنطق
- Audit Log لكل العمليات الحساسة
- لا تخزين كلمات المرور كنص صريح

## [Unreleased]

### Planned
- 📋 طباعة الفواتير عبر Bluetooth
- 📋 دعم الباركود عبر الكاميرا
- 📋 تصدير التقارير PDF
- 📋 مزامنة سحابية اختيارية
- 📋 دعم متعدد اللغات (عربي/إنجليزي)
- 📋 تنبيهات المخزون المنخفض
- 📋 نظام ولاء العملاء
- 📋 أكواد QR للمنتجات
