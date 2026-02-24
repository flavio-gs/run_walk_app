import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class TrainingPlanDetailsPage extends StatefulWidget {
  final String title;
  final String level;
  final String planText;
  final String userId;

  const TrainingPlanDetailsPage({
    super.key,
    required this.title,
    required this.level,
    required this.planText,
    required this.userId,
  });

  @override
  State<TrainingPlanDetailsPage> createState() =>
      _TrainingPlanDetailsPageState();
}

class _TrainingPlanDetailsPageState
    extends State<TrainingPlanDetailsPage> {

  Future<void> _toggleGoal(
      String docId, bool currentState) async {
    await FirebaseFirestore.instance
        .collection("training_goals")
        .doc(docId)
        .update({"isCompleted": !currentState});
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: s.card,
        foregroundColor: s.cardForeground,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            // 🔥 Badge de nível
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: s.secondary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.level,
                style: TextStyle(
                  color: s.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🔥 PLANO BONITO EM MARKDOWN
            Expanded(
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: widget.planText,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                        color: s.foreground,
                        fontSize: 15,
                        height: 1.6),
                    h1: TextStyle(
                        color: s.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                    h2: TextStyle(
                        color: s.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    strong: TextStyle(
                        color: s.primary,
                        fontWeight: FontWeight.bold),
                    listBullet: TextStyle(
                        color: s.accent),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🔥 METAS SALVAS
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("training_goals")
                  .where("userId", isEqualTo: widget.userId)
                  .where("planTitle", isEqualTo: widget.title)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox();
                }

                final goals = snapshot.data!.docs;

                if (goals.isEmpty) {
                  return const SizedBox();
                }

                return Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      "Minhas Metas",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: s.foreground,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...goals.map((doc) {
                      final data =
                      doc.data() as Map<String, dynamic>;
                      final completed =
                          data['isCompleted'] ?? false;
                      final lines =
                      List<String>.from(
                          data['goalLines'] ?? []);

                      return Card(
                        color: completed
                            ? s.secondary
                            .withOpacity(0.2)
                            : s.card,
                        child: ListTile(
                          leading: Checkbox(
                            value: completed,
                            activeColor: s.primary,
                            onChanged: (_) =>
                                _toggleGoal(
                                    doc.id,
                                    completed),
                          ),
                          title: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: lines
                                .map((l) => Text(
                              l,
                              style:
                              TextStyle(
                                decoration:
                                completed
                                    ? TextDecoration
                                    .lineThrough
                                    : null,
                                color: s
                                    .cardForeground,
                              ),
                            ))
                                .toList(),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}