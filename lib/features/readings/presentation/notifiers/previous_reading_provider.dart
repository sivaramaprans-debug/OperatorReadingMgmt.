import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/supabase_providers.dart';

typedef PreviousReadingArgs = ({
  String deviceId,
  String readingType,
  int readingDateMs,
  String heatNumber,
});

final previousReadingProvider = FutureProvider.autoDispose.family<SupabaseReading?, PreviousReadingArgs>((ref, args) async {
  if (args.deviceId.isEmpty) return null;
  
  final repo = ref.read(supabaseReadingsRepoProvider);
  return repo.getPreviousReading(
    deviceId: args.deviceId,
    readingType: args.readingType,
    readingDateMs: args.readingDateMs,
    heatNumber: args.heatNumber,
  );
});
