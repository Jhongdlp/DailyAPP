import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_model.dart';

enum LibraryLayout {
  grid('Cuadrícula', Icons.grid_view_outlined),
  list('Lista', Icons.view_list_outlined);

  const LibraryLayout(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum LibrarySort {
  recent('Recientes'),
  progress('Progreso'),
  title('Título'),
  added('Añadidos');

  const LibrarySort(this.label);
  final String label;
}

enum LibraryFilter {
  all('Todos'),
  reading('Leyendo'),
  unread('Sin empezar'),
  finished('Terminados');

  const LibraryFilter(this.label);
  final String label;
}

/// Un libro se considera terminado un pelo antes del final: la última página
/// suele ser el colofón o la nota legal, y esperar al 100% exacto haría que
/// casi ningún libro llegara a marcarse.
const kBookFinishedThreshold = 0.98;

extension BookReadingState on Book {
  bool get isFinished => (progressPercent ?? 0) >= kBookFinishedThreshold;
  bool get isStarted => (progressPercent ?? 0) > 0 && !isFinished;
  bool get isUnread => (progressPercent ?? 0) <= 0;
}

class LibraryView {
  final LibraryLayout layout;
  final LibrarySort sort;
  final LibraryFilter filter;

  const LibraryView({
    this.layout = LibraryLayout.grid,
    this.sort = LibrarySort.recent,
    this.filter = LibraryFilter.all,
  });

  LibraryView copyWith({
    LibraryLayout? layout,
    LibrarySort? sort,
    LibraryFilter? filter,
  }) =>
      LibraryView(
        layout: layout ?? this.layout,
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
      );

  Map<String, dynamic> toJson() => {
        'layout': layout.name,
        'sort': sort.name,
        'filter': filter.name,
      };

  factory LibraryView.fromJson(Map<String, dynamic> json) => LibraryView(
        layout: LibraryLayout.values.firstWhere(
          (v) => v.name == json['layout'],
          orElse: () => LibraryLayout.grid,
        ),
        sort: LibrarySort.values.firstWhere(
          (v) => v.name == json['sort'],
          orElse: () => LibrarySort.recent,
        ),
        filter: LibraryFilter.values.firstWhere(
          (v) => v.name == json['filter'],
          orElse: () => LibraryFilter.all,
        ),
      );

  /// Aplica filtro y orden. La búsqueda por texto se resuelve aparte porque es
  /// efímera: no se persiste con el resto de la vista.
  List<Book> apply(List<Book> books) {
    final filtered = [
      for (final book in books)
        if (switch (filter) {
          LibraryFilter.all => true,
          LibraryFilter.reading => book.isStarted,
          LibraryFilter.unread => book.isUnread,
          LibraryFilter.finished => book.isFinished,
        })
          book,
    ];

    filtered.sort(switch (sort) {
      LibrarySort.recent => (a, b) => dateDesc(a.lastOpenedAt, b.lastOpenedAt),
      LibrarySort.added => (a, b) => dateDesc(a.addedAt, b.addedAt),
      LibrarySort.title => (a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      LibrarySort.progress => (a, b) =>
          (b.progressPercent ?? 0).compareTo(a.progressPercent ?? 0),
    });

    return filtered;
  }

  /// Ordena por fecha de más reciente a más antigua dejando los nulos al final.
  static int dateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}

class LibraryViewNotifier extends Notifier<LibraryView> {
  static const _prefsKey = 'library_view';

  @override
  LibraryView build() {
    _load();
    return const LibraryView();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = LibraryView.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Preferencia corrupta: se conserva la vista por defecto
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  void _update(LibraryView next) {
    state = next;
    _persist();
  }

  void toggleLayout() => _update(state.copyWith(
        layout: state.layout == LibraryLayout.grid
            ? LibraryLayout.list
            : LibraryLayout.grid,
      ));

  void setSort(LibrarySort sort) => _update(state.copyWith(sort: sort));

  void setFilter(LibraryFilter filter) => _update(state.copyWith(filter: filter));
}

final libraryViewProvider =
    NotifierProvider<LibraryViewNotifier, LibraryView>(LibraryViewNotifier.new);
