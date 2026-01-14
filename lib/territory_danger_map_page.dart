import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide Marker;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' hide LatLng;

class TerritoryDangerMapPage extends StatelessWidget {
  final String territoryName;
  final List<Map<String, dynamic>> points;

  const TerritoryDangerMapPage({
    super.key,
    required this.territoryName,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};

    LatLng center = const LatLng(-22.9, -43.2);
    if (points.isNotEmpty) {
      final p0 = points.first;
      center = LatLng((p0['lat'] as num).toDouble(), (p0['lng'] as num).toDouble());
    }

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      final desc = (p['desc'] ?? 'Ponto de atenção').toString();

      markers.add(
        Marker(
          markerId: MarkerId("danger_$i"),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: "Atenção", snippet: desc),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Pontos de atenção • $territoryName"),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: center, zoom: 16),
        markers: markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
