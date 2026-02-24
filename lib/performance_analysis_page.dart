import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class PerformanceAnalysisPage extends StatefulWidget {
  final String userId;

  const PerformanceAnalysisPage({super.key, required this.userId});

  @override
  State<PerformanceAnalysisPage> createState() =>
      _PerformanceAnalysisPageState();
}

class _PerformanceAnalysisPageState extends State<PerformanceAnalysisPage> {
  double progress = 0.0;
  bool loading = true;

  List<String> strengths = [];
  List<String> improvements = [];
  String summary = "";

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    try {
      _fakeProgress();

      final snapshot = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      if (snapshot.docs.isEmpty) {
        throw Exception("Sem corridas suficientes.");
      }

      String raceData = "";

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final distanceKm =
            ((data['distance'] as num?)?.toDouble() ?? 0) / 1000.0;

        final durationSeconds =
            (data['duration'] as num?)?.toInt() ?? 0;

        final minutes = durationSeconds ~/ 60;
        final seconds = durationSeconds % 60;

        final pace =
            (data['pace'] as num?)?.toDouble() ?? 0.0;

        final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate();

        raceData +=
        "- ${createdAt?.day}/${createdAt?.month}/${createdAt?.year} | "
            "${distanceKm.toStringAsFixed(2)} km | "
            "${minutes}m ${seconds}s | "
            "Pace ${pace.toStringAsFixed(2)}\n";
      }

      final response = await http.post(
        Uri.parse(
          "https://studio--studio-4298368751-f334d.us-central1.hosted.app/api/analyze-performance",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"raceData": raceData}),
      );

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      final json = jsonDecode(response.body);

      setState(() {
        strengths = List<String>.from(json['strengths'] ?? []);
        improvements = List<String>.from(json['improvements'] ?? []);
        summary = json['summary'] ?? "";
        progress = 1.0;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
        summary = "Erro ao analisar desempenho: $e";
      });
    }
  }

  // Simula progresso enquanto espera API
  void _fakeProgress() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!loading) return false;

      setState(() {
        progress += 0.02;
        if (progress > 0.9) progress = 0.9;
      });

      return loading;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Análise de Performance")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: loading
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Analisando seu perfil...",
              style:
              TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 10),
            Text("${(progress * 100).toInt()}%"),
          ],
        )
            : SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("💪 Pontos Fortes",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              ...strengths.map((e) => Text("• $e")),
              const SizedBox(height: 20),
              const Text("📈 Pontos a Melhorar",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              ...improvements.map((e) => Text("• $e")),
              const SizedBox(height: 20),
              const Text("🧠 Resumo",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Text(summary),
            ],
          ),
        ),
      ),
    );
  }
}