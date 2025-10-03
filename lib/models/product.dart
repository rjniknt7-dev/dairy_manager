import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final int? id;                // Local SQLite ID (nullable)
  final String name;
  final double weight;
  final double price;
  final double costPrice;
  final double stock;           // always a number, default 0
  final String? firestoreId;    // Firestore document ID
  final DateTime? updatedAt;    // Last update time (local or server)
  final bool isSynced;          // Track if synced to Firestore

  Product({
    this.id,
    required this.name,
    required this.weight,
    required this.price,
    this.costPrice = 0.0,
    this.stock = 0.0,
    this.firestoreId,
    this.updatedAt,
    this.isSynced = false,
  });

  // -----------------------
  // Parsers (robust + reusable)
  // -----------------------
  static int? _parseIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double _parseDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static String _parseString(dynamic v, {String fallback = ''}) {
    return v == null ? fallback : v.toString();
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = v.toString();
    return DateTime.tryParse(s);
  }

  // -----------------------
  // Local SQLite map
  // -----------------------
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'weight': weight,
    'price': price,
    'costPrice': costPrice,
    'stock': stock,
    'firestoreId': firestoreId,
    'updatedAt': updatedAt?.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
  };

  // -----------------------
  // Firestore map (server timestamp for updatedAt)
  // -----------------------
  Map<String, dynamic> toFirestore() => {
    if (id != null) 'id': id,
    'name': name,
    'weight': weight,
    'price': price,
    'costPrice': costPrice,
    'stock': stock,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  // -----------------------
  // Create from a SQLite row (Map)
  // -----------------------
  factory Product.fromMap(Map<String, dynamic> m) => Product(
    id: _parseIntNullable(m['id']),
    name: _parseString(m['name'], fallback: 'Unnamed Product'),
    weight: _parseDouble(m['weight']),
    price: _parseDouble(m['price']),
    costPrice: _parseDouble(m['costPrice']),
    stock: _parseDouble(m['stock']),
    firestoreId: m['firestoreId']?.toString(),
    updatedAt: m['updatedAt'] != null ? _parseDateTime(m['updatedAt']) : null,
    isSynced: (m['isSynced'] ?? 0) == 1,
  );

  // -----------------------
  // Create from a Firestore DocumentSnapshot (defensive)
  // -----------------------
  factory Product.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    final Map<String, dynamic> data =
    (raw is Map<String, dynamic>) ? raw : <String, dynamic>{};

    return Product(
      firestoreId: doc.id,
      id: _parseIntNullable(data['id']),
      name: _parseString(data['name'], fallback: ''),
      weight: _parseDouble(data['weight']),
      price: _parseDouble(data['price']),
      costPrice: _parseDouble(data['costPrice']),
      stock: _parseDouble(data['stock']),
      updatedAt: _parseDateTime(data['updatedAt']),
      isSynced: true, // already in cloud
    );
  }

  // -----------------------
  // Copy
  // -----------------------
  Product copyWith({
    int? id,
    String? name,
    double? weight,
    double? price,
    double? costPrice,
    double? stock,
    String? firestoreId,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      weight: weight ?? this.weight,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      stock: stock ?? this.stock,
      firestoreId: firestoreId ?? this.firestoreId,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  // -----------------------
  // Equality (optional but recommended)
  // -----------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Product &&
              id == other.id &&
              firestoreId == other.firestoreId &&
              name == other.name;

  @override
  int get hashCode => id.hashCode ^ (firestoreId?.hashCode ?? 0) ^ name.hashCode;

  @override
  String toString() =>
      'Product(id: $id, name: $name, price: $price, costPrice: $costPrice)';
}
