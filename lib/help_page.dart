import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';


class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final Color orange = const Color(0xFFFF6D00);

  String frameForLevel(int level) {
    if (level <= 0) return 'assets/frames/lvl 1.json';
    if (level <= 5) return 'assets/frames/lvl 1.json'; // Bronze
    if (level <= 10) return 'assets/frames/lvl 2.json'; // Prata
    if (level <= 20) return 'assets/frames/lvl 3.json'; // Ouro
    if (level <= 30) return 'assets/frames/lvl 4.json'; // Platina
    if (level <= 40) return 'assets/frames/lvl 5.json'; // Diamante
    if (level <= 50) return 'assets/frames/lvl 6.json'; // Mestre
    return 'assets/frames/lvl 7.json'; // Imperador (ou Lendário)
  }


  // ====== Interatividade ======
  double _kmSimulador = 5.0;
  bool _isPro = false;

  int _streakDay = 3;

  int _levelSim = 12;

  double _territoryProgress = 0.75; // 0..1
  double _hoursHolding = 3.5;

  // ====== Regras (IGUAL AO CÓDIGO) ======

  int pontosPorCorrida(double km) {
    if (km < 1) return 10;
    if (km < 5) return 25;
    if (km < 10) return 50;
    return 100;
  }

  int pontosBonusDiario(int streak) {
    if (streak >= 5) return 25;
    return 5 * streak;
  }

  int aplicaPro(int base) {
    final mult = _isPro ? 1.2 : 1.0;
    return (base * mult).round();
  }

  /// XP de território (TerritoryService._transferTerritory)
  double xpPorConquistaTerritorio(double progress01) {
    // xpGanho = (progress * 150).clamp(50, 150).toDouble();
    final xp = (progress01 * 150);
    if (xp < 50) return 50;
    if (xp > 150) return 150;
    return xp.toDouble();
  }

  /// XP por tempo de domínio (AchievementService.finalizeTerritoryHold)
  double xpPorTempoDominio(double hours, {double xpPerHour = 5.0}) {
    if (hours <= 0) return 0;
    return hours * xpPerHour;
  }

  /// Level (AchievementService._calculateLevel)
  int levelFromXp(double totalXp) => (totalXp / 500).floor();

  /// Elo (Rank) (igual ao seu snippet)
  static String getRankName(int level) {
    if (level <= 5) return 'Bronze';
    if (level <= 10) return 'Prata';
    if (level <= 20) return 'Ouro';
    if (level <= 30) return 'Platina';
    if (level <= 40) return 'Diamante';
    if (level <= 50) return 'Mestre';
    return 'Imperador';
  }

  String rankEmoji(String rank) {
    switch (rank) {
      case 'Bronze':
        return '🥉';
      case 'Prata':
        return '🥈';
      case 'Ouro':
        return '🥇';
      case 'Platina':
        return '💠';
      case 'Diamante':
        return '💎';
      case 'Mestre':
        return '🏅';
      case 'Imperador':
        return '👑';
      default:
        return '🏁';
    }
  }

  @override
  Widget build(BuildContext context) {
    final corridaBase = pontosPorCorrida(_kmSimulador);
    final corridaFinal = aplicaPro(corridaBase);

    final bonusBase = pontosBonusDiario(_streakDay);
    final bonusFinal = aplicaPro(bonusBase);

    final territoryXp = xpPorConquistaTerritorio(_territoryProgress);
    final holdXp = xpPorTempoDominio(_hoursHolding, xpPerHour: 5.0);

    final rank = getRankName(_levelSim);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Ajuda',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _headerCard(),
          const SizedBox(height: 12),

          // ===== PONTOS =====
          _sectionTitle('🟠 Pontos (Ranking)'),
          const SizedBox(height: 8),
          _pointsCard(
            corridaBase: corridaBase,
            corridaFinal: corridaFinal,
            bonusBase: bonusBase,
            bonusFinal: bonusFinal,
          ),
          const SizedBox(height: 12),

          // ===== XP =====
          _sectionTitle('🔵 XP (Level)'),
          const SizedBox(height: 8),
          _xpCard(
            territoryXp: territoryXp,
            holdXp: holdXp,
          ),
          const SizedBox(height: 12),

          // ===== ELO =====
          _sectionTitle('🏆 Elo (Rank)'),
          const SizedBox(height: 8),
          _eloCard(rank: rank),

          const SizedBox(height: 16),
          _faqCard(),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Como evoluir no Império',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '• Pontos = ranking geral\n'
                '• XP = sobe de nível\n'
                '• Elo = seu rank, definido pelo nível',
            style: TextStyle(color: Colors.black54, height: 1.3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isPro,
                  onChanged: (v) => setState(() => _isPro = v),
                  title: const Text(
                    'Simular Pro Runner',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    '+20% de pontos em corridas e bônus diário',
                    style: TextStyle(color: Colors.black54),
                  ),
                  activeColor: orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pointsCard({
    required int corridaBase,
    required int corridaFinal,
    required int bonusBase,
    required int bonusFinal,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '🏃 Pontos por corrida',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              _isPro ? 'Pro ativo: bônus aplicado' : 'Base + regras de distância',
              style: const TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Row(
                children: [
                  const Text('Distância (km): ', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(_kmSimulador.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w900, color: orange)),
                ],
              ),
              Slider(
                value: _kmSimulador,
                min: 0.2,
                max: 21.0,
                divisions: 208,
                onChanged: (v) => setState(() => _kmSimulador = v),
                activeColor: orange,
              ),
              _ruleRow('Menos de 1km', '10 pts'),
              _ruleRow('1 a 4,9km', '25 pts'),
              _ruleRow('5 a 9,9km', '50 pts'),
              _ruleRow('10km ou mais', '100 pts'),
              const Divider(height: 18),
              _resultRow('Pontos base', '$corridaBase'),
              _resultRow(_isPro ? 'Pontos com Pro (+20%)' : 'Pontos finais', '$corridaFinal'),
            ],
          ),

          const Divider(height: 0),

          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '🔥 Bônus diário (streak)',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Você ganha 1 vez por dia',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Row(
                children: [
                  const Text('Dia da sequência: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('$_streakDay', style: TextStyle(fontWeight: FontWeight.w900, color: orange)),
                ],
              ),
              Slider(
                value: _streakDay.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) => setState(() => _streakDay = v.round()),
                activeColor: orange,
              ),
              _ruleRow('Dia 1', '5 pts'),
              _ruleRow('Dia 2', '10 pts'),
              _ruleRow('Dia 3', '15 pts'),
              _ruleRow('Dia 4', '20 pts'),
              _ruleRow('Dia 5+', '25 pts/dia'),
              const Divider(height: 18),
              _resultRow('Bônus base', '$bonusBase'),
              _resultRow(_isPro ? 'Bônus com Pro (+20%)' : 'Bônus final', '$bonusFinal'),
            ],
          ),

          const Divider(height: 0),

          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '🏆 Conquistas',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Toda conquista desbloqueada dá pontos extras',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: const [
              _Bullet('Cada conquista desbloqueada: +100 pontos'),
              _Bullet('Exemplos: Primeira corrida, 5K, 10K, sequência diária, territórios…'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _xpCard({
    required double territoryXp,
    required double holdXp,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '🏰 XP por conquista de território',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'XP varia conforme o domínio (parcial/total)',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Row(
                children: [
                  const Text('Progresso no território: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('${(_territoryProgress * 100).toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w900, color: orange)),
                ],
              ),
              Slider(
                value: _territoryProgress,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (v) => setState(() => _territoryProgress = v),
                activeColor: orange,
              ),
              const _Bullet('Fórmula atual: XP = clamp(progress × 150, 50, 150)'),
              const SizedBox(height: 6),
              _resultRow('XP estimado', territoryXp.toStringAsFixed(1)),
            ],
          ),

          const Divider(height: 0),

          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '⏱️ XP por tempo de domínio',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Calculado quando o domínio termina',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Row(
                children: [
                  const Text('Horas segurando: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(_hoursHolding.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w900, color: orange)),
                ],
              ),
              Slider(
                value: _hoursHolding,
                min: 0,
                max: 48,
                divisions: 96,
                onChanged: (v) => setState(() => _hoursHolding = v),
                activeColor: orange,
              ),
              const _Bullet('Regra atual: 5 XP por hora (padrão)'),
              const SizedBox(height: 6),
              _resultRow('XP estimado', holdXp.toStringAsFixed(1)),
            ],
          ),

          const Divider(height: 0),

          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '⬆️ Como o Level é calculado',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Seu nível depende do XP total',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: const [
              _Bullet('Level = floor(XP total ÷ 500)'),
              _Bullet('Ou seja: a cada 500 XP, você sobe 1 nível.'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eloCard({required String rank}) {
    final frame = frameForLevel(_levelSim);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '🏆 Seu Elo é definido pelo Level',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Rank muda conforme o seu nível',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              Row(
                children: [
                  const Text('Simular Level: ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('$_levelSim',
                      style: TextStyle(fontWeight: FontWeight.w900, color: orange)),
                ],
              ),
              Slider(
                value: _levelSim.toDouble(),
                min: 0,
                max: 60,
                divisions: 60,
                onChanged: (v) => setState(() => _levelSim = v.round()),
                activeColor: orange,
              ),

              // ✅ Card do Elo + Frame Lottie
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // 🔥 Lottie do Elo (frame)
                    SizedBox(
                      height: 44,
                      width: 70,
                      child: Lottie.asset(
                        frame,
                        repeat: true,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Emoji + Texto
                    Text(rankEmoji(rank), style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Elo atual: $rank',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Desbloqueie frames subindo de nível 🚀',
                            style: const TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    Text(
                      'Lv $_levelSim',
                      style: TextStyle(color: orange, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              const _Bullet('Bronze: Lv 1–5'),
              const _Bullet('Prata: Lv 6–10'),
              const _Bullet('Ouro: Lv 11–20'),
              const _Bullet('Platina: Lv 21–30'),
              const _Bullet('Diamante: Lv 31–40'),
              const _Bullet('Mestre: Lv 41–50'),
              const _Bullet('Imperador: Lv 51+'),

              // ✅ OPCIONAL: mini cards com todos os elos e frames
              // const SizedBox(height: 12),
              // Wrap(
              //   spacing: 10,
              //   runSpacing: 10,
              //   children: [
              //     _eloMini('Bronze', 'assets/frames/lvl 1.json'),
              //     _eloMini('Prata', 'assets/frames/lvl 2.json'),
              //     _eloMini('Ouro', 'assets/frames/lvl 3.json'),
              //     _eloMini('Platina', 'assets/frames/lvl 4.json'),
              //     _eloMini('Diamante', 'assets/frames/lvl 5.json'),
              //     _eloMini('Mestre', 'assets/frames/lvl 6.json'),
              //     _eloMini('Imperador', 'assets/frames/lvl 7.json'),
              //   ],
              // ),
            ],
          ),

          const Divider(height: 0),

          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              '📉 Posso cair de Elo?',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Se houver perda de XP, o Level pode cair',
              style: TextStyle(color: Colors.black54),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: const [
              _Bullet('Se o XP total diminuir, o Level pode diminuir.'),
              _Bullet('Se o Level cair, o Elo também pode cair.'),
              _Bullet('Isso depende das regras competitivas (territórios/disputas).'),
            ],
          ),
        ],
      ),
    );
  }


  Widget _faqCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: const ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: 14),
        title: Text(
          '❓ Perguntas rápidas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          'Tire dúvidas em 10 segundos',
          style: TextStyle(color: Colors.black54),
        ),
        childrenPadding: EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          _QA(
            q: 'Pontos e XP são a mesma coisa?',
            a: 'Não. Pontos contam para ranking e recompensas. XP serve para subir de nível.',
          ),
          _QA(
            q: 'O Pro aumenta meu XP?',
            a: 'Atualmente, o bônus Pro (+20%) é aplicado em Pontos (corrida e bônus diário), não em XP.',
          ),
          _QA(
            q: 'Ganhar conquistas dá o quê?',
            a: 'Toda conquista desbloqueada dá +100 pontos.',
          ),
          _QA(
            q: 'Dominar território dá o quê?',
            a: 'Dá XP baseado no quanto você dominou e pode dar XP por tempo quando o domínio termina.',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
    );
  }

  Widget _ruleRow(String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: const TextStyle(color: Colors.black54))),
          Text(right, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _resultRow(String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(right, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.w900)),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.black87, height: 1.25))),
        ],
      ),
    );
  }
}

class _QA extends StatelessWidget {
  final String q;
  final String a;
  const _QA({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(a, style: const TextStyle(color: Colors.black54, height: 1.25)),
        ],
      ),
    );
  }
}
