import 'package:flutter/material.dart';

/// Gerencia qual moldura Lottie será usada conforme o nível do usuário.
class LevelFrameManager {
  /// Retorna o caminho do arquivo Lottie da moldura conforme o nível.
  static String getFrameForLevel(int level) {
    if (level <= 0) return 'assets/frames/lvl 1.json';
    if (level <= 5) return 'assets/frames/lvl 1.json'; // Bronze
    if (level <= 10) return 'assets/frames/lvl 2.json'; // Prata
    if (level <= 20) return 'assets/frames/lvl 3.json'; // Ouro
    if (level <= 30) return 'assets/frames/lvl 4.json'; // Platina
    if (level <= 40) return 'assets/frames/lvl 5.json'; // Diamante
    if (level <= 50) return 'assets/frames/lvl 6.json'; // Mestre
    return 'assets/frames/lvl 7.json'; // Mestre ou Lendário
  }

  /// Retorna um nome amigável para exibir abaixo do avatar (opcional)
  static String getRankName(int level) {
    if (level <= 5) return 'Bronze';
    if (level <= 10) return 'Prata';
    if (level <= 20) return 'Ouro';
    if (level <= 30) return 'Platina';
    if (level <= 40) return 'Diamante';
    if (level <= 50) return 'Mestre';
    return 'Imperador';
  }
}
