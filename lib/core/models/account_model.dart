import 'package:flutter/material.dart';
import '../theme/bento_theme.dart';

enum AccountType { cash, bank, card, savings }

extension AccountTypeX on AccountType {
  String get dbValue => name;

  String get label {
    switch (this) {
      case AccountType.cash:
        return 'Efectivo';
      case AccountType.bank:
        return 'Banco';
      case AccountType.card:
        return 'Tarjeta';
      case AccountType.savings:
        return 'Ahorros';
    }
  }

  IconData get icon {
    switch (this) {
      case AccountType.cash:
        return Icons.payments_outlined;
      case AccountType.bank:
        return Icons.account_balance_outlined;
      case AccountType.card:
        return Icons.credit_card_outlined;
      case AccountType.savings:
        return Icons.savings_outlined;
    }
  }

  Color get color {
    switch (this) {
      case AccountType.cash:
        return BentoTheme.successGreen;
      case AccountType.bank:
        return BentoTheme.accentBlue;
      case AccountType.card:
        return BentoTheme.accentOrange;
      case AccountType.savings:
        return BentoTheme.accentPurple;
    }
  }
}

class AccountModel {
  final String id;
  final String userId;
  final String name;
  final AccountType type;
  final double initialBalance;
  final String currency;
  final DateTime createdAt;

  const AccountModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.currency,
    required this.createdAt,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      type: AccountType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AccountType.cash,
      ),
      initialBalance: (json['initial_balance'] as num).toDouble(),
      currency: (json['currency'] as String?) ?? 'USD',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.dbValue,
        'initial_balance': initialBalance,
        'currency': currency,
      };

  AccountModel copyWith({
    String? name,
    AccountType? type,
    double? initialBalance,
  }) {
    return AccountModel(
      id: id,
      userId: userId,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      currency: currency,
      createdAt: createdAt,
    );
  }
}
