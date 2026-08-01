import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import '../services/cache_service.dart';
import '../services/outbox_service.dart';
import '../services/synced_write.dart';

/// Fila completa tal y como la devolvería el servidor.
///
/// Los `toJson()` de los modelos omiten `id`, `user_id` y `created_at` porque
/// hasta ahora los ponía Supabase al insertar. Sin conexión eso no vale: la
/// fila tiene que estar entera desde el principio para poder pintarla, guardarla
/// en caché y reconciliarla cuando el servidor responda.
Map<String, dynamic> _accountRow(AccountModel a) => {
      'id': a.id,
      'user_id': a.userId,
      'created_at': a.createdAt.toIso8601String(),
      ...a.toJson(),
    };

Map<String, dynamic> _transactionRow(TransactionModel t) => {
      'id': t.id,
      'user_id': t.userId,
      'created_at': t.createdAt.toIso8601String(),
      ...t.toJson(),
    };

class AccountsNotifier extends AsyncNotifier<List<AccountModel>> {
  @override
  Future<List<AccountModel>> build() async {
    final cached = await _readCache();
    if (cached != null) {
      // Pintar el último estado conocido al instante y refrescar por detrás:
      // abrir finanzas en el metro ya no deja la pantalla en blanco.
      unawaited(_refresh());
      return cached;
    }
    return _fetch();
  }

  List<AccountModel> get _current => state.value ?? [];

  Future<List<AccountModel>?> _readCache() async {
    try {
      final cached = await CacheService.read('accounts');
      if (cached is! List) return null;
      return cached
          .map((e) => AccountModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<AccountModel>> _fetch() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('accounts')
        .select()
        .order('created_at');

    final rows = OutboxService.reconcileRows(
      [for (final row in data as List) Map<String, dynamic>.from(row as Map)],
      await OutboxService.pendingFor('accounts'),
    );

    final accounts = rows.map(AccountModel.fromJson).toList();
    unawaited(CacheService.save('accounts', rows));
    return accounts;
  }

  Future<void> _refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (_) {
      // Sin red nos quedamos con la caché que ya está en pantalla.
    }
  }

  void _persist() => unawaited(
        CacheService.save('accounts', _current.map(_accountRow).toList()),
      );

  Future<void> addAccount(AccountModel account) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final local = account.withIdentity(
      id: newRowId(),
      userId: user.id,
      createdAt: DateTime.now(),
    );

    state = AsyncData([..._current, local]);
    _persist();

    final payload = _accountRow(local);
    await syncedWrite(
      write: () => Supabase.instance.client.from('accounts').insert(payload),
      fallback: () => OutboxOp.create(
        table: 'accounts',
        kind: OutboxOpKind.insert,
        payload: payload,
        match: {'id': local.id},
      ),
    );
  }

  Future<void> updateAccount(AccountModel account) async {
    final list = [..._current];
    final idx = list.indexWhere((a) => a.id == account.id);
    if (idx != -1) list[idx] = account;
    state = AsyncData(list);
    _persist();

    if (!canWriteToSupabase) return;

    final payload = account.toJson();
    await syncedWrite(
      write: () => Supabase.instance.client
          .from('accounts')
          .update(payload)
          .eq('id', account.id),
      fallback: () => OutboxOp.create(
        table: 'accounts',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': account.id},
      ),
    );
  }

  Future<void> deleteAccount(String id) async {
    state = AsyncData(_current.where((a) => a.id != id).toList());
    _persist();

    // En la base de datos las transacciones caen en cascada, pero sin conexión
    // esa cascada no ocurre: hay que reproducirla en local o quedarían
    // movimientos huérfanos apuntando a una cuenta que ya no se ve.
    ref.read(transactionsProvider.notifier).dropAccountLocally(id);

    if (!canWriteToSupabase) return;

    await syncedWrite(
      write: () => Supabase.instance.client.from('accounts').delete().eq('id', id),
      fallback: () => OutboxOp.create(
        table: 'accounts',
        kind: OutboxOpKind.delete,
        match: {'id': id},
      ),
    );
  }
}

