import 'package:flutter/material.dart';

/// Catálogo de cosméticos comprables con oro.
///
/// Los sprites son overlays sobre el grid 22x20 del héroe y se dibujan
/// DETRÁS del sprite para no romper ninguna silueta. Las auras no tienen
/// sprite: el painter dibuja chispas animadas con [auraColor].
class CosmeticDef {
  final String id;
  final String name;
  final String description;
  final String slot; // 'halo' | 'back' | 'pet' | 'aura'
  final int price;
  final List<String> sprite;
  final Map<String, Color> palette;
  final Color? auraColor;

  const CosmeticDef({
    required this.id,
    required this.name,
    required this.description,
    required this.slot,
    required this.price,
    this.sprite = const [],
    this.palette = const {},
    this.auraColor,
  });
}

const String slotHalo = 'halo';
const String slotBack = 'back';
const String slotPet = 'pet';
const String slotAura = 'aura';

String cosmeticSlotLabel(String slot) {
  switch (slot) {
    case slotHalo:
      return 'Halo';
    case slotBack:
      return 'Alas';
    case slotPet:
      return 'Mascota';
    case slotAura:
      return 'Aura';
    default:
      return slot;
  }
}

const List<CosmeticDef> cosmeticCatalog = [
  CosmeticDef(
    id: 'halo_gold',
    name: 'Halo Dorado',
    description: 'Un aro de pura virtud.',
    slot: slotHalo,
    price: 250,
    palette: {
      'g': Color(0xFFFFD75E),
      'x': Color(0xFFFFF3C4),
    },
    sprite: [
      ".........gxgg.........",
      "........g....g........",
    ],
  ),
  CosmeticDef(
    id: 'pet_slime',
    name: 'Slime Compañero',
    description: 'Te sigue a todas partes.',
    slot: slotPet,
    price: 300,
    palette: {
      'a': Color(0xFF7ED957),
      'A': Color(0xFF4FA332),
      'e': Color(0xFF2E2440),
      'x': Color(0xFFD7F5C4),
    },
    sprite: [
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      ".................axa..",
      "................aaaaa.",
      "................aeaea.",
      "................aAAAa.",
    ],
  ),
  CosmeticDef(
    id: 'pet_cat',
    name: 'Gato Sombra',
    description: 'Independiente, como tú.',
    slot: slotPet,
    price: 550,
    palette: {
      'a': Color(0xFF4A4458),
      'A': Color(0xFF332E40),
      'g': Color(0xFFFFD75E),
    },
    sprite: [
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "................a..a..",
      "................aaaa..",
      "................agga..",
      "................aaaa..",
      "................aaaaA.",
      "...............AaaaA..",
    ],
  ),
  CosmeticDef(
    id: 'aura_arcana',
    name: 'Aura Arcana',
    description: 'Chispas de poder puro.',
    slot: slotAura,
    price: 700,
    auraColor: Color(0xFFB18CFF),
  ),
  CosmeticDef(
    id: 'aura_fire',
    name: 'Aura Ígnea',
    description: 'El calor de la constancia.',
    slot: slotAura,
    price: 700,
    auraColor: Color(0xFFF5923E),
  ),
  CosmeticDef(
    id: 'wings_angel',
    name: 'Alas Celestes',
    description: 'Plumas de un guardián.',
    slot: slotBack,
    price: 800,
    palette: {
      'b': Color(0xFFF2EFE9),
      'B': Color(0xFFC8C2B4),
    },
    sprite: [
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "..bb..............bb..",
      ".bbbb............bbbb.",
      ".bbbbb..........bbbbb.",
      "..bbbb..........bbbb..",
      "..Bbbb..........bbbB..",
      "...Bbb..........bbB...",
      "....Bb..........bB....",
      ".....B..........B.....",
    ],
  ),
  CosmeticDef(
    id: 'wings_fire',
    name: 'Alas de Fénix',
    description: 'Arden pero no queman.',
    slot: slotBack,
    price: 1000,
    palette: {
      'b': Color(0xFFF5923E),
      'B': Color(0xFFD9532B),
      'x': Color(0xFFFFD75E),
    },
    sprite: [
      "......................",
      "......................",
      "......................",
      "......................",
      "..x................x..",
      "..bx..............xb..",
      ".xbbb............bbbx.",
      ".bbbbb..........bbbbb.",
      "..bbbb..........bbbb..",
      "..Bbbb..........bbbB..",
      "...BbB..........BbB...",
      "....BB..........BB....",
      ".....B..........B.....",
    ],
  ),
  CosmeticDef(
    id: 'pet_dragon',
    name: 'Dragón Bebé',
    description: 'Algún día será enorme.',
    slot: slotPet,
    price: 1500,
    palette: {
      'a': Color(0xFFD9532B),
      'A': Color(0xFFA33A1E),
      'w': Color(0xFFF5923E),
      'e': Color(0xFFFFD75E),
      'x': Color(0xFFFFF3C4),
    },
    sprite: [
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      "......................",
      ".................aae..",
      ".................aaaa.",
      "...............w.aa...",
      "..............wwaaaa..",
      "..............wwaaaaa.",
      "...............aaaa.A.",
      "...............A..A...",
    ],
  ),
];

CosmeticDef? cosmeticById(String id) {
  for (final c in cosmeticCatalog) {
    if (c.id == id) return c;
  }
  return null;
}
