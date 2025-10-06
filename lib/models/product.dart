import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class Product {
  final int? id;
  final String firestoreId;
  final String name;
  final double quantity;
  final double price;
  final double costPrice;
  final double stock;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  Product({
    this.id,
    String? firestoreId,
    required this.name,
    required this.quantity,
    required this.price,
    this.costPrice = 0.0,
    this.stock = 0.0,
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
    'name': name,
    'weight': quantity,
    'price': price,
    'costPrice': costPrice,
    'stock': stock,
    'updatedAt': updatedAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'weight': quantity,
    'price': price,
    'costPrice': costPrice,
    'stock': stock,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Product(
      firestoreId: doc.id,
      id: _parseInt(data['id']),
      name: data['name']?.toString() ?? '',
      quantity: _parseDouble(data['weight']),
      price: _parseDouble(data['price']),
      costPrice: _parseDouble(data['costPrice']),
      stock: _parseDouble(data['stock']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  factory Product.fromMap(Map<String, dynamic> m) => Product(
    id: _parseInt(m['id']),
    firestoreId: m['firestoreId'] as String?,
    name: m['name']?.toString() ?? 'Unnamed Product',
    quantity: _parseDouble(m['weight']),
    price: _parseDouble(m['price']),
    costPrice: _parseDouble(m['costPrice']),
    stock: _parseDouble(m['stock']),
    createdAt: m['createdAt'] != null
        ? DateTime.parse(m['createdAt'] as String)
        : DateTime.parse(m['updatedAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
    isSynced: (m['isSynced'] ?? 0) == 1,
    isDeleted: (m['isDeleted'] ?? 0) == 1,
  );

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  Product copyWith({
    int? id,
    String? firestoreId,
    String? name,
    double? weight,
    double? price,
    double? costPrice,
    double? stock,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Product(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      name: name ?? this.name,
      quantity: weight ?? this.quantity,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      stock: stock ?? this.stock,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Product && runtimeType == other.runtimeType && firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;

  @override
  String toString() => 'Product(id: $id, name: $name, price: $price)';
}