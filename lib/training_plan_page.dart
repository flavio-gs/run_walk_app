import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';
import 'package:run_walk_app/training_plan_details_page.dart';

class TrainingPlanPage extends StatefulWidget {
  final String userId;

  const TrainingPlanPage({super.key, required this.userId});

  @override
  State<TrainingPlanPage> createState() => _TrainingPlanPageState();
}

class _TrainingPlanPageState extends State<TrainingPlanPage> {
  bool loading = false;
  String? generatedPlan;
  String? generatedLevel;

  // =========================
  // GERAR PLANO
  // =========================
  Future<void> _generatePlanWithPrompt(String prompt) async {
    setState(() => loading = true);

    try {
      final response = await http.post(
        Uri.parse(
          "https://studio--studio-4298368751-f334d.us-central1.hosted.app/api/generate-quick-plan",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"prompt": prompt}),
      );

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      final json = jsonDecode(response.body);

      if (json['trainingPlans'] != null &&
          json['trainingPlans'] is List &&
          json['trainingPlans'].isNotEmpty) {
        generatedPlan = json['trainingPlans'][0]['plan'];
        generatedLevel = json['trainingPlans'][0]['level'];
      } else {
        generatedPlan = "Plano não retornado.";
      }

      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao gerar plano: $e")),
      );
    }

    setState(() => loading = false);
  }

  // =========================
  // SELETOR DE META
  // =========================
  Future<void> _selectPlanType() async {
    final TextEditingController customController =
    TextEditingController();
    String selectedLevel = "Iniciante";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final s = SeasonThemeScope.of(context);

            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.75,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: s.card,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: 20,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          children: [

                            // HANDLE
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: s.muted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),

                            const SizedBox(height: 20),

                            Text(
                              "Escolha sua meta",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: s.cardForeground,
                              ),
                            ),

                            const SizedBox(height: 20),

                            DropdownButtonFormField<String>(
                              dropdownColor: s.popover,
                              value: selectedLevel,
                              decoration: InputDecoration(
                                labelText: "Nível do plano",
                                labelStyle:
                                TextStyle(color: s.mutedForeground),
                                filled: true,
                                fillColor: s.input,
                                border: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: s.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: s.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: s.ring),
                                ),
                              ),
                              style:
                              TextStyle(color: s.foreground),
                              items: [
                                "Iniciante",
                                "Intermediário",
                                "Avançado"
                              ]
                                  .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  style: TextStyle(
                                      color: s.foreground),
                                ),
                              ))
                                  .toList(),
                              onChanged: (value) {
                                setModalState(() {
                                  selectedLevel = value!;
                                });
                              },
                            ),

                            const SizedBox(height: 24),

                            _goalButton("Melhorar pace 5K", selectedLevel),
                            _goalButton("Correr 10K", selectedLevel),
                            _goalButton("Emagrecimento", selectedLevel),
                            _goalButton(
                                "Melhorar resistência", selectedLevel),

                            const SizedBox(height: 16),
                            Divider(color: s.border),
                            const SizedBox(height: 16),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Meta personalizada",
                                style: TextStyle(
                                  color: s.foreground,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            TextField(
                              controller: customController,
                              style:
                              TextStyle(color: s.foreground),
                              decoration: InputDecoration(
                                hintText:
                                "Ex: Meia maratona em 6 meses",
                                hintStyle: TextStyle(
                                    color: s.mutedForeground),
                                filled: true,
                                fillColor: s.input,
                                border: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: s.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: s.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                  borderSide:
                                  BorderSide(color: s.ring),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: s.primary,
                                  foregroundColor:
                                  s.primaryForeground,
                                  minimumSize:
                                  const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  if (customController
                                      .text.isNotEmpty) {
                                    Navigator.pop(context);
                                    _generatePlanWithPrompt(
                                      "Crie um plano de treino nível $selectedLevel para: ${customController.text}",
                                    );
                                  }
                                },
                                child: const Text(
                                  "Gerar Plano Personalizado",
                                  style: TextStyle(
                                      fontWeight:
                                      FontWeight.w600),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _goalButton(String goal, String level) {
    final s = SeasonThemeScope.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: s.secondary,
            foregroundColor: s.secondaryForeground,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
            _generatePlanWithPrompt(
              "Crie um plano de treino nível $level detalhado para: $goal",
            );
          },
          child: Text(
            goal,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // =========================
  // SALVAR
  // =========================
  Future<void> _savePlan() async {
    if (generatedPlan == null) return;

    await FirebaseFirestore.instance.collection("training_plans").add({
      "userId": widget.userId,
      "title": "Plano ${DateTime.now().day}/${DateTime.now().month}",
      "level": generatedLevel,
      "planText": generatedPlan,
      "createdAt": FieldValue.serverTimestamp(),
      "isActive": false,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Plano salvo com sucesso!")),
    );
  }

  Future<void> _setActivePlan(String docId) async {
    final batch = FirebaseFirestore.instance.batch();

    final plans = await FirebaseFirestore.instance
        .collection("training_plans")
        .where("userId", isEqualTo: widget.userId)
        .get();

    for (var doc in plans.docs) {
      batch.update(doc.reference, {"isActive": false});
    }

    batch.update(
      FirebaseFirestore.instance
          .collection("training_plans")
          .doc(docId),
      {"isActive": true},
    );

    await batch.commit();
  }

  Future<void> _deletePlan(String docId) async {
    await FirebaseFirestore.instance
        .collection("training_plans")
        .doc(docId)
        .delete();
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return Scaffold(
      backgroundColor: s.background,

      appBar: AppBar(
        title: const Text("Plano de Treino"),
        backgroundColor: s.card,
        foregroundColor: s.cardForeground,
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: s.accent,
        foregroundColor: s.accentForeground,
        onPressed: _selectPlanType,
        child: const Icon(Icons.add),
      ),

      body: loading
          ? Center(
        child: CircularProgressIndicator(
          color: s.accent,
        ),
      )
          : Column(
        children: [

          if (generatedPlan != null)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: MarkdownBody(
                          data: generatedPlan!,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: s.foreground),
                            h1: TextStyle(color: s.primary),
                            h2: TextStyle(color: s.accent),
                            strong: TextStyle(color: s.primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: s.primary,
                          foregroundColor: s.primaryForeground,
                        ),
                        onPressed: _savePlan,
                        child: const Text("Salvar Plano"),
                      ),
                    )
                  ],
                ),
              ),
            ),

          Divider(color: s.border),

          Expanded(
            flex: 3,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "Meus Planos Salvos",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: s.foreground,
                    ),
                  ),
                ),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("training_plans")
                        .where("userId",
                        isEqualTo: widget.userId)
                        .orderBy("createdAt",
                        descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: s.accent,
                          ),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            "Nenhum plano salvo ainda.",
                            style: TextStyle(
                              color: s.mutedForeground,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final data =
                          docs[i].data()
                          as Map<String, dynamic>;

                          final isActive =
                              data['isActive'] ?? false;

                          return Card(
                              color: isActive
                                  ? s.secondary.withOpacity(0.2)
                                  : s.card,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TrainingPlanDetailsPage(
                                        title: data['title'] ?? '',
                                        level: data['level'] ?? '',
                                        planText: data['planText'] ?? '',
                                        userId: widget.userId,
                                      ),
                                    ),
                                  );
                                },
                                child: ListTile(
                              title: Text(
                                "${data['title']} (${data['level'] ?? ''})",
                                style: TextStyle(
                                  color: s.cardForeground,
                                ),
                              ),
                              subtitle: Text(
                                data['planText'] ?? '',
                                maxLines: 3,
                                overflow:
                                TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: s.mutedForeground,
                                ),
                              ),
                              leading: isActive
                                  ? Icon(
                                Icons.star,
                                color: s.accent,
                              )
                                  : null,
                              trailing: Row(
                                mainAxisSize:
                                MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.check,
                                      color: s.primary,
                                    ),
                                    onPressed: () =>
                                        _setActivePlan(
                                            docs[i].id),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: s.destructive,
                                    ),
                                    onPressed: () =>
                                        _deletePlan(
                                            docs[i].id),
                                  ),
                                ],
                              ),
                            ),
                          )
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}