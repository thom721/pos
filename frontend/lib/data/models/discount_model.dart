class DiscountModel {
  final String id;
  final String name;
  final String type; // "percentage" | "fixed"
  final double value;
  final String scope; // "receipt" | "item" | "both"
  final bool isAutomatic;
  final bool isActive;
  final String? scheduleDays; // "0,1,2,3,4" (0=lundi)
  final String? scheduleStart; // "HH:MM:SS"
  final String? scheduleEnd;
  final double? minQuantity; // seuil de quantité (rabais article) — ex: à partir de 3

  DiscountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.scope,
    this.isAutomatic = false,
    this.isActive = true,
    this.scheduleDays,
    this.scheduleStart,
    this.scheduleEnd,
    this.minQuantity,
  });

  bool get isPercentage => type == 'percentage';

  bool get appliesReceipt => scope == 'receipt' || scope == 'both';
  bool get appliesItem => scope == 'item' || scope == 'both';

  factory DiscountModel.fromJson(Map<String, dynamic> json) => DiscountModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() ?? 'percentage',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        scope: json['scope']?.toString() ?? 'both',
        isAutomatic: json['is_automatic'] == true,
        isActive: json['is_active'] != false,
        scheduleDays: json['schedule_days']?.toString(),
        scheduleStart: json['schedule_start']?.toString(),
        scheduleEnd: json['schedule_end']?.toString(),
        minQuantity: (json['min_quantity'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'value': value,
        'scope': scope,
        'is_automatic': isAutomatic,
        'is_active': isActive,
        if (scheduleDays != null) 'schedule_days': scheduleDays,
        if (scheduleStart != null) 'schedule_start': scheduleStart,
        if (scheduleEnd != null) 'schedule_end': scheduleEnd,
        if (minQuantity != null) 'min_quantity': minQuantity,
      };
}
