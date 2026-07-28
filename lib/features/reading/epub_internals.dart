/// Tipos internos de `epub_view` que su barril público no reexporta pero que
/// necesitan tanto el lector como sus paneles: `chapterBuilder` entrega
/// `Paragraph`, el índice se construye con `EpubViewChapter` y la posición
/// llega como `EpubChapterViewValue`.
///
/// Se concentran aquí para que el acoplamiento con las tripas del paquete viva
/// en un solo archivo y sea fácil de revisar si el paquete cambia.
library;

// ignore: implementation_imports
export 'package:epub_view/src/data/models/paragraph.dart' show Paragraph;
// ignore: implementation_imports
export 'package:epub_view/src/data/models/chapter.dart'
    show EpubViewChapter, EpubViewSubChapter;
// ignore: implementation_imports
export 'package:epub_view/src/data/models/chapter_view_value.dart'
    show EpubChapterViewValue;
