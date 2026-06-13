class PaginationMeta {
  final int page;
  final int limit;
  final int total;
  final int pages;

  PaginationMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) => PaginationMeta(
        page: json['page'] ?? 1,
        limit: json['limit'] ?? 10,
        total: json['total'] ?? 0,
        pages: json['pages'] ?? 1,
      );
}

class PaginatedResponse<T> {
  final List<T> data;
  final PaginationMeta meta;

  PaginatedResponse({required this.data, required this.meta});

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    // Support both {data, meta:{page,limit,total,pages}} and flat {data,page,per_page,total}
    final metaJson = json['meta'] as Map<String, dynamic>? ??
        {
          'page': json['page'] ?? 1,
          'limit': json['per_page'] ?? json['limit'] ?? 10,
          'total': json['total'] ?? 0,
          'pages': json['pages'] ?? 1,
        };
    return PaginatedResponse(
      data: (json['data'] as List).map((e) => fromJson(e as Map<String, dynamic>)).toList(),
      meta: PaginationMeta.fromJson(metaJson),
    );
  }
}
