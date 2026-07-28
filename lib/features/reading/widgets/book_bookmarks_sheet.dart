import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/models/book_bookmark_model.dart';
import '../../../core/providers/book_bookmarks_provider.dart';

/// Bottom sheet compartido entre el lector de PDF y el de EPUB: lista los
/// bookmarks del libro y permite crear uno nuevo en la posición actual.
Future<void> showBookBookmarksSheet(
  BuildContext context, {
  required String bookId,
  required String currentPosition,
  required void Function(String position) onJumpTo,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _BookBookmarksSheet(
      bookId: bookId,
      currentPosition: currentPosition,
      onJumpTo: onJumpTo,
    ),
  );
}

class _BookBookmarksSheet extends ConsumerStatefulWidget {
  final String bookId;
  final String currentPosition;
  final void Function(String position) onJumpTo;

  const _BookBookmarksSheet({
    required this.bookId,
    required this.currentPosition,
    required this.onJumpTo,
  });

  @override
  ConsumerState<_BookBookmarksSheet> createState() => _BookBookmarksSheetState();
}

class _BookBookmarksSheetState extends ConsumerState<_BookBookmarksSheet> {
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _addBookmark() async {
    final label = _labelController.text.trim();
    await ref.read(bookBookmarksProvider.notifier).addBookmark(
          widget.bookId,
          widget.currentPosition,
          label: label.isEmpty ? null : label,
        );
    _labelController.clear();
    if (mounted) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bookBookmarksProvider);
    final bookmarks = ref.read(bookBookmarksProvider.notifier).forBook(widget.bookId);

    return NeuCard(
      radius: const BorderRadius.vertical(top: Radius.circular(28)),
      elevation: 22,
      convex: false,
      padding: EdgeInsets.only(
        top: 10,
        left: 20,
        right: 20,
        bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: NeuPressed(
              borderRadius: 3,
              distance: 2,
              blur: 3,
              child: SizedBox(width: 40, height: 5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bookmarks',
            style: GoogleFonts.montserrat(
              color: BentoTheme.cream,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _labelController,
                  style: GoogleFonts.montserrat(color: BentoTheme.cream),
                  decoration: InputDecoration(
                    hintText: 'Nombre del marcador (opcional)',
                    hintStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.4)),
                    filled: true,
                    fillColor: BentoTheme.neuSurfaceSunken,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _addBookmark(),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: _addBookmark,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: BentoTheme.accentPurple.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.bookmark_add_outlined, color: BentoTheme.accentPurple),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Aún no tienes marcadores en este libro.',
                style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5)),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: bookmarks.length,
                separatorBuilder: (context, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) => _bookmarkTile(bookmarks[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bookmarkTile(BookBookmark bookmark) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.bookmark, color: BentoTheme.accentPurple),
      title: Text(
        bookmark.label?.isNotEmpty == true ? bookmark.label! : 'Posición ${bookmark.position}',
        style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: BentoTheme.creamAlpha(0.5)),
        onPressed: () => ref.read(bookBookmarksProvider.notifier).deleteBookmark(bookmark.id),
      ),
      onTap: () {
        Navigator.of(context).pop();
        widget.onJumpTo(bookmark.position);
      },
    );
  }
}
