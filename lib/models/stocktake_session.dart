import 'stocktake_item.dart';

enum StocktakeStatus { inProgress, completed }

class StocktakeSession {
  StocktakeSession({
    required this.id,
    required this.name,
    required this.status,
    required this.scopeDescription,
    required this.notes,
    required this.createdAt,
    this.completedAt,
    List<StocktakeItem> items = const [],
  }) : items = List.unmodifiable(items);

  final String id;
  final String name;
  final StocktakeStatus status;
  final String scopeDescription;
  final String notes;
  final DateTime createdAt;
  final DateTime? completedAt;

  /// Items are ordered by ascending, bytewise product ID for deterministic resume.
  final List<StocktakeItem> items;

  factory StocktakeSession.fromJson(Map<String, Object?> json) =>
      StocktakeSession(
        id: json['id'] as String,
        name: json['name'] as String,
        status: _statusFromDatabase(json['status'] as String),
        scopeDescription: json['scope_description'] as String,
        notes: json['notes'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'status': _statusToDatabase(status),
    'scope_description': scopeDescription,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };

  StocktakeSession copyWith({
    StocktakeStatus? status,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    List<StocktakeItem>? items,
  }) => StocktakeSession(
    id: id,
    name: name,
    status: status ?? this.status,
    scopeDescription: scopeDescription,
    notes: notes,
    createdAt: createdAt,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    items: items ?? this.items,
  );
}

String stocktakeStatusToDatabase(StocktakeStatus status) =>
    status == StocktakeStatus.inProgress ? 'in_progress' : 'completed';

StocktakeStatus stocktakeStatusFromDatabase(String value) {
  if (value == 'in_progress') return StocktakeStatus.inProgress;
  if (value == 'completed') return StocktakeStatus.completed;
  throw FormatException('Unknown stocktake status: $value');
}

StocktakeStatus _statusFromDatabase(String value) =>
    stocktakeStatusFromDatabase(value);

String _statusToDatabase(StocktakeStatus status) =>
    stocktakeStatusToDatabase(status);
