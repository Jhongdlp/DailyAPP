import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';

class AccountsNotifier extends AsyncNotifier<List<AccountModel>> {
  @override
  Future<List<AccountModel>> build() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('accounts')
        .select()
        .order('created_at');

    return (data as List).map((e) => AccountModel.fromJson(e)).toList();
  }

  List<AccountModel> get _current => state.value ?? [];

  Future<void> addAccount(AccountModel account) async {
    final user = Supabase.instance.client.auth.currentUser!;
    final data = await Supabase.instance.client
        .from('accounts')
        .insert({...account.toJson(), 'user_id': user.id})
        .select()
        .single();

    state = AsyncData([..._current, AccountModel.fromJson(data)]);
  }

  Future<void> updateAccount(AccountModel account) async {
    await Supabase.instance.client
        .from('accounts')
        .update(account.toJson())
        .eq('id', account.id);

    final list = [..._current];
    final idx = list.indexWhere((a) => a.id == account.id);
    if (idx != -1) list[idx] = account;
    state = AsyncData(list);
  }

  Future<void> deleteAccount(String id) async {
    await Supabase.instance.client.from('accounts').delete().eq('id', id);
    state = AsyncData(_current.where((a) => a.id != id).toList());
    // Las transacciones de la cuenta se borran en cascada en la BD
    ref.invalidate(transactionsProvider);
  }
}

class TransactionsNotifier extends AsyncNotifier<List<TransactionModel>> {
  @override
  Future<List<TransactionModel>> build() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('transactions')
        .select()
        .order('occurred_at', ascending: false)
        .order('created_at', ascending: false);

    return (data as List).map((e) => TransactionModel.fromJson(e)).toList();
  }

  List<TransactionModel> get _current => state.value ?? [];

  Future<void> addTransaction(TransactionModel tx) async {
    final user = Supabase.instance.client.auth.currentUser!;
    final data = await Supabase.instance.client
        .from('transactions')
        .insert({...tx.toJson(), 'user_id': user.id})
        .select()
        .single();

    final newTx = TransactionModel.fromJson(data);
    final list = [newTx, ..._current];
    list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    state = AsyncData(list);
  }

  Future<void> updateTransaction(TransactionModel tx) async {
    await Supabase.instance.client
        .from('transactions')
        .update(tx.toJson())
        .eq('id', tx.id);

    final list = [..._current];
    final idx = list.indexWhere((t) => t.id == tx.id);
    if (idx != -1) list[idx] = tx;
    list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    state = AsyncData(list);
  }

  Future<void> deleteTransaction(String id) async {
    await Supabase.instance.client.from('transactions').delete().eq('id', id);
    state = AsyncData(_current.where((t) => t.id != id).toList());
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, List<AccountModel>>(
        AccountsNotifier.new);

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<TransactionModel>>(
        TransactionsNotifier.new);

/// Saldo actual de cada cuenta: saldo inicial + movimientos.
final accountBalancesProvider = Provider<Map<String, double>>((ref) {
  final accounts = ref.watch(accountsProvider).value ?? [];
  final txs = ref.watch(transactionsProvider).value ?? [];

  final balances = {for (final a in accounts) a.id: a.initialBalance};

  for (final tx in txs) {
    switch (tx.type) {
      case TransactionType.income:
        balances.update(tx.accountId, (b) => b + tx.amount, ifAbsent: () => tx.amount);
      case TransactionType.expense:
        balances.update(tx.accountId, (b) => b - tx.amount, ifAbsent: () => -tx.amount);
      case TransactionType.transfer:
        balances.update(tx.accountId, (b) => b - tx.amount, ifAbsent: () => -tx.amount);
        if (tx.transferAccountId != null) {
          balances.update(tx.transferAccountId!, (b) => b + tx.amount, ifAbsent: () => tx.amount);
        }
    }
  }

  return balances;
});

/// Resumen del mes en curso: (ingresos, gastos).
final monthSummaryProvider = Provider<({double income, double expense})>((ref) {
  final txs = ref.watch(transactionsProvider).value ?? [];
  final now = DateTime.now();

  double income = 0;
  double expense = 0;
  for (final tx in txs) {
    if (tx.occurredAt.year != now.year || tx.occurredAt.month != now.month) continue;
    if (tx.type == TransactionType.income) income += tx.amount;
    if (tx.type == TransactionType.expense) expense += tx.amount;
  }

  return (income: income, expense: expense);
});
