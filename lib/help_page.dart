import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String frameForLevel(int level) {
    if (level <= 0) return 'assets/frames/lvl 1.json';
    if (level <= 5) return 'assets/frames/lvl 1.json'; // Bronze
    if (level <= 10) return 'assets/frames/lvl 2.json'; // Prata
    if (level <= 20) return 'assets/frames/lvl 3.json'; // Ouro
    if (level <= 30) return 'assets/frames/lvl 4.json'; // Platina
    if (level <= 40) return 'assets/frames/lvl 5.json'; // Diamante
    if (level <= 50) return 'assets/frames/lvl 6.json'; // Mestre
    return 'assets/frames/lvl 7.json'; // Imperador
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

  /// Elo (Rank)
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

  Widget _card(SeasonTheme s, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final corridaBase = pontosPorCorrida(_kmSimulador);
    final corridaFinal = aplicaPro(corridaBase);

    final bonusBase = pontosBonusDiario(_streakDay);
    final bonusFinal = aplicaPro(bonusBase);

    final territoryXp = xpPorConquistaTerritorio(_territoryProgress);
    final holdXp = xpPorTempoDominio(_hoursHolding, xpPerHour: 5.0);

    final rank = getRankName(_levelSim);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        backgroundColor: s.background,
        elevation: 0,
        title: Text(
          'Ajuda',
          style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
        ),
        iconTheme: IconThemeData(color: s.foreground),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _headerCard(s),
          const SizedBox(height: 12),

          _sectionTitle(s, '🟠 Pontos (Ranking)'),
          const SizedBox(height: 8),
          _pointsCard(
            s,
            corridaBase: corridaBase,
            corridaFinal: corridaFinal,
            bonusBase: bonusBase,
            bonusFinal: bonusFinal,
          ),
          const SizedBox(height: 12),

          _sectionTitle(s, '🔵 XP (Level)'),
          const SizedBox(height: 8),
          _xpCard(
            s,
            territoryXp: territoryXp,
            holdXp: holdXp,
          ),
          const SizedBox(height: 12),

          _sectionTitle(s, '🏆 Elo (Rank)'),
          const SizedBox(height: 8),
          _eloCard(s, rank: rank),

          const SizedBox(height: 16),
          _faqCard(s),
        ],
      ),
    );
  }

  Widget _headerCard(SeasonTheme s) {
    return _card(
      s,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como evoluir no Império',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: s.cardForeground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '• Pontos = ranking geral\n'
                  '• XP = sobe de nível\n'
                  '• Elo = seu rank, definido pelo nível',
              style: TextStyle(color: s.mutedForeground, height: 1.3),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isPro,
              onChanged: (v) => setState(() => _isPro = v),
              title: Text(
                'Simular Pro Runner',
                style: TextStyle(fontWeight: FontWeight.w800, color: s.cardForeground),
              ),
              subtitle: Text(
                '+20% de pontos em corridas e bônus diário',
                style: TextStyle(color: s.mutedForeground),
              ),
              activeColor: s.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pointsCard(
      SeasonTheme s, {
        required int corridaBase,
        required int corridaFinal,
        required int bonusBase,
        required int bonusFinal,
      }) {
    return _card(
      s,
      child: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '🏃 Pontos por corrida',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                _isPro ? 'Pro ativo: bônus aplicado' : 'Base + regras de distância',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Row(
                  children: [
                    Text('Distância (km): ', style: TextStyle(fontWeight: FontWeight.w700, color: s.cardForeground)),
                    Text(
                      _kmSimulador.toStringAsFixed(1),
                      style: TextStyle(fontWeight: FontWeight.w900, color: s.primary),
                    ),
                  ],
                ),
                Slider(
                  value: _kmSimulador,
                  min: 0.2,
                  max: 21.0,
                  divisions: 208,
                  onChanged: (v) => setState(() => _kmSimulador = v),
                  activeColor: s.primary,
                  inactiveColor: s.muted.withOpacity(0.75),
                ),
                _ruleRow(s, 'Menos de 1km', '10 pts'),
                _ruleRow(s, '1 a 4,9km', '25 pts'),
                _ruleRow(s, '5 a 9,9km', '50 pts'),
                _ruleRow(s, '10km ou mais', '100 pts'),
                Divider(height: 18, color: s.border),
                _resultRow(s, 'Pontos base', '$corridaBase'),
                _resultRow(s, _isPro ? 'Pontos com Pro (+20%)' : 'Pontos finais', '$corridaFinal'),
              ],
            ),
          ),
          Divider(height: 0, color: s.border),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '🔥 Bônus diário (streak)',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'Você ganha 1 vez por dia',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Row(
                  children: [
                    Text('Dia da sequência: ', style: TextStyle(fontWeight: FontWeight.w700, color: s.cardForeground)),
                    Text(
                      '$_streakDay',
                      style: TextStyle(fontWeight: FontWeight.w900, color: s.primary),
                    ),
                  ],
                ),
                Slider(
                  value: _streakDay.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) => setState(() => _streakDay = v.round()),
                  activeColor: s.primary,
                  inactiveColor: s.muted.withOpacity(0.75),
                ),
                _ruleRow(s, 'Dia 1', '5 pts'),
                _ruleRow(s, 'Dia 2', '10 pts'),
                _ruleRow(s, 'Dia 3', '15 pts'),
                _ruleRow(s, 'Dia 4', '20 pts'),
                _ruleRow(s, 'Dia 5+', '25 pts/dia'),
                Divider(height: 18, color: s.border),
                _resultRow(s, 'Bônus base', '$bonusBase'),
                _resultRow(s, _isPro ? 'Bônus com Pro (+20%)' : 'Bônus final', '$bonusFinal'),
              ],
            ),
          ),
          Divider(height: 0, color: s.border),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '🏆 Conquistas',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'Toda conquista desbloqueada dá pontos extras',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: const [
                _Bullet('Cada conquista desbloqueada: +100 pontos'),
                _Bullet('Exemplos: Primeira corrida, 5K, 10K, sequência diária, territórios…'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _xpCard(
      SeasonTheme s, {
        required double territoryXp,
        required double holdXp,
      }) {
    return _card(
      s,
      child: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '🏰 XP por conquista de território',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'XP varia conforme o domínio (parcial/total)',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Row(
                  children: [
                    Text('Progresso no território: ', style: TextStyle(fontWeight: FontWeight.w700, color: s.cardForeground)),
                    Text(
                      '${(_territoryProgress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontWeight: FontWeight.w900, color: s.primary),
                    ),
                  ],
                ),
                Slider(
                  value: _territoryProgress,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  onChanged: (v) => setState(() => _territoryProgress = v),
                  activeColor: s.primary,
                  inactiveColor: s.muted.withOpacity(0.75),
                ),
                const _Bullet('Fórmula atual: XP = clamp(progress × 150, 50, 150)'),
                const SizedBox(height: 6),
                _resultRow(s, 'XP estimado', territoryXp.toStringAsFixed(1)),
              ],
            ),
          ),
          Divider(height: 0, color: s.border),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '⏱️ XP por tempo de domínio',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'Calculado quando o domínio termina',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Row(
                  children: [
                    Text('Horas segurando: ', style: TextStyle(fontWeight: FontWeight.w700, color: s.cardForeground)),
                    Text(
                      _hoursHolding.toStringAsFixed(1),
                      style: TextStyle(fontWeight: FontWeight.w900, color: s.primary),
                    ),
                  ],
                ),
                Slider(
                  value: _hoursHolding,
                  min: 0,
                  max: 48,
                  divisions: 96,
                  onChanged: (v) => setState(() => _hoursHolding = v),
                  activeColor: s.primary,
                  inactiveColor: s.muted.withOpacity(0.75),
                ),
                const _Bullet('Regra atual: 5 XP por hora (padrão)'),
                const SizedBox(height: 6),
                _resultRow(s, 'XP estimado', holdXp.toStringAsFixed(1)),
              ],
            ),
          ),
          Divider(height: 0, color: s.border),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '⬆️ Como o Level é calculado',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'Seu nível depende do XP total',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: const [
                _Bullet('Level = floor(XP total ÷ 500)'),
                _Bullet('Ou seja: a cada 500 XP, você sobe 1 nível.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eloCard(SeasonTheme s, {required String rank}) {
    final frame = frameForLevel(_levelSim);

    return _card(
      s,
      child: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '🏆 Seu Elo é definido pelo Level',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'Rank muda conforme o seu nível',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Row(
                  children: [
                    Text('Simular Level: ', style: TextStyle(fontWeight: FontWeight.w700, color: s.cardForeground)),
                    Text('$_levelSim', style: TextStyle(fontWeight: FontWeight.w900, color: s.primary)),
                  ],
                ),
                Slider(
                  value: _levelSim.toDouble(),
                  min: 0,
                  max: 60,
                  divisions: 60,
                  onChanged: (v) => setState(() => _levelSim = v.round()),
                  activeColor: s.primary,
                  inactiveColor: s.muted.withOpacity(0.75),
                ),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: s.muted.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: s.border),
                  ),
                  child: Row(
                    children: [
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

                      Text(rankEmoji(rank), style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Elo atual: $rank',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: s.cardForeground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Desbloqueie frames subindo de nível 🚀',
                              style: TextStyle(color: s.mutedForeground, fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      Text(
                        'Lv $_levelSim',
                        style: TextStyle(color: s.primary, fontWeight: FontWeight.w900),
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
              ],
            ),
          ),

          Divider(height: 0, color: s.border),

          Theme(
            data: Theme.of(context).copyWith(dividerColor: s.border),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              collapsedIconColor: s.mutedForeground,
              iconColor: s.foreground,
              title: Text(
                '📉 Posso cair de Elo?',
                style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
              ),
              subtitle: Text(
                'Se houver perda de XP, o Level pode cair',
                style: TextStyle(color: s.mutedForeground),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: const [
                _Bullet('Se o XP total diminuir, o Level pode diminuir.'),
                _Bullet('Se o Level cair, o Elo também pode cair.'),
                _Bullet('Isso depende das regras competitivas (territórios/disputas).'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faqCard(SeasonTheme s) {
    return _card(
      s,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: s.border),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          collapsedIconColor: s.mutedForeground,
          iconColor: s.foreground,
          title: Text(
            '❓ Perguntas rápidas',
            style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground),
          ),
          subtitle: Text(
            'Tire dúvidas em 10 segundos',
            style: TextStyle(color: s.mutedForeground),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: const [
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
      ),
    );
  }

  Widget _sectionTitle(SeasonTheme s, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: s.foreground,
      ),
    );
  }

  Widget _ruleRow(SeasonTheme s, String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: TextStyle(color: s.mutedForeground))),
          Text(right, style: TextStyle(fontWeight: FontWeight.w800, color: s.cardForeground)),
        ],
      ),
    );
  }

  Widget _resultRow(SeasonTheme s, String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: TextStyle(fontWeight: FontWeight.w800, color: s.cardForeground))),
          Text(right, style: TextStyle(fontWeight: FontWeight.w900, color: s.foreground)),
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
    final s = SeasonThemeScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: s.foreground, height: 1.25),
            ),
          ),
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
    final s = SeasonThemeScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: TextStyle(fontWeight: FontWeight.w900, color: s.cardForeground)),
          const SizedBox(height: 4),
          Text(a, style: TextStyle(color: s.mutedForeground, height: 1.25)),
        ],
      ),
    );
  }
}
