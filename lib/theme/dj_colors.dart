import 'package:flutter/material.dart';
import '../services/audio_service.dart';

/// Club-style palette: near-black panels with one neon color per deck.
class DjColors {
  static const background = Color(0xFF0B0B0F);
  static const panel = Color(0xFF16161C);
  static const panelHigh = Color(0xFF23232B);
  static const textDim = Color(0xFF8A8A96);
  static const djBackground = Color(0xFF26262C); // DJ mode's charcoal
  static const button = Color(0xFF1C1C21);
  static const deckA = Color(0xFF19C3FF); // left deck: electric blue
  static const deckB = Color(0xFFFF7A1A); // right deck: orange

  static Color forDeck(DeckId id) => id == DeckId.left ? deckA : deckB;
  static String letter(DeckId id) => id == DeckId.left ? 'A' : 'B';
}
