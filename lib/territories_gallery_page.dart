import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:run_walk_app/territory_details_page.dart';

class TerritoriesGalleryPage extends StatelessWidget {
  final String userId;
  final bool isOwner;

  const TerritoriesGalleryPage({
    super.key,
    required this.userId,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('territorios')
        .where('userId', isEqualTo: userId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Territórios conquistados'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                isOwner
                    ? "Você ainda não conquistou territórios."
                    : "Este usuário não tem territórios.",
                style: const TextStyle(color: Colors.black54),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final territoryId = doc.id;

              final title = (data['customName'] ??
                  data['name'] ??
                  data['title'] ??
                  data['territoryName'] ??
                  "Território")
                  .toString();

              final difficulty = (data['difficulty'] is num)
                  ? (data['difficulty'] as num).toInt()
                  : null;

              final safety = (data['safety'] ?? '').toString();

              String subtitle;
              if (safety == 'safe') subtitle = 'Tranquilo';
              else if (safety == 'danger') subtitle = 'Perigoso';
              else if (difficulty != null) subtitle = 'Dificuldade $difficulty/5';
              else subtitle = 'Domínio ativo';

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TerritoryDetailsPage(
                          territoryId: territoryId,
                          isOwner: isOwner,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6D00).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.flag, color: Color(0xFFFF6D00)),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const Row(
                          children: [
                            Icon(Icons.chevron_right, color: Colors.black45),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
