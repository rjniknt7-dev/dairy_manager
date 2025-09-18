import 'package:cloud_firestore/cloud_firestore.dart';

class BillItem {
  final int? id;             // Local SQLite ID
  final int? billId;         // May be null until parent Bill is saved
  final int productId;
  final double quantity;
  final double price;
  final String? docId;       // Firestore document ID
  final DateTime? updatedAt; // Last update time (local or cloud)
  final bool isSynced;       // ✅ Tracks if this record is already synced to cloud

  const BillItem({
    this.id,
    this.billId,
    required this.productId,
    required this.quantity,
    required this.price,
    this.docId,
    this.updatedAt,
    this.isSynced = false,
  });

  /* ------------ Conversions ------------ */

  /// Local DB representation (SQLite)
  Map<String, dynamic> toMap() => {
    'id': id,
    'billId': billId,
    'productId': productId,
    'quantity': quantity,
    'price': price,
    'updatedAt': updatedAt?.toIso8601String(),
    'isSynced': isSynced ? 1 : 0, // store as int(0/1)
  };

  /// Firestore representation
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'billId': billId,
    'productId': productId,
    'quantity': quantity,
    'price': price,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// From Firestore document snapshot
  factory BillItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BillItem(
      docId: doc.id,
      id: data['id'] as int?,
      billId: data['billId'] as int?,
      productId: (data['productId'] ?? 0) as int,
      quantity: (data['quantity'] ?? 0).toDouble(),
      price: (data['price'] ?? 0).toDouble(),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isSynced: true, // when reading from Firestore, we consider it synced
    );
  }

  /// From local SQLite row
  factory BillItem.fromMap(Map<String, dynamic> map) => BillItem(
    id: map['id'] as int?,
    billId: map['billId'] as int?,
    productId: (map['productId'] ?? 0) as int,
    quantity: (map['quantity'] ?? 0).toDouble(),
    price: (map['price'] ?? 0).toDouble(),
    updatedAt: map['updatedAt'] != null
        ? DateTime.tryParse(map['updatedAt'].toString())
        : null,
    isSynced: (map['isSynced'] ?? 0) == 1,
  );

  /* ------------ Utilities ------------ */

  BillItem copyWith({
    int? id,
    int? billId,
    int? productId,
    double? quantity,
    double? price,
    String? docId,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return BillItem(
      id: id ?? this.id,
      billId: billId ?? this.billId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      docId: docId ?? this.docId,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is BillItem &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              billId == other.billId &&
              productId == other.productId &&
              quantity == other.quantity &&
              price == other.price &&
              docId == other.docId;

  @override
  int get hashCode =>
      id.hashCode ^
      billId.hashCode ^
      productId.hashCode ^
      quantity.hashCode ^
      price.hashCode ^
      (docId?.hashCode ?? 0);
}
