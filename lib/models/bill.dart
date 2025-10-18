import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class Bill {
  final int? id;
  final String firestoreId;
  final int clientId;
  final double totalAmount;
  final double paidAmount;
  final double carryForward;
  final double? discount;
  final double? tax;
  final DateTime date;
  final DateTime? dueDate;
  final String? paymentStatus;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  Bill({
    this.id,
    String? firestoreId,
    required this.clientId,
    required this.totalAmount,
    required this.paidAmount,
    required this.carryForward,
    this.discount,
    this.tax,
    required this.date,
    this.dueDate,
    this.paymentStatus,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : firestoreId = firestoreId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// FOR LOCAL SQLITE
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'firestoreId': firestoreId,
    'clientId': clientId,
    'totalAmount': totalAmount,
    'paidAmount': paidAmount,
    'carryForward': carryForward,
    'discount': discount ?? 0.0,
    'tax': tax ?? 0.0,
    'date': date.toIso8601String(),
    if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
    'paymentStatus': paymentStatus ?? 'pending',
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  /// FOR FIREBASE - Uses Timestamps
  Map<String, dynamic> toFirestore() => {
    'totalAmount': totalAmount,
    'paidAmount': paidAmount,
    'carryForward': carryForward,
    'discount': discount ?? 0.0,
    'tax': tax ?? 0.0,
    'date': Timestamp.fromDate(date),
    if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
    'paymentStatus': paymentStatus ?? 'pending',
    'notes': notes,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    // Don't include clientId - added as clientFirestoreId in sync service
  };

  /// FROM FIRESTORE DOCUMENT
  factory Bill.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    return Bill(
      firestoreId: doc.id,
      id: null,
      clientId: 0, // Will be resolved during sync
      totalAmount: _parseDouble(data['totalAmount']),
      paidAmount: _parseDouble(data['paidAmount']),
      carryForward: _parseDouble(data['carryForward']),
      discount: _parseDouble(data['discount']),
      tax: _parseDouble(data['tax']),
      date: _parseTimestamp(data['date']),
      dueDate: data['dueDate'] != null ? _parseTimestamp(data['dueDate']) : null,
      paymentStatus: data['paymentStatus'] as String? ?? 'pending',
      notes: data['notes'] as String?,
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  /// FROM LOCAL DATABASE MAP
  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      clientId: (map['clientId'] ?? 0) as int,
      totalAmount: _parseDouble(map['totalAmount']),
      paidAmount: _parseDouble(map['paidAmount']),
      carryForward: _parseDouble(map['carryForward']),
      discount: _parseDouble(map['discount']),
      tax: _parseDouble(map['tax']),
      date: DateTime.parse(map['date'] as String),
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate'] as String) : null,
      paymentStatus: map['paymentStatus'] as String? ?? 'pending',
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.parse(map['updatedAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isSynced: (map['isSynced'] ?? 0) == 1,
      isDeleted: (map['isDeleted'] ?? 0) == 1,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  Bill copyWith({
    int? id,
    String? firestoreId,
    int? clientId,
    double? totalAmount,
    double? paidAmount,
    double? carryForward,
    double? discount,
    double? tax,
    DateTime? date,
    DateTime? dueDate,
    String? paymentStatus,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Bill(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      clientId: clientId ?? this.clientId,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      carryForward: carryForward ?? this.carryForward,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Bill && runtimeType == other.runtimeType && firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;

  @override
  String toString() {
    return 'Bill(id: $id, firestoreId: $firestoreId, clientId: $clientId, '
        'totalAmount: $totalAmount, date: ${date.toIso8601String()})';
  }
}