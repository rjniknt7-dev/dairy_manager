import 'package:cloud_firestore/cloud_firestore.dart';

class LedgerEntry {
  final int? id;              // Local SQLite ID
  final int clientId;         // Local client ID
  final int? billId;          // Nullable: link to a bill if applicable
  final String type;          // 'bill' or 'payment'
  final double amount;
  final DateTime date;
  final String? note;
  final String? firestoreId;  // Firestore document ID
  final DateTime? updatedAt;  // Last update time in Firestore
  final bool isSynced;        // Tracks if this row is already synced

  const LedgerEntry({
    this.id,
    required this.clientId,
    this.billId,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.firestoreId,
    this.updatedAt,
    this.isSynced = false,
  });

  /* ------------ Conversions ------------ */

  /// Local SQLite representation
  Map<String, dynamic> toMap() => {
    'id': id,
    'clientId': clientId,
    'billId': billId,
    'type': type,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'updatedAt': updatedAt?.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'firestoreId': firestoreId,
  };

  /// Firestore representation
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'clientId': clientId,
    'billId': billId,
    'type': type,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// From Firestore document
  factory LedgerEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return LedgerEntry(
      firestoreId: doc.id,
      id: data['id'] as int?,
      clientId: (data['clientId'] ?? 0) as int,
      billId: data['billId'] is int ? data['billId'] as int? : null,
      type: (data['type'] ?? '') as String,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.tryParse(data['date'] as String? ?? '') ?? DateTime.now(),
      note: data['note'] as String?,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isSynced: true,
    );
  }

  /// From local SQLite row
  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
    id: m['id'] as int?,
    clientId: m['clientId'] as int,
    billId: m['billId'] as int?,
    type: (m['type'] ?? '') as String,
    amount: (m['amount'] is int)
        ? (m['amount'] as int).toDouble()
        : (m['amount'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
    note: m['note'] as String?,
    firestoreId: m['firestoreId'] as String?,
    updatedAt: m['updatedAt'] != null
        ? DateTime.tryParse(m['updatedAt'].toString())
        : null,
    isSynced: (m['isSynced'] ?? 0) == 1,
  );

  /* ------------ Utilities ------------ */

  /// Create a modified copy
  LedgerEntry copyWith({
    int? id,
    int? clientId,
    int? billId,
    String? type,
    double? amount,
    DateTime? date,
    String? note,
    String? firestoreId,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      billId: billId ?? this.billId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      firestoreId: firestoreId ?? this.firestoreId,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is LedgerEntry &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              clientId == other.clientId &&
              billId == other.billId &&
              type == other.type &&
              amount == other.amount &&
              date == other.date &&
              note == other.note &&
              firestoreId == other.firestoreId;

  @override
  int get hashCode =>
      id.hashCode ^
      clientId.hashCode ^
      (billId?.hashCode ?? 0) ^
      type.hashCode ^
      amount.hashCode ^
      date.hashCode ^
      (note?.hashCode ?? 0) ^
      (firestoreId?.hashCode ?? 0);
}
