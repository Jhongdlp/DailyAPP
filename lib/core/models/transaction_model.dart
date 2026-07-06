import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/bento_theme.dart';

enum TransactionType { income, expense, transfer }

extension TransactionTypeX on TransactionType {
  String get dbValue => name;

  String get label {
    switch (this) {
      case TransactionType.income:
        return 'Ingreso';
      case TransactionType.expense:
        return 'Gasto';
      case TransactionType.transfer:
        return 'Transferencia';
    }
  }

  Color get color {
    switch (this) {
      case TransactionType.income:
        return BentoTheme.successGreen;
      case TransactionType.expense:
        return BentoTheme.errorRed;
      case TransactionType.transfer:
        return BentoTheme.accentBlue;
    }
  }
}

/// Categoría de transacción definida en la app (no en base de datos).
class FinanceCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool forIncome;

  const FinanceCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.forIncome = false,
  });
}

class FinanceCategories {
  static const List<FinanceCategory> all = [
    // Gastos
    FinanceCategory(id: 'food', label: 'Comida', icon: Icons.restaurant_outlined, color: BentoTheme.accentOrange),
    FinanceCategory(id: 'transport', label: 'Transporte', icon: Icons.directions_bus_outlined, color: BentoTheme.accentBlue),
    FinanceCategory(id: 'home', label: 'Hogar', icon: Icons.home_outlined, color: BentoTheme.accentPurple),
    FinanceCategory(id: 'services', label: 'Servicios', icon: Icons.bolt_outlined, color: BentoTheme.accentOrange),
    FinanceCategory(id: 'health', label: 'Salud', icon: Icons.favorite_outline, color: BentoTheme.errorRed),
    FinanceCategory(id: 'entertainment', label: 'Ocio', icon: Icons.sports_esports_outlined, color: BentoTheme.accentPurple),
    FinanceCategory(id: 'shopping', label: 'Compras', icon: Icons.shopping_bag_outlined, color: BentoTheme.accentBlue),
    FinanceCategory(id: 'education', label: 'Educación', icon: Icons.school_outlined, color: BentoTheme.primaryDark),
    FinanceCategory(id: 'subscriptions', label: 'Suscripciones', icon: Icons.autorenew_outlined, color: BentoTheme.accentBlue),
    // Ingresos
    FinanceCategory(id: 'salary', label: 'Salario', icon: Icons.work_outline, color: BentoTheme.successGreen, forIncome: true),
    FinanceCategory(id: 'freelance', label: 'Freelance', icon: Icons.laptop_outlined, color: BentoTheme.successGreen, forIncome: true),
    FinanceCategory(id: 'investment', label: 'Inversión', icon: Icons.trending_up_outlined, color: BentoTheme.successGreen, forIncome: true),
    // Genérica
    FinanceCategory(id: 'other', label: 'Otro', icon: Icons.category_outlined, color: BentoTheme.textSecondary),
  ];

  static FinanceCategory byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);

  static List<FinanceCategory> forType(TransactionType type) {
    if (type == TransactionType.income) {
      return all.where((c) => c.forIncome || c.id == 'other').toList();
    }
    return all.where((c) => !c.forIncome).toList();
  }
}

class TransactionModel {
  final String id;
  final String userId;
  final String accountId;
  final String? transferAccountId;
  final TransactionType type;
  final double amount;
  final String category;
  final String description;
  final DateTime occurredAt;
  final DateTime createdAt;

  const TransactionModel({
    required this.id,
    required this.userId,
    required this.accountId,
    this.transferAccountId,
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.occurredAt,
    required this.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      accountId: json['account_id'] as String,
      transferAccountId: json['transfer_account_id'] as String?,
      type: TransactionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => TransactionType.expense,
      ),
      amount: (json['amount'] as num).toDouble(),
      category: (json['category'] as String?) ?? 'other',
      description: (json['description'] as String?) ?? '',
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'account_id': accountId,
        'transfer_account_id': transferAccountId,
        'type': type.dbValue,
        'amount': amount,
        'category': category,
        'description': description,
        'occurred_at': DateFormat('yyyy-MM-dd').format(occurredAt),
      };

  FinanceCategory get categoryInfo => FinanceCategories.byId(category);

  /// Monto con signo: positivo para ingresos, negativo para gastos.
  double get signedAmount {
    switch (type) {
      case TransactionType.income:
        return amount;
      case TransactionType.expense:
        return -amount;
      case TransactionType.transfer:
        return 0;
    }
  }
}

/// Formateador de moneda USD compartido por la feature de finanzas.
final usdFormat = NumberFormat.currency(locale: 'en_US', symbol: '\$');
