import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';

class SearchReadingsUseCase {
  const SearchReadingsUseCase(this.readingsRepo);
  final dynamic readingsRepo;

  Future<List<SupabaseReadingWithDetails>> call({
    String? operatorId,
    List<String>? deviceIds, // multi-device filter
    String? readingType,
    int? fromDateMs,
    int? toDateMs,
    int limit = 100,
    int offset = 0,
  }) {
    return readingsRepo.searchReadings(
      operatorId: operatorId,
      deviceIds: deviceIds,
      readingType: readingType,
      fromDateMs: fromDateMs,
      toDateMs: toDateMs,
      limit: limit,
      offset: offset,
    );
  }
}
