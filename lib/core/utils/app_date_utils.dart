import 'package:intl/intl.dart';

// Date/time utilities — all timezone-aware helpers for the edit-window rule (§0.2)
// and local-midnight epoch storage. All stored timestamps are UTC integers (ms since epoch);
// all display/comparison is in device local time.

/// Utilities for date operations in the Operator Reading Management System.
abstract final class AppDateUtils {
  // ── Epoch helpers ──────────────────────────────────────────────────────────

  /// Current UTC time as milliseconds since epoch.
  static int nowUtcMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Converts a [DateTime] to UTC milliseconds since epoch (for DB storage).
  static int toUtcMs(DateTime dt) => dt.toUtc().millisecondsSinceEpoch;

  /// Converts UTC milliseconds since epoch back to a [DateTime] in local time.
  static DateTime fromUtcMs(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

  // ── Local-midnight epoch ──────────────────────────────────────────────────

  /// Returns the local-midnight UTC epoch (ms) for [date].
  /// Used to store `reading_date` as a date-only value (§7 schema note).
  static int toLocalMidnightUtcMs(DateTime date) {
    final localMidnight =
        DateTime(date.year, date.month, date.day); // local midnight
    return localMidnight.toUtc().millisecondsSinceEpoch;
  }

  /// Returns the local-midnight epoch for TODAY.
  static int todayLocalMidnightUtcMs() => toLocalMidnightUtcMs(DateTime.now());

  /// Parses a local-midnight epoch back to a [DateTime] at local midnight.
  static DateTime fromLocalMidnightUtcMs(int ms) {
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return DateTime(utc.toLocal().year, utc.toLocal().month, utc.toLocal().day);
  }

  // ── Edit-window check (§0.2) ──────────────────────────────────────────────

  /// Returns true if a reading created at [createdAtUtcMs] is still editable.
  /// A reading is editable only on the calendar day it was *created* (local time).
  /// §0.2: edit window = calendar day of creation, not the reading_date.
  static bool isEditableToday(int createdAtUtcMs) {
    final createdLocal = fromUtcMs(createdAtUtcMs);
    final now = DateTime.now();
    return createdLocal.year == now.year &&
        createdLocal.month == now.month &&
        createdLocal.day == now.day;
  }

  // ── Display helpers ───────────────────────────────────────────────────────

  static final DateFormat _dateFormatter = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTimeFormatter = DateFormat('dd MMM yyyy, HH:mm');
  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  /// Formats a UTC-ms timestamp as a human-readable date (e.g. "19 Jul 2026").
  static String formatDate(int utcMs) =>
      _dateFormatter.format(fromUtcMs(utcMs));

  /// Formats a UTC-ms timestamp as date + time (e.g. "19 Jul 2026, 14:30").
  static String formatDateTime(int utcMs) =>
      _dateTimeFormatter.format(fromUtcMs(utcMs));

  /// Formats a UTC-ms timestamp as time only (e.g. "14:30").
  static String formatTime(int utcMs) => _timeFormatter.format(fromUtcMs(utcMs));

  /// Formats a local-midnight epoch as a display date.
  static String formatReadingDate(int localMidnightMs) =>
      _dateFormatter.format(fromLocalMidnightUtcMs(localMidnightMs));

  // ── Comparison helpers ────────────────────────────────────────────────────

  /// Returns true if [readingDateMs] (local-midnight epoch) is today (local).
  static bool isToday(int readingDateMs) {
    final readingDate = fromLocalMidnightUtcMs(readingDateMs);
    final now = DateTime.now();
    return readingDate.year == now.year &&
        readingDate.month == now.month &&
        readingDate.day == now.day;
  }

  /// Returns true if [readingDateMs] (local-midnight epoch) is in the future.
  static bool isFutureDate(int readingDateMs) {
    final readingDate = fromLocalMidnightUtcMs(readingDateMs);
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return readingDate.isAfter(todayMidnight);
  }

  // ── Business Day helpers ──────────────────────────────────────────────────

  /// Returns the start of the current business day in local time, converted to UTC ms.
  /// A business day starts at 8:00 AM.
  static int startOfCurrentBusinessDayUtcMs() {
    final now = DateTime.now();
    final DateTime localStart;
    if (now.hour < 8) {
      localStart = DateTime(now.year, now.month, now.day - 1, 8, 0, 0);
    } else {
      localStart = DateTime(now.year, now.month, now.day, 8, 0, 0);
    }
    return localStart.toUtc().millisecondsSinceEpoch;
  }

  /// Converts a reading timestamp (ms) to the local midnight of its business day.
  /// (e.g. any time between 20 Aug 8:00 AM and 21 Aug 8:00 AM maps to 20 Aug local midnight).
  static int toBusinessDayMidnightUtcMs(int readingDateMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(readingDateMs, isUtc: true).toLocal();
    final DateTime businessDay;
    if (dt.hour < 8) {
      businessDay = DateTime(dt.year, dt.month, dt.day - 1);
    } else {
      businessDay = DateTime(dt.year, dt.month, dt.day);
    }
    return businessDay.toUtc().millisecondsSinceEpoch;
  }

  /// Returns a list of [DateTime] objects for the date-picker range (today going back [days] days).
  static List<DateTime> recentDays({int days = 30}) {
    final today = DateTime.now();
    return List.generate(
      days,
      (i) => DateTime(today.year, today.month, today.day - i),
    );
  }
}