class TransactionsNotifier extends AsyncNotifier<List<TransactionModel>> {
  @override
  Future<List<TransactionModel>> build() async {
    final cached = await _readCache();
    if (cached != null) {
      unawaited(_refresh());
      return cached;
    }
    return _fetch();
  }

  List<TransactionModel> get _current => state.value ?? [];

  Future<List<TransactionModel>?> _readCache() async {
    try {
      final cached = await CacheService.read('transactions');
      if (cached is! List) return null;
      return cached
          .map((e) => TransactionModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<TransactionModel>> _fetch() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('transactions')
        .select()
        .order('occurred_at', ascending: false)
        .order('created_at', ascending: false);

    final rows = OutboxService.reconcileRows(
      [for (final row in data as List) Map<String, dynamic>.from(row as Map)],
      await OutboxService.pendingFor('transactions'),
    );

    final txs = rows.map(TransactionModel.fromJson).toList()..sort(_byDateDesc);
    unawaited(CacheService.save('transactions', rows));
    return txs;
  }

  Future<void> _refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (_) {}
  }

  static int _byDateDesc(TransactionModel a, TransactionModel b) {
    final byOccurred = b.occurredAt.compareTo(a.occurredAt);
    return byOccurred != 0 ? byOccurred : b.createdAt.compareTo(a.createdAt);
  }

  void _persist() => unawaited(
        CacheService.save('transactions', _current.map(_transactionRow).toList()),
      );

  Future<void> addTransaction(TransactionModel tx) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final local = tx.withIdentity(
      id: newRowId(),
      userId: user.id,
      // Se respeta la fecha que trae el modelo si ya venía puesta: la captura
      // rápida vuelca movimientos con la fecha del día en que se anotaron.
      createdAt: tx.createdAt,
    );

    state = AsyncData([local, ..._current]..sort(_byDateDesc));
    _persist();

    final payload = _transactionRow(local);
    await syncedWrite(
      write: () => Supabase.instance.client.from('transactions').insert(payload),
      fallback: () => OutboxOp.create(
        table: 'transactions',
        kind: OutboxOpKind.insert,
        payload: payload,
        match: {'id': local.id},
      ),
    );
  }

  Future<void> updateTransaction(TransactionModel tx) async {
    final list = [..._current];
    final idx = list.indexWhere((t) => t.id == tx.id);
    if (idx != -1) list[idx] = tx;
    state = AsyncData(list..sort(_byDateDesc));
    _persist();

    if (!canWriteToSupabase) return;

    final payload = tx.toJson();
    await syncedWrite(
      write: () => Supabase.instance.client
          .from('transactions')
          .update(payload)
          .eq('id', tx.id),
      fallback: () => OutboxOp.create(
        table: 'transactions',
        kind: OutboxOpKind.update,
        payload: payload,
        match: {'id': tx.id},
      ),
    );
  }

  Future<void> deleteTransaction(String id) async {
    state = AsyncData(_current.where((t) => t.id != id).toList());
    _persist();

    if (!canWriteToSupabase) return;

    await syncedWrite(
      write: () =>
          Supabase.instance.client.from('transactions').delete().eq('id', id),
      fallback: () => OutboxOp.create(
        table: 'transactions',
        kind: OutboxOpKind.delete,
        match: {'id': id},
      ),
    );
  }

  /// Quita de la vista los movimientos de una cuenta borrada. No encola nada:
  /// la cascada la hace la base de datos cuando el borrado de la cuenta llegue.
  void dropAccountLocally(String accountId) {
    state = AsyncData(
      _current
          .where((t) => t.accountId != accountId && t.transferAccountId != accountId)
          .toList(),
    );
    _persist();
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
