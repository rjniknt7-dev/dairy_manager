import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class LedgerEntry {
  final int? id;
  final String firestoreId;
  final int clientId;
  final int? billId;
  final String type;
  final double amount;
  final DateTime date;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  LedgerEntry({
    this.id,
    String? firestoreId,
    required this.clientId,
    this.billId,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : firestoreId = firestoreId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'firestoreId': firestoreId,
    'clientId': clientId,
    'billId': billId,
    'type': type,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'updatedAt': updatedAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  Map<String, dynamic> toFirestore() => {
    'clientId': clientId,
    'billId': billId,
    'type': type,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory LedgerEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return LedgerEntry(
      firestoreId: doc.id,
      id: data['id'] as int?,
      clientId: (data['clientId'] ?? 0) as int,
      billId: data['billId'] as int?,
      type: (data['type'] ?? '') as String,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.parse(data['date'] as String? ?? DateTime.now().toIso8601String()),
      note: data['note'] as String?,
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
    id: m['id'] as int?,
    firestoreId: m['firestoreId'] as String?,
    clientId: m['clientId'] as int,
    billId: m['billId'] as int?,
    type: (m['type'] ?? '') as String,
    amount: (m['amount'] is int) ? (m['amount'] as int).toDouble() : (m['amount'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.parse(m['date'] as String),
    note: m['note'] as String?,
    createdAt: m['createdAt'] != null
        ? DateTime.parse(m['createdAt'] as String)
        : DateTime.parse(m['updatedAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
    isSynced: (m['isSynced'] ?? 0) == 1,
    isDeleted: (m['isDeleted'] ?? 0) == 1,
  );

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  LedgerEntry copyWith({
    int? id,
    String? firestoreId,
    int? clientId,
    int? billId,
    String? type,
    double? amount,
    DateTime? date,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      clientId: clientId ?? this.clientId,
      billId: billId ?? this.billId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is LedgerEntry && runtimeType == other.runtimeType && firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;
}