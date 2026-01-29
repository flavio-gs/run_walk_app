import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProPlansPage extends StatelessWidget {
  const ProPlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final plans = [
      {
        'name': 'Pro Lite',
        'price': 'R\$ 14,90/mês',
        'color': const Color(0xFF4A90E2),
        'emoji': '🥈',
        'features': [
          'Sem anúncios',
          'Análises avançadas',
          'Relatórios semanais',
          'Personalização do avatar'
        ]
      },
      {
        'name': 'Pro Max',
        'price': 'R\$ 24,90/mês',
        'color': const Color(0xFFFFC400),
        'emoji': '🥇',
        'features': [
          'Tudo do Lite +',
          'Radar de Conquista',
          'Domínio 2× mais duradouro',
          'Ranking e clubes exclusivos',
          'Alertas de disputa em tempo real'
        ]
      },
      {
        'name': 'Pro Elite (Anual)',
        'price': 'R\$ 199,90/ano',
        'color': const Color(0xFF8E24AA),
        'emoji': '👑',
        'features': [
          'Todos os recursos',
          'Título “Fundador Pro Runner”',
          'Acesso antecipado a funções Beta',
          'Descontos com parceiros'
        ]
      },
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFFFD740), Color(0xFFFFAB00)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(bounds),
              child: const Icon(Icons.bolt_rounded,
                  color: Colors.white, size: 30, shadows: [
                    Shadow(
                        blurRadius: 18,
                        color: Colors.amberAccent,
                        offset: Offset(0, 0))
                  ]),
            ),
            const SizedBox(width: 6),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                "Planos Pro",
                style: GoogleFonts.russoOne(
                    textStyle: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.4,
                        shadows: [
                          Shadow(
                              blurRadius: 14,
                              color: Colors.black45,
                              offset: Offset(2, 2))
                        ])),
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF002171)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 40),
          itemCount: plans.length,
          itemBuilder: (context, i) {
            final p = plans[i];
            return _buildPlanCard(context, p);
          },
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, Map<String, dynamic> plan) {
    final Color color = plan['color'];
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24, width: 1.2),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.25),
            Colors.black.withOpacity(0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('${plan['emoji']} ${plan['name']}',
                    style: GoogleFonts.russoOne(
                        fontSize: 22, color: Colors.white)),
                const SizedBox(height: 8),
                Text(plan['price'],
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (plan['features'] as List<String>)
                      .map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(f,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14)),
                        )
                      ],
                    ),
                  ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 50, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Assinatura de ${plan['name']} em breve!'),
                    ));
                  },
                  child: const Text(
                    'Assinar agora',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
