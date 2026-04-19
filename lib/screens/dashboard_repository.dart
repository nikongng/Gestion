import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';

class DashboardRepository {
  Future<List<Map<String, dynamic>>> fetchCollectionsInRange({
    required DateTime from,
    required DateTime to,
    String? communeId,
    String? taxpayerProfileId,
  }) {
    return GestiaDataService.fetchCollectionsInRange(
      from: from,
      to: to,
      communeId: communeId,
      taxpayerProfileId: taxpayerProfileId,
    );
  }

  Future<List<({String id, String name})>> fetchCommunes() {
    return GestiaDataService.fetchCommunes();
  }

  Future<List<UserProfile>> fetchAllProfiles() {
    return GestiaDataService.fetchAllProfiles();
  }

  Future<dynamic> fetchAlertsSummary(UserProfile profile) {
    return GestiaDataService.fetchAlertsSummary(profile);
  }
}
