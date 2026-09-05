import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import '../../../../database/supabase_client.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../domain/models/log_sheet_entry.dart';

class SupabaseLogSheetRepository {
  static const _table = 'log_sheets';
  static const _bucket = 'log_sheets';
  final _uuid = const Uuid();

  /// Fetch log sheet records with optional filters.
  Future<List<LogSheetEntry>> getAll({
    String? operatorId,
    String? section,
    String? workType,
    int? fromDateMs,
    int? toDateMs,
    int limit = 200,
  }) async {
    try {
      var query = supabase.from(_table).select();

      if (operatorId != null && operatorId.isNotEmpty) {
        query = query.eq('operator_id', operatorId);
      }
      if (section != null && section.isNotEmpty && section != 'All') {
        query = query.eq('section', section);
      }
      if (workType != null && workType.isNotEmpty && workType != 'All') {
        query = query.eq('work_type', workType);
      }
      if (fromDateMs != null) {
        query = query.gte('log_date', fromDateMs);
      }
      if (toDateMs != null) {
        query = query.lte('log_date', toDateMs);
      }

      final data = await query.order('log_date', ascending: false).limit(limit);
      return (data as List)
          .map((m) => LogSheetEntry.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LogSheetRepository.getAll error: $e');
      return [];
    }
  }

  /// Insert a new log entry.
  Future<String> insert({
    required String operatorId,
    required String operatorName,
    required String section,
    required int logDate,
    required String workType,
    required String equipmentType,
    required String description,
    String? imageUrl,
  }) async {
    final id = _uuid.v4();
    final now = AppDateUtils.nowUtcMs();

    await supabase.from(_table).insert({
      'id': id,
      'operator_id': operatorId,
      'operator_name': operatorName,
      'section': section,
      'log_date': logDate,
      'work_type': workType,
      'equipment_type': equipmentType,
      'description': description,
      'image_url': imageUrl,
      'created_at': now,
    });

    return id;
  }

  /// Delete a log entry by ID.
  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }

  /// Compress an image down to max 1024px and 70% JPEG quality, then upload to Supabase Storage.
  /// Free tier capacity: compresses a 5MB photo to ~80-120KB (1GB holds >10,000 photos).
  Future<String?> compressAndUploadImage(Uint8List rawBytes) async {
    try {
      // Decode image
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      // Downscale if larger than 1024 on either dimension
      img.Image resized = decoded;
      const maxDim = 1024;
      if (decoded.width > maxDim || decoded.height > maxDim) {
        if (decoded.width >= decoded.height) {
          resized = img.copyResize(decoded, width: maxDim);
        } else {
          resized = img.copyResize(decoded, height: maxDim);
        }
      }

      // Encode to JPEG with 70% quality (~80-120 KB)
      final compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));

      final fileId = _uuid.v4();
      final path = 'logs/$fileId.jpg';

      // Upload to bucket
      await supabase.storage.from(_bucket).uploadBinary(
            path,
            compressedBytes,
          );

      // Get public URL
      final publicUrl = supabase.storage.from(_bucket).getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('compressAndUploadImage error: $e');
      return null;
    }
  }

  /// Get distinct equipment names previously recorded for auto-completion.
  Future<List<String>> getEquipmentSuggestions(String section) async {
    try {
      final data = await supabase
          .from(_table)
          .select('equipment_type')
          .eq('section', section)
          .limit(100);

      final set = <String>{};
      for (final row in data) {
        final eq = (row['equipment_type'] as String?)?.trim();
        if (eq != null && eq.isNotEmpty) {
          set.add(eq);
        }
      }
      return set.toList();
    } catch (_) {
      return [];
    }
  }

  /// Get distinct sections previously recorded.
  Future<List<String>> getSectionSuggestions() async {
    try {
      final data = await supabase
          .from(_table)
          .select('section')
          .limit(200);

      final set = <String>{};
      for (final row in data) {
        final s = (row['section'] as String?)?.trim();
        if (s != null && s.isNotEmpty) {
          set.add(s);
        }
      }
      return set.toList();
    } catch (_) {
      return [];
    }
  }

  /// Get distinct work types previously recorded.
  Future<List<String>> getWorkTypeSuggestions() async {
    try {
      final data = await supabase
          .from(_table)
          .select('work_type')
          .limit(200);

      final set = <String>{};
      for (final row in data) {
        final wt = (row['work_type'] as String?)?.trim();
        if (wt != null && wt.isNotEmpty) {
          set.add(wt);
        }
      }
      return set.toList();
    } catch (_) {
      return [];
    }
  }
}

final supabaseLogSheetRepoProvider =
    Provider<SupabaseLogSheetRepository>((ref) => SupabaseLogSheetRepository());

final logSheetsListProvider = FutureProvider.autoDispose
    .family<List<LogSheetEntry>, ({String? operatorId, String? section, String? workType})>((ref, args) {
  final repo = ref.watch(supabaseLogSheetRepoProvider);
  return repo.getAll(
    operatorId: args.operatorId,
    section: args.section,
    workType: args.workType,
  );
});
