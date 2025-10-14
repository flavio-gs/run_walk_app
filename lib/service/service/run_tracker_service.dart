import 'dart:async';
import 'package:geolocator/geolocator.dart';

class RunTrackerService {
  StreamSubscription<Position>? _positionSubscription;

  /// Stream pública de posições
  Stream<Position> get positionStream => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // só atualiza se mover 5 metros
        ),
      );

  /// Inicia o rastreamento
  Future<void> start(Function(Position) onPosition) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Serviço de localização desativado.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissão de localização negada.');
      }
    }

    // Inicia stream de posições
    _positionSubscription = positionStream.listen(onPosition);
  }

  /// Para o rastreamento
  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Libera recursos
  void dispose() {
    stop();
  }
}
