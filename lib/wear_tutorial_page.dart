import 'package:flutter/material.dart';
import 'package:run_walk_app/run_tracker_wear.dart';
import 'package:run_walk_app/widgets/main_scaffold_wear.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_walk_app/widgets/main_scaffold.dart';

class WearTextTutorialPage extends StatefulWidget {
  const WearTextTutorialPage({super.key});

  @override
  State<WearTextTutorialPage> createState() => _WearTextTutorialPageState();
}

class _WearTextTutorialPageState extends State<WearTextTutorialPage> {
  int _step = 0;

  final List<Map<String, String>> steps = [
    {
      'title': '🌎 Empire of The Run',
      'text':
      'Transforme suas corridas em conquistas reais! Cada trajeto vira território dominado no mapa.'
    },
    {
      'title': '🏃 Crie seu trajeto',
      'text':
      'Enquanto corre, o app registra seu percurso. Feche voltas e conquiste áreas para ganhar XP.'
    },
    {
      'title': '🔥 Suba de nível',
      'text':
      'Cada território rende XP e desbloqueia molduras exclusivas (Elos) que mostram sua evolução.'
    },
    {
      'title': '⚔️ Defenda seu império',
      'text':
      'Outros corredores podem invadir suas áreas! Corra para proteger seu domínio e reconquistar espaço.'
    },
    {
      'title': '🏅 Explore e Conecte-se',
      'text':
      'Siga outros corredores, entre em clãs e participe de desafios globais. Seu império te espera!'
    },
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenTutorial', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScaffoldWear()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        steps[_step]['title']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        steps[_step]['text']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text(
                        "◀",
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                      ),
                    ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () async {
                      if (_step < steps.length - 1) {
                        setState(() => _step++);
                      } else {
                        await _finish();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _step == steps.length - 1 ? "Ir ▶" : "Avançar ▶",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
