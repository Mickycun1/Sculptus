import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SculptusApp());
}

const _romanRed = Color(0xFF7A2738);
const _bronze = Color(0xFFC08A3E);
const _marble = Color(0xFFF4EFE5);
const _parchment = Color(0xFFFFFBF1);
const _olive = Color(0xFF536443);
const _ink = Color(0xFF25201C);
const _stone = Color(0xFFD8D0C3);
const _blue = Color(0xFF2F5869);

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _dateKey(DateTime value) {
  final date = _dateOnly(value);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _displayDate(DateTime value) {
  final date = _dateOnly(value);
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}

String _shortDate(DateTime value) {
  final date = _dateOnly(value);
  return '${_months[date.month - 1]} ${date.day}';
}

String _displayDateTime(DateTime value) {
  return '${_shortDate(value)} ${_displayTime(value)}';
}

String _displayTime(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

double _readDouble(String value, [double fallback = 0]) {
  return double.tryParse(value.trim()) ?? fallback;
}

int _readInt(String value, [int fallback = 0]) {
  return int.tryParse(value.trim()) ?? fallback;
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _newId(String prefix) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final salt = math.Random().nextInt(99999).toString().padLeft(5, '0');
  return '$prefix-$now-$salt';
}

class Nutrition {
  const Nutrition({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  static const zero = Nutrition();

  Nutrition operator +(Nutrition other) {
    return Nutrition(
      calories: calories + other.calories,
      protein: protein + other.protein,
      carbs: carbs + other.carbs,
      fat: fat + other.fat,
    );
  }

  Nutrition scale(double factor) {
    return Nutrition(
      calories: (calories * factor).round(),
      protein: protein * factor,
      carbs: carbs * factor,
      fat: fat * factor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
    };
  }

  factory Nutrition.fromJson(Map<String, dynamic> json) {
    return Nutrition(
      calories: (json['calories'] as num?)?.round() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FoodEstimateItem {
  const FoodEstimateItem({
    required this.name,
    required this.calories,
    this.protein = 0,
    this.note = '',
  });

  final String name;
  final int calories;
  final double protein;
  final String note;
}

class FoodEstimateResult {
  const FoodEstimateResult(this.items);

  final List<FoodEstimateItem> items;

  int get calories {
    return items.fold<int>(0, (sum, item) => sum + item.calories);
  }

  double get protein {
    return items.fold<double>(0, (sum, item) => sum + item.protein);
  }

  int get lowCalories => (calories * 0.88).round();

  int get highCalories => (calories * 1.18).round();

  String get notes {
    return items
        .map((item) {
          final proteinText = item.protein > 0
              ? ', ${_formatNumber(item.protein)}g protein'
              : '';
          final noteText = item.note.isNotEmpty ? ' (${item.note})' : '';
          return '${item.name}: ${item.calories} kcal$proteinText$noteText';
        })
        .join('\n');
  }
}

FoodEstimateResult estimateFoodText(String rawText) {
  final text = rawText.toLowerCase();
  final items = <FoodEstimateItem>[];

  int countFor(String pattern, [int fallback = 1]) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
    if (match == null) {
      return 0;
    }
    final rawCount = match.group(1);
    if (rawCount == null) {
      return fallback;
    }
    return math.max(int.tryParse(rawCount) ?? fallback, 1);
  }

  int gramsFor(String pattern) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  void addCounted({
    required String pattern,
    required String name,
    required int caloriesEach,
    double proteinEach = 0,
    int fallback = 1,
    String note = '',
  }) {
    final count = countFor(pattern, fallback);
    if (count <= 0) {
      return;
    }
    items.add(
      FoodEstimateItem(
        name: count == 1 ? name : '$count x $name',
        calories: count * caloriesEach,
        protein: count * proteinEach,
        note: note,
      ),
    );
  }

  void addGrams({
    required String pattern,
    required String name,
    required double caloriesPer100g,
    double proteinPer100g = 0,
  }) {
    final grams = gramsFor(pattern);
    if (grams <= 0) {
      return;
    }
    final factor = grams / 100;
    items.add(
      FoodEstimateItem(
        name: '${grams}g $name',
        calories: (caloriesPer100g * factor).round(),
        protein: proteinPer100g * factor,
      ),
    );
  }

  final explicitCalorieMatches = RegExp(
    r'([a-z][a-z\s]+?)\s*(?:\(|-)?\s*(\d{2,4})\s*(?:cal|cals|calories)',
    caseSensitive: false,
  ).allMatches(rawText);
  for (final match in explicitCalorieMatches) {
    final label = (match.group(1) ?? 'Estimated item').trim();
    final calories = int.tryParse(match.group(2) ?? '') ?? 0;
    final isActivity =
        label.contains('burn') ||
        label.contains('worked') ||
        label.contains('workout') ||
        label.contains('crossfit') ||
        label.contains('walk');
    if (calories > 0 && !isActivity) {
      items.add(
        FoodEstimateItem(
          name: label,
          calories: calories,
          note: 'user-provided calories',
        ),
      );
    }
  }

  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:small\s*)?(?:pink lady\s*)?apples?',
    name: 'small apple',
    caloriesEach: 70,
  );
  addCounted(pattern: r'(\d+)\s*x?\s*kiwis?', name: 'kiwi', caloriesEach: 45);
  addCounted(
    pattern: r'(\d+)\s*x?\s*bananas?',
    name: 'banana',
    caloriesEach: 105,
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:medium\s*)?(?:brown\s*)?eggs?',
    name: 'egg',
    caloriesEach: 70,
    proteinEach: 6,
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:drumstick\s*)?(?:chicken\s*)?wings?',
    name: 'chicken wing',
    caloriesEach: 95,
    proteinEach: 7,
    note: 'restaurant wing average',
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:fried\s*)?spring rolls?',
    name: 'spring roll',
    caloriesEach: 150,
  );
  addCounted(
    pattern: r'(one)\s*(?:fried\s*)?spring roll',
    name: 'spring roll',
    caloriesEach: 150,
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:fried\s*)?dumplings?',
    name: 'fried dumpling',
    caloriesEach: 80,
  );
  addCounted(
    pattern: r'(one)\s*(?:fried\s*)?dumpling',
    name: 'fried dumpling',
    caloriesEach: 80,
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:balls?\s*of\s*)?falafel',
    name: 'falafel ball',
    caloriesEach: 70,
    proteinEach: 3,
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*(?:scoops?\s*of\s*)?(?:on\s*)?whey',
    name: 'ON whey scoop',
    caloriesEach: 120,
    proteinEach: 24,
  );
  addCounted(
    pattern: r'(\d+)\s*x?\s*coffees?',
    name: 'coffee',
    caloriesEach: 5,
  );

  if (text.contains('1/2 cup oats') || text.contains('½ cup oats')) {
    items.add(
      const FoodEstimateItem(name: '1/2 cup oats', calories: 150, protein: 5),
    );
  }
  if (text.contains('bagel')) {
    items.add(
      const FoodEstimateItem(name: 'bagel', calories: 280, protein: 10),
    );
  }
  if (text.contains('honey')) {
    items.add(const FoodEstimateItem(name: 'honey', calories: 60));
  }
  if (text.contains('granola')) {
    items.add(const FoodEstimateItem(name: 'granola', calories: 70));
  }
  if (text.contains('meringue')) {
    items.add(const FoodEstimateItem(name: 'crushed meringue', calories: 20));
  }
  if (text.contains('brown rice')) {
    items.add(const FoodEstimateItem(name: 'brown rice scoop', calories: 215));
  }

  addGrams(
    pattern: r'(\d+)\s*g\s*(?:kirkland\s*)?(?:greek\s*)?yogurt',
    name: 'Greek yogurt',
    caloriesPer100g: 60,
    proteinPer100g: 10,
  );
  addGrams(
    pattern: r'(\d+)\s*g\s*cantaloupe',
    name: 'cantaloupe',
    caloriesPer100g: 34,
  );
  addGrams(
    pattern: r'(\d+)\s*g\s*(?:zucchini|courgette)',
    name: 'zucchini',
    caloriesPer100g: 17,
  );
  addGrams(
    pattern: r'(\d+)\s*g\s*hummus',
    name: 'hummus',
    caloriesPer100g: 166,
    proteinPer100g: 8,
  );
  addGrams(
    pattern: r'(\d+)\s*g\s*(?:dry\s*)?pasta',
    name: 'pasta',
    caloriesPer100g: 355,
    proteinPer100g: 13,
  );
  addGrams(
    pattern: r'(\d+)\s*g\s*meatballs?',
    name: 'lean meatballs',
    caloriesPer100g: 175,
    proteinPer100g: 22,
  );

  if (text.contains('strawberries')) {
    items.add(const FoodEstimateItem(name: 'strawberries', calories: 25));
  }
  if (text.contains('grapes')) {
    items.add(const FoodEstimateItem(name: 'grapes', calories: 50));
  }
  if (text.contains('blueberries')) {
    items.add(const FoodEstimateItem(name: 'blueberries', calories: 40));
  }
  if (text.contains('raspberries')) {
    items.add(const FoodEstimateItem(name: 'raspberries', calories: 30));
  }

  return FoodEstimateResult(items);
}

class Ingredient {
  const Ingredient({
    required this.name,
    required this.nutrition,
    this.amount = '',
  });

  final String name;
  final String amount;
  final Nutrition nutrition;

  Map<String, dynamic> toJson() {
    return {'name': name, 'amount': amount, 'nutrition': nutrition.toJson()};
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String? ?? '',
      amount: json['amount'] as String? ?? '',
      nutrition: Nutrition.fromJson(
        Map<String, dynamic>.from(json['nutrition'] as Map? ?? {}),
      ),
    );
  }
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.servings,
    required this.ingredients,
    required this.createdAt,
    this.notes = '',
  });

  final String id;
  final String name;
  final int servings;
  final List<Ingredient> ingredients;
  final DateTime createdAt;
  final String notes;

  Nutrition get totalNutrition {
    return ingredients.fold<Nutrition>(
      Nutrition.zero,
      (sum, ingredient) => sum + ingredient.nutrition,
    );
  }

  Nutrition get perServing {
    final safeServings = math.max(servings, 1);
    return totalNutrition.scale(1 / safeServings);
  }

  Recipe copyWith({
    String? id,
    String? name,
    int? servings,
    List<Ingredient>? ingredients,
    DateTime? createdAt,
    String? notes,
  }) {
    return Recipe(
      id: id ?? this.id,
      name: name ?? this.name,
      servings: servings ?? this.servings,
      ingredients: ingredients ?? this.ingredients,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'servings': servings,
      'ingredients': ingredients.map((item) => item.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
    };
  }

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String? ?? _newId('recipe'),
      name: json['name'] as String? ?? 'Recipe',
      servings: (json['servings'] as num?)?.round() ?? 1,
      ingredients: (json['ingredients'] as List? ?? const [])
          .map((item) => Ingredient.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      notes: json['notes'] as String? ?? '',
    );
  }
}

enum DiarySource {
  quick,
  recipe,
  restaurant,
  estimate;

  String get label {
    switch (this) {
      case DiarySource.quick:
        return 'Food';
      case DiarySource.recipe:
        return 'Recipe';
      case DiarySource.restaurant:
        return 'Restaurant';
      case DiarySource.estimate:
        return 'Estimate';
    }
  }

  IconData get icon {
    switch (this) {
      case DiarySource.quick:
        return Icons.restaurant_menu;
      case DiarySource.recipe:
        return Icons.soup_kitchen;
      case DiarySource.restaurant:
        return Icons.local_dining;
      case DiarySource.estimate:
        return Icons.psychology_alt;
    }
  }
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.date,
    required this.name,
    required this.nutrition,
    required this.source,
    required this.createdAt,
    this.servings = 1,
    this.recipeId,
    this.notes = '',
  });

  final String id;
  final DateTime date;
  final String name;
  final Nutrition nutrition;
  final DiarySource source;
  final DateTime createdAt;
  final double servings;
  final String? recipeId;
  final String notes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': _dateKey(date),
      'name': name,
      'nutrition': nutrition.toJson(),
      'source': source.name,
      'createdAt': createdAt.toIso8601String(),
      'servings': servings,
      'recipeId': recipeId,
      'notes': notes,
    };
  }

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String? ?? DiarySource.quick.name;
    return DiaryEntry(
      id: json['id'] as String? ?? _newId('entry'),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      name: json['name'] as String? ?? 'Food',
      nutrition: Nutrition.fromJson(
        Map<String, dynamic>.from(json['nutrition'] as Map? ?? {}),
      ),
      source: DiarySource.values.firstWhere(
        (source) => source.name == sourceName,
        orElse: () => DiarySource.quick,
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      servings: (json['servings'] as num?)?.toDouble() ?? 1,
      recipeId: json['recipeId'] as String?,
      notes: json['notes'] as String? ?? '',
    );
  }
}

class WeightEntry {
  const WeightEntry({
    required this.id,
    required this.date,
    required this.weight,
  });

  final String id;
  final DateTime date;
  final double weight;

  Map<String, dynamic> toJson() {
    return {'id': id, 'date': _dateKey(date), 'weight': weight};
  }

  factory WeightEntry.fromJson(Map<String, dynamic> json) {
    return WeightEntry(
      id: json['id'] as String? ?? _newId('weight'),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.date,
    required this.name,
    required this.caloriesBurned,
    required this.createdAt,
    this.steps = 0,
    this.minutes = 0,
    this.notes = '',
  });

  final String id;
  final DateTime date;
  final String name;
  final int caloriesBurned;
  final int steps;
  final int minutes;
  final String notes;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': _dateKey(date),
      'name': name,
      'caloriesBurned': caloriesBurned,
      'steps': steps,
      'minutes': minutes,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as String? ?? _newId('activity'),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      name: json['name'] as String? ?? 'Workout',
      caloriesBurned: (json['caloriesBurned'] as num?)?.round() ?? 0,
      steps: (json['steps'] as num?)?.round() ?? 0,
      minutes: (json['minutes'] as num?)?.round() ?? 0,
      notes: json['notes'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class StepEntry {
  const StepEntry({
    required this.id,
    required this.date,
    required this.steps,
    required this.recordedAt,
    required this.timeLabel,
    this.projectedSteps = 0,
    this.notes = '',
  });

  final String id;
  final DateTime date;
  final int steps;
  final int projectedSteps;
  final DateTime recordedAt;
  final String timeLabel;
  final String notes;

  int get budgetSteps => math.max(steps, projectedSteps);

  int get caloriesBurned => (budgetSteps * 0.05).round();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': _dateKey(date),
      'steps': steps,
      'projectedSteps': projectedSteps,
      'recordedAt': recordedAt.toIso8601String(),
      'timeLabel': timeLabel,
      'notes': notes,
    };
  }

  factory StepEntry.fromJson(Map<String, dynamic> json) {
    final recordedAt =
        DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
        DateTime.now();
    return StepEntry(
      id: json['id'] as String? ?? _newId('steps'),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      steps: (json['steps'] as num?)?.round() ?? 0,
      projectedSteps: (json['projectedSteps'] as num?)?.round() ?? 0,
      recordedAt: recordedAt,
      timeLabel: json['timeLabel'] as String? ?? _displayTime(recordedAt),
      notes: json['notes'] as String? ?? '',
    );
  }
}

class WhoopSnapshot {
  const WhoopSnapshot({
    required this.connected,
    this.summaryDate,
    this.profileName = '',
    this.profileEmail = '',
    this.lastSyncedAt,
    this.recoveryScore = 0,
    this.hrvRmssdMillis = 0,
    this.restingHeartRate = 0,
    this.sleepPerformance = 0,
    this.sleepHours = 0,
    this.cycleStrain = 0,
    this.cycleKilojoules = 0,
    this.todayWorkoutCalories = 0,
    this.todayWorkoutCount = 0,
    this.todayWorkoutMinutes = 0,
    this.latestWorkoutName = '',
    this.latestWorkoutStart,
    this.latestWorkoutStrain = 0,
    this.latestWorkoutKilojoules = 0,
    this.bodyWeightLb = 0,
    this.steps = 0,
    this.stepsSource = '',
    this.stepsRecordedAt,
  });

  final bool connected;
  final DateTime? summaryDate;
  final String profileName;
  final String profileEmail;
  final DateTime? lastSyncedAt;
  final int recoveryScore;
  final double hrvRmssdMillis;
  final int restingHeartRate;
  final int sleepPerformance;
  final double sleepHours;
  final double cycleStrain;
  final double cycleKilojoules;
  final int todayWorkoutCalories;
  final int todayWorkoutCount;
  final int todayWorkoutMinutes;
  final String latestWorkoutName;
  final DateTime? latestWorkoutStart;
  final double latestWorkoutStrain;
  final double latestWorkoutKilojoules;
  final double bodyWeightLb;
  final int steps;
  final String stepsSource;
  final DateTime? stepsRecordedAt;

  static const empty = WhoopSnapshot(connected: false);

  bool get hasUsefulData {
    return recoveryScore > 0 ||
        sleepPerformance > 0 ||
        cycleStrain > 0 ||
        todayWorkoutCalories > 0 ||
        bodyWeightLb > 0 ||
        steps > 0;
  }

  String get displayName {
    if (profileName.trim().isNotEmpty) {
      return profileName.trim();
    }
    if (profileEmail.trim().isNotEmpty) {
      return profileEmail.trim();
    }
    return 'WHOOP';
  }

  WhoopSnapshot copyWith({
    bool? connected,
    DateTime? summaryDate,
    String? profileName,
    String? profileEmail,
    DateTime? lastSyncedAt,
    int? recoveryScore,
    double? hrvRmssdMillis,
    int? restingHeartRate,
    int? sleepPerformance,
    double? sleepHours,
    double? cycleStrain,
    double? cycleKilojoules,
    int? todayWorkoutCalories,
    int? todayWorkoutCount,
    int? todayWorkoutMinutes,
    String? latestWorkoutName,
    DateTime? latestWorkoutStart,
    double? latestWorkoutStrain,
    double? latestWorkoutKilojoules,
    double? bodyWeightLb,
    int? steps,
    String? stepsSource,
    DateTime? stepsRecordedAt,
  }) {
    return WhoopSnapshot(
      connected: connected ?? this.connected,
      summaryDate: summaryDate ?? this.summaryDate,
      profileName: profileName ?? this.profileName,
      profileEmail: profileEmail ?? this.profileEmail,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      recoveryScore: recoveryScore ?? this.recoveryScore,
      hrvRmssdMillis: hrvRmssdMillis ?? this.hrvRmssdMillis,
      restingHeartRate: restingHeartRate ?? this.restingHeartRate,
      sleepPerformance: sleepPerformance ?? this.sleepPerformance,
      sleepHours: sleepHours ?? this.sleepHours,
      cycleStrain: cycleStrain ?? this.cycleStrain,
      cycleKilojoules: cycleKilojoules ?? this.cycleKilojoules,
      todayWorkoutCalories: todayWorkoutCalories ?? this.todayWorkoutCalories,
      todayWorkoutCount: todayWorkoutCount ?? this.todayWorkoutCount,
      todayWorkoutMinutes: todayWorkoutMinutes ?? this.todayWorkoutMinutes,
      latestWorkoutName: latestWorkoutName ?? this.latestWorkoutName,
      latestWorkoutStart: latestWorkoutStart ?? this.latestWorkoutStart,
      latestWorkoutStrain: latestWorkoutStrain ?? this.latestWorkoutStrain,
      latestWorkoutKilojoules:
          latestWorkoutKilojoules ?? this.latestWorkoutKilojoules,
      bodyWeightLb: bodyWeightLb ?? this.bodyWeightLb,
      steps: steps ?? this.steps,
      stepsSource: stepsSource ?? this.stepsSource,
      stepsRecordedAt: stepsRecordedAt ?? this.stepsRecordedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connected': connected,
      'summaryDate': summaryDate == null ? null : _dateKey(summaryDate!),
      'profileName': profileName,
      'profileEmail': profileEmail,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'recoveryScore': recoveryScore,
      'hrvRmssdMillis': hrvRmssdMillis,
      'restingHeartRate': restingHeartRate,
      'sleepPerformance': sleepPerformance,
      'sleepHours': sleepHours,
      'cycleStrain': cycleStrain,
      'cycleKilojoules': cycleKilojoules,
      'todayWorkoutCalories': todayWorkoutCalories,
      'todayWorkoutCount': todayWorkoutCount,
      'todayWorkoutMinutes': todayWorkoutMinutes,
      'latestWorkoutName': latestWorkoutName,
      'latestWorkoutStart': latestWorkoutStart?.toIso8601String(),
      'latestWorkoutStrain': latestWorkoutStrain,
      'latestWorkoutKilojoules': latestWorkoutKilojoules,
      'bodyWeightLb': bodyWeightLb,
      'steps': steps,
      'stepsSource': stepsSource,
      'stepsRecordedAt': stepsRecordedAt?.toIso8601String(),
    };
  }

  factory WhoopSnapshot.fromJson(Map<String, dynamic> json) {
    DateTime? dateFrom(dynamic value) {
      if (value is! String || value.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    }

    double doubleFrom(String key) {
      return (json[key] as num?)?.toDouble() ?? 0;
    }

    int intFrom(String key) {
      return (json[key] as num?)?.round() ?? 0;
    }

    final bodyWeightLb = doubleFrom('bodyWeightLb') > 0
        ? doubleFrom('bodyWeightLb')
        : doubleFrom('bodyWeightKg') * 2.2046226218;

    return WhoopSnapshot(
      connected: json['connected'] as bool? ?? json.isNotEmpty,
      summaryDate: dateFrom(json['summaryDate'] ?? json['date']),
      profileName:
          json['profileName'] as String? ?? json['name'] as String? ?? '',
      profileEmail: json['profileEmail'] as String? ?? '',
      lastSyncedAt:
          dateFrom(json['lastSyncedAt']) ??
          dateFrom(json['syncedAt']) ??
          DateTime.now(),
      recoveryScore: intFrom('recoveryScore'),
      hrvRmssdMillis: doubleFrom('hrvRmssdMillis'),
      restingHeartRate: intFrom('restingHeartRate'),
      sleepPerformance: intFrom('sleepPerformance'),
      sleepHours: doubleFrom('sleepHours'),
      cycleStrain: doubleFrom('cycleStrain'),
      cycleKilojoules: doubleFrom('cycleKilojoules'),
      todayWorkoutCalories: intFrom('todayWorkoutCalories') > 0
          ? intFrom('todayWorkoutCalories')
          : intFrom('workoutCalories'),
      todayWorkoutCount: intFrom('todayWorkoutCount'),
      todayWorkoutMinutes: intFrom('todayWorkoutMinutes'),
      latestWorkoutName: json['latestWorkoutName'] as String? ?? '',
      latestWorkoutStart: dateFrom(json['latestWorkoutStart']),
      latestWorkoutStrain: doubleFrom('latestWorkoutStrain'),
      latestWorkoutKilojoules: doubleFrom('latestWorkoutKilojoules'),
      bodyWeightLb: bodyWeightLb,
      steps: intFrom('steps'),
      stepsSource: json['stepsSource'] as String? ?? '',
      stepsRecordedAt: dateFrom(json['stepsRecordedAt']),
    );
  }
}

class WhoopSyncException implements Exception {
  const WhoopSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WhoopApiClient {
  const WhoopApiClient(this.baseUrl);

  final String baseUrl;

  Future<WhoopSnapshot> fetchSummary(DateTime date) async {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      throw const WhoopSyncException('Set a backend URL first.');
    }

    final uri = Uri.parse(
      '$trimmed/api/whoop/summary',
    ).replace(queryParameters: {'date': _dateKey(date)});

    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WhoopSyncException(_readWhoopError(response.statusCode, body));
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const WhoopSyncException('WHOOP backend returned invalid JSON.');
      }
      return WhoopSnapshot.fromJson(decoded);
    } on SocketException catch (error) {
      throw WhoopSyncException('Cannot reach WHOOP backend: ${error.message}');
    } on TimeoutException {
      throw const WhoopSyncException('WHOOP backend did not respond in time.');
    } on FormatException {
      throw const WhoopSyncException('WHOOP backend returned invalid JSON.');
    } finally {
      client.close(force: true);
    }
  }

  String _readWhoopError(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Fall through to the generic message below.
    }
    return 'WHOOP sync failed with HTTP $statusCode.';
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.provider,
    required this.signedInAt,
    this.photoUrl = '',
    this.backendToken = '',
    this.expiresAt,
  });

  final String userId;
  final String email;
  final String displayName;
  final String provider;
  final String photoUrl;
  final String backendToken;
  final DateTime signedInAt;
  final DateTime? expiresAt;

  String get shortName {
    final trimmed = displayName.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return email;
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'email': email,
      'displayName': displayName,
      'provider': provider,
      'photoUrl': photoUrl,
      'backendToken': backendToken,
      'signedInAt': signedInAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      provider: json['provider'] as String? ?? 'local',
      photoUrl: json['photoUrl'] as String? ?? '',
      backendToken: json['backendToken'] as String? ?? '',
      signedInAt:
          DateTime.tryParse(json['signedInAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }
}

class AuthBackendClient {
  const AuthBackendClient(this.baseUrl);

  final String baseUrl;

  Future<AuthSession> signInWithGoogle(String idToken) async {
    final json = await _postJson('/api/auth/google', {'idToken': idToken});
    return _sessionFromResponse(json, 'google');
  }

  Future<AuthSession> signInWithLocal({
    required String email,
    required String displayName,
  }) async {
    final json = await _postJson('/api/auth/local', {
      'email': email,
      'displayName': displayName,
    });
    return _sessionFromResponse(json, 'local');
  }

  Future<void> logout(String token) async {
    if (token.trim().isEmpty) {
      return;
    }
    await _postJson('/api/auth/logout', const {}, token: token);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    String token = '',
  }) async {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      throw const AuthException('Set a backend URL first.');
    }

    final uri = Uri.parse('$trimmed$path');
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      if (token.trim().isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final responseBody = await utf8.decodeStream(response);

      if (response.statusCode == 204) {
        return const {};
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(_readAuthError(response.statusCode, responseBody));
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const AuthException('Auth backend returned invalid JSON.');
      }
      return decoded;
    } on SocketException catch (error) {
      throw AuthException('Cannot reach auth backend: ${error.message}');
    } on TimeoutException {
      throw const AuthException('Auth backend did not respond in time.');
    } on FormatException {
      throw const AuthException('Auth backend returned invalid JSON.');
    } finally {
      client.close(force: true);
    }
  }

  AuthSession _sessionFromResponse(Map<String, dynamic> json, String provider) {
    final user = Map<String, dynamic>.from(json['user'] as Map? ?? {});
    final session = Map<String, dynamic>.from(json['session'] as Map? ?? {});
    final email = user['email'] as String? ?? '';
    return AuthSession(
      userId: user['id'] as String? ?? email,
      email: email,
      displayName: user['displayName'] as String? ?? email,
      provider: user['provider'] as String? ?? provider,
      photoUrl: user['photoUrl'] as String? ?? '',
      backendToken: session['token'] as String? ?? '',
      signedInAt:
          DateTime.tryParse(session['createdAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(session['expiresAt'] as String? ?? ''),
    );
  }

  String _readAuthError(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Fall through to the generic message below.
    }
    return 'Auth failed with HTTP $statusCode.';
  }
}

class AuthController extends ChangeNotifier {
  static const _storageKey = 'sculptus_auth_v1';
  static const _defaultBackendUrl = String.fromEnvironment(
    'SCULPTUS_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
  static const _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  bool _isLoaded = false;
  bool isBusy = false;
  String errorMessage = '';
  String authBackendUrl = _defaultBackendUrl;
  AuthSession? session;
  Future<void>? _googleInitialization;

  bool get isLoaded => _isLoaded;
  bool get isSignedIn => session != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    authBackendUrl =
        prefs.getString('sculptus_auth_backend_url') ?? authBackendUrl;
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final restored = AuthSession.fromJson(decoded);
        if (restored.expiresAt == null ||
            restored.expiresAt!.isAfter(DateTime.now())) {
          session = restored;
        }
      } on FormatException {
        session = null;
      } on TypeError {
        session = null;
      }
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> signInWithLocal({
    required String email,
    required String displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.contains('@')) {
      _setError('Enter a valid email.');
      return;
    }

    await _runAuthAction(() async {
      AuthSession nextSession;
      try {
        nextSession = await AuthBackendClient(authBackendUrl).signInWithLocal(
          email: normalizedEmail,
          displayName: displayName.trim(),
        );
      } on AuthException {
        nextSession = AuthSession(
          userId: 'local-$normalizedEmail',
          email: normalizedEmail,
          displayName: displayName.trim().isEmpty
              ? normalizedEmail
              : displayName.trim(),
          provider: 'local',
          signedInAt: DateTime.now(),
        );
      }
      session = nextSession;
      await _save();
    });
  }

  Future<void> signInWithGoogle() async {
    await _runAuthAction(() async {
      await _ensureGoogleInitialized();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const AuthException(
          'Google sign-in is not available on this platform.',
        );
      }

      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Google did not return an ID token.');
      }

      session = await AuthBackendClient(
        authBackendUrl,
      ).signInWithGoogle(idToken);
      await _save();
    });
  }

  Future<void> signOut() async {
    final current = session;
    session = null;
    errorMessage = '';
    notifyListeners();
    await _save();

    if (current?.provider == 'google') {
      try {
        await _ensureGoogleInitialized();
        await GoogleSignIn.instance.signOut();
      } on Object {
        // Local sign-out should not be blocked by provider cleanup.
      }
    }
    if (current?.backendToken.trim().isNotEmpty ?? false) {
      try {
        await AuthBackendClient(authBackendUrl).logout(current!.backendToken);
      } on Object {
        // The local session has already been cleared.
      }
    }
  }

  Future<void> updateBackendUrl(String value) async {
    authBackendUrl = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sculptus_auth_backend_url', authBackendUrl);
    notifyListeners();
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = '';
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _ensureGoogleInitialized() {
    _googleInitialization ??= GoogleSignIn.instance.initialize(
      clientId: _googleClientId.isEmpty ? null : _googleClientId,
      serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
    );
    return _googleInitialization!;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (session == null) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(session!.toJson()));
    }
  }

  void _setError(String message) {
    errorMessage = message;
    notifyListeners();
  }
}

class Competition {
  const Competition({
    required this.id,
    required this.name,
    required this.date,
    required this.type,
    required this.createdAt,
    this.targetWeight = 0,
    this.priority = true,
    this.notes = '',
  });

  final String id;
  final String name;
  final DateTime date;
  final String type;
  final double targetWeight;
  final bool priority;
  final String notes;
  final DateTime createdAt;

  int get daysOut =>
      _dateOnly(date).difference(_dateOnly(DateTime.now())).inDays;

  String get phase {
    final days = daysOut;
    if (days < 0) {
      return 'Completed';
    }
    if (days <= 7) {
      return 'Peak week';
    }
    if (days <= 28) {
      return 'Specific prep';
    }
    if (days <= 84) {
      return 'Build phase';
    }
    return 'Base phase';
  }

  Competition copyWith({
    String? id,
    String? name,
    DateTime? date,
    String? type,
    double? targetWeight,
    bool? priority,
    String? notes,
    DateTime? createdAt,
  }) {
    return Competition(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      type: type ?? this.type,
      targetWeight: targetWeight ?? this.targetWeight,
      priority: priority ?? this.priority,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'date': _dateKey(date),
      'type': type,
      'targetWeight': targetWeight,
      'priority': priority,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Competition.fromJson(Map<String, dynamic> json) {
    return Competition(
      id: json['id'] as String? ?? _newId('competition'),
      name: json['name'] as String? ?? 'Competition',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      type: json['type'] as String? ?? 'Race',
      targetWeight: (json['targetWeight'] as num?)?.toDouble() ?? 0,
      priority: json['priority'] as bool? ?? true,
      notes: json['notes'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class UserGoals {
  const UserGoals({
    required this.dailyCalories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.targetWeight,
    required this.competitionDate,
    required this.competitionName,
  });

  final int dailyCalories;
  final double protein;
  final double carbs;
  final double fat;
  final double targetWeight;
  final DateTime competitionDate;
  final String competitionName;

  int get daysToCompetition {
    return _dateOnly(
      competitionDate,
    ).difference(_dateOnly(DateTime.now())).inDays;
  }

  UserGoals copyWith({
    int? dailyCalories,
    double? protein,
    double? carbs,
    double? fat,
    double? targetWeight,
    DateTime? competitionDate,
    String? competitionName,
  }) {
    return UserGoals(
      dailyCalories: dailyCalories ?? this.dailyCalories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      targetWeight: targetWeight ?? this.targetWeight,
      competitionDate: competitionDate ?? this.competitionDate,
      competitionName: competitionName ?? this.competitionName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyCalories': dailyCalories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'targetWeight': targetWeight,
      'competitionDate': _dateKey(competitionDate),
      'competitionName': competitionName,
    };
  }

  factory UserGoals.fromJson(Map<String, dynamic> json) {
    return UserGoals(
      dailyCalories: (json['dailyCalories'] as num?)?.round() ?? 2400,
      protein: (json['protein'] as num?)?.toDouble() ?? 190,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 250,
      fat: (json['fat'] as num?)?.toDouble() ?? 70,
      targetWeight: (json['targetWeight'] as num?)?.toDouble() ?? 185,
      competitionDate:
          DateTime.tryParse(json['competitionDate'] as String? ?? '') ??
          DateTime(DateTime.now().year, 10, 18),
      competitionName: json['competitionName'] as String? ?? 'October Classic',
    );
  }

  static UserGoals initial() {
    final now = DateTime.now();
    var competitionDate = DateTime(now.year, 10, 18);
    if (competitionDate.isBefore(_dateOnly(now))) {
      competitionDate = DateTime(now.year + 1, 10, 18);
    }
    return UserGoals(
      dailyCalories: 2400,
      protein: 190,
      carbs: 250,
      fat: 70,
      targetWeight: 185,
      competitionDate: competitionDate,
      competitionName: 'October Classic',
    );
  }
}

class SculptusState extends ChangeNotifier {
  static const _storageKey = 'sculptus_state_v1';

  bool _isLoaded = false;
  DateTime selectedDate = _dateOnly(DateTime.now());
  UserGoals goals = UserGoals.initial();
  WhoopSnapshot whoop = WhoopSnapshot.empty;
  String whoopBackendUrl = 'http://127.0.0.1:8787';
  final List<Recipe> recipes = [];
  final List<DiaryEntry> entries = [];
  final List<WeightEntry> weights = [];
  final List<ActivityEntry> activities = [];
  final List<StepEntry> stepEntries = [];
  final List<Competition> competitions = [];

  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      _seed();
    } else {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        goals = UserGoals.fromJson(
          Map<String, dynamic>.from(json['goals'] as Map? ?? {}),
        );
        whoop = WhoopSnapshot.fromJson(
          Map<String, dynamic>.from(json['whoop'] as Map? ?? {}),
        );
        whoopBackendUrl = json['whoopBackendUrl'] as String? ?? whoopBackendUrl;
        recipes
          ..clear()
          ..addAll(
            (json['recipes'] as List? ?? const []).map(
              (item) => Recipe.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        entries
          ..clear()
          ..addAll(
            (json['entries'] as List? ?? const []).map(
              (item) => DiaryEntry.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        weights
          ..clear()
          ..addAll(
            (json['weights'] as List? ?? const []).map(
              (item) => WeightEntry.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        activities
          ..clear()
          ..addAll(
            (json['activities'] as List? ?? const []).map(
              (item) => ActivityEntry.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        stepEntries
          ..clear()
          ..addAll(
            (json['stepEntries'] as List? ?? const []).map(
              (item) => StepEntry.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        competitions
          ..clear()
          ..addAll(
            (json['competitions'] as List? ?? const []).map(
              (item) => Competition.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        if (competitions.isEmpty) {
          competitions.add(_competitionFromGoals());
        }
      } on FormatException {
        _seed();
      } on TypeError {
        _seed();
      }
    }

    _sortAll();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_isLoaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(toJson()));
  }

  Map<String, dynamic> toJson() {
    return {
      'goals': goals.toJson(),
      'whoop': whoop.toJson(),
      'whoopBackendUrl': whoopBackendUrl,
      'recipes': recipes.map((recipe) => recipe.toJson()).toList(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'weights': weights.map((entry) => entry.toJson()).toList(),
      'activities': activities.map((entry) => entry.toJson()).toList(),
      'stepEntries': stepEntries.map((entry) => entry.toJson()).toList(),
      'competitions': competitions.map((entry) => entry.toJson()).toList(),
    };
  }

  List<DiaryEntry> entriesFor(DateTime date) {
    final key = _dateKey(date);
    return entries.where((entry) => _dateKey(entry.date) == key).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Nutrition consumedFor(DateTime date) {
    return entriesFor(
      date,
    ).fold<Nutrition>(Nutrition.zero, (sum, entry) => sum + entry.nutrition);
  }

  int remainingCaloriesFor(DateTime date) {
    return goals.dailyCalories - consumedFor(date).calories;
  }

  List<ActivityEntry> activitiesFor(DateTime date) {
    final key = _dateKey(date);
    return activities.where((entry) => _dateKey(entry.date) == key).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int activityBurnFor(DateTime date) {
    return activitiesFor(
      date,
    ).fold<int>(0, (sum, entry) => sum + entry.caloriesBurned);
  }

  List<StepEntry> stepEntriesFor(DateTime date) {
    final key = _dateKey(date);
    return stepEntries.where((entry) => _dateKey(entry.date) == key).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  }

  StepEntry? latestStepsFor(DateTime date) {
    final entries = stepEntriesFor(date);
    return entries.isEmpty ? null : entries.first;
  }

  int stepsFor(DateTime date) {
    return latestStepsFor(date)?.budgetSteps ?? 0;
  }

  int stepBurnFor(DateTime date) {
    return latestStepsFor(date)?.caloriesBurned ?? 0;
  }

  int totalBurnFor(DateTime date) {
    return activityBurnFor(date) + stepBurnFor(date);
  }

  int remainingFoodBudgetFor(DateTime date) {
    return remainingCaloriesFor(date) + totalBurnFor(date);
  }

  int netCaloriesFor(DateTime date) {
    return consumedFor(date).calories - totalBurnFor(date);
  }

  Competition? get primaryCompetition {
    if (competitions.isEmpty) {
      return null;
    }
    final upcoming =
        competitions.where((competition) => competition.daysOut >= 0).toList()
          ..sort((a, b) {
            if (a.priority != b.priority) {
              return a.priority ? -1 : 1;
            }
            return a.date.compareTo(b.date);
          });
    if (upcoming.isNotEmpty) {
      return upcoming.first;
    }
    return competitions.first;
  }

  WeightEntry? get latestWeight {
    if (weights.isEmpty) {
      return null;
    }
    return weights.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  }

  void selectDate(DateTime date) {
    selectedDate = _dateOnly(date);
    notifyListeners();
  }

  Future<void> addEntry(DiaryEntry entry) async {
    entries.add(entry);
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> deleteEntry(String id) async {
    entries.removeWhere((entry) => entry.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> upsertRecipe(Recipe recipe) async {
    final index = recipes.indexWhere((item) => item.id == recipe.id);
    if (index >= 0) {
      recipes[index] = recipe;
    } else {
      recipes.add(recipe);
    }
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> deleteRecipe(String id) async {
    recipes.removeWhere((recipe) => recipe.id == id);
    entries.removeWhere((entry) => entry.recipeId == id);
    notifyListeners();
    await _save();
  }

  Future<void> addWeight(WeightEntry entry) async {
    weights.removeWhere((item) => _dateKey(item.date) == _dateKey(entry.date));
    weights.add(entry);
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> deleteWeight(String id) async {
    weights.removeWhere((entry) => entry.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> addActivity(ActivityEntry entry) async {
    activities.add(entry);
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> deleteActivity(String id) async {
    activities.removeWhere((entry) => entry.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> addStepEntry(StepEntry entry) async {
    stepEntries.add(entry);
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> deleteStepEntry(String id) async {
    stepEntries.removeWhere((entry) => entry.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> updateWhoopBackendUrl(String value) async {
    whoopBackendUrl = value.trim();
    notifyListeners();
    await _save();
  }

  Future<void> applyWhoopSnapshot(WhoopSnapshot snapshot) async {
    final summaryDate = _dateOnly(snapshot.summaryDate ?? selectedDate);
    whoop = snapshot.copyWith(
      connected: true,
      summaryDate: summaryDate,
      lastSyncedAt: snapshot.lastSyncedAt ?? DateTime.now(),
    );

    final workoutCalories = snapshot.todayWorkoutCalories;
    final whoopActivityId = 'whoop-${_dateKey(summaryDate)}';
    activities.removeWhere((entry) => entry.id == whoopActivityId);

    if (workoutCalories > 0) {
      final count = snapshot.todayWorkoutCount;
      final name = count > 1
          ? 'WHOOP workouts ($count)'
          : snapshot.latestWorkoutName.trim().isEmpty
          ? 'WHOOP workout'
          : 'WHOOP ${snapshot.latestWorkoutName.trim()}';
      final notes = [
        'Imported from WHOOP.',
        if (snapshot.latestWorkoutStrain > 0)
          'Strain ${_formatNumber(snapshot.latestWorkoutStrain)}.',
        if (snapshot.latestWorkoutKilojoules > 0)
          '${_formatNumber(snapshot.latestWorkoutKilojoules)} kJ.',
      ].join(' ');
      activities.add(
        ActivityEntry(
          id: whoopActivityId,
          date: summaryDate,
          name: name,
          caloriesBurned: workoutCalories,
          minutes: snapshot.todayWorkoutMinutes,
          notes: notes,
          createdAt: DateTime.now(),
        ),
      );
    }

    final whoopStepId = 'whoop-steps-${_dateKey(summaryDate)}';
    stepEntries.removeWhere((entry) => entry.id == whoopStepId);
    if (snapshot.steps > 0) {
      final recordedAt =
          snapshot.stepsRecordedAt ?? snapshot.lastSyncedAt ?? DateTime.now();
      stepEntries.add(
        StepEntry(
          id: whoopStepId,
          date: summaryDate,
          steps: snapshot.steps,
          projectedSteps: snapshot.steps,
          recordedAt: recordedAt,
          timeLabel: 'WHOOP',
          notes: snapshot.stepsSource.trim().isEmpty
              ? 'Imported from WHOOP.'
              : 'Imported from WHOOP ${snapshot.stepsSource}.',
        ),
      );
    }

    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> disconnectWhoop() async {
    whoop = WhoopSnapshot.empty;
    activities.removeWhere((entry) => entry.id.startsWith('whoop-'));
    stepEntries.removeWhere((entry) => entry.id.startsWith('whoop-steps-'));
    notifyListeners();
    await _save();
  }

  Future<void> upsertCompetition(Competition competition) async {
    final index = competitions.indexWhere((item) => item.id == competition.id);
    if (index >= 0) {
      competitions[index] = competition;
    } else {
      competitions.add(competition);
    }
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> deleteCompetition(String id) async {
    competitions.removeWhere((entry) => entry.id == id);
    if (competitions.isEmpty) {
      competitions.add(_competitionFromGoals());
    }
    _sortAll();
    notifyListeners();
    await _save();
  }

  Future<void> updateGoals(UserGoals nextGoals) async {
    goals = nextGoals;
    notifyListeners();
    await _save();
  }

  void _sortAll() {
    recipes.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    weights.sort((a, b) => b.date.compareTo(a.date));
    activities.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    stepEntries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    competitions.sort((a, b) => a.date.compareTo(b.date));
  }

  Competition _competitionFromGoals() {
    return Competition(
      id: _newId('competition'),
      name: goals.competitionName,
      date: goals.competitionDate,
      type: 'Competition',
      targetWeight: goals.targetWeight,
      createdAt: DateTime.now(),
    );
  }

  void _seed() {
    final today = _dateOnly(DateTime.now());
    goals = UserGoals.initial();
    recipes
      ..clear()
      ..add(
        Recipe(
          id: _newId('recipe'),
          name: 'Legion Chicken Rice',
          servings: 5,
          createdAt: DateTime.now(),
          notes: 'Reliable meal prep base.',
          ingredients: const [
            Ingredient(
              name: 'Chicken breast',
              amount: '2.5 lb cooked',
              nutrition: Nutrition(calories: 1300, protein: 245, fat: 30),
            ),
            Ingredient(
              name: 'Jasmine rice',
              amount: '5 cups cooked',
              nutrition: Nutrition(calories: 1025, protein: 20, carbs: 225),
            ),
            Ingredient(
              name: 'Olive oil',
              amount: '2 tbsp',
              nutrition: Nutrition(calories: 240, fat: 28),
            ),
            Ingredient(
              name: 'Vegetables',
              amount: '5 cups',
              nutrition: Nutrition(calories: 250, protein: 10, carbs: 45),
            ),
          ],
        ),
      );
    entries
      ..clear()
      ..add(
        DiaryEntry(
          id: _newId('entry'),
          date: today,
          name: 'Legion Chicken Rice',
          source: DiarySource.recipe,
          recipeId: recipes.first.id,
          servings: 1,
          nutrition: recipes.first.perServing,
          createdAt: DateTime.now(),
        ),
      );
    weights
      ..clear()
      ..add(WeightEntry(id: _newId('weight'), date: today, weight: 192));
    whoop = WhoopSnapshot.empty;
    activities.clear();
    stepEntries.clear();
    competitions
      ..clear()
      ..add(_competitionFromGoals());
  }
}

class SculptusApp extends StatefulWidget {
  const SculptusApp({super.key});

  @override
  State<SculptusApp> createState() => _SculptusAppState();
}

class _SculptusAppState extends State<SculptusApp> {
  final SculptusState state = SculptusState();
  final AuthController auth = AuthController();

  @override
  void initState() {
    super.initState();
    state.load();
    auth.load();
  }

  @override
  void dispose() {
    state.dispose();
    auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sculptus',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: AnimatedBuilder(
        animation: Listenable.merge([state, auth]),
        builder: (context, _) {
          if (!state.isLoaded || !auth.isLoaded) {
            return const LoadingScreen();
          }
          if (!auth.isSignedIn) {
            return AuthScreen(auth: auth);
          }
          return HomeShell(state: state, auth: auth);
        },
      ),
    );
  }
}

ThemeData _buildTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: _romanRed,
        brightness: Brightness.light,
      ).copyWith(
        primary: _romanRed,
        secondary: _bronze,
        tertiary: _olive,
        surface: _parchment,
        onSurface: _ink,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: _marble,
    fontFamily: 'Avenir',
    appBarTheme: const AppBarTheme(
      backgroundColor: _romanRed,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _parchment,
      indicatorColor: _bronze,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected) ? _ink : _blue,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          fontSize: 12,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _stone),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _stone),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _romanRed, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _romanRed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _romanRed,
        side: const BorderSide(color: _romanRed),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: _romanRed),
    ),
  );
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: _romanRed)),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final displayName = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Panel(
                padding: 18,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _romanRed,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.account_balance,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sculptus',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: _ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: widget.auth.isBusy
                          ? null
                          : widget.auth.signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('authEmailField'),
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: displayName,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('authContinueButton'),
                        onPressed: widget.auth.isBusy
                            ? null
                            : () => widget.auth.signInWithLocal(
                                email: email.text,
                                displayName: displayName.text,
                              ),
                        icon: const Icon(Icons.login),
                        label: const Text('Continue'),
                      ),
                    ),
                    if (widget.auth.errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.auth.errorMessage,
                        style: const TextStyle(
                          color: _romanRed,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: widget.auth.isBusy
                          ? null
                          : () => _showAuthBackendDialog(context),
                      icon: const Icon(Icons.settings),
                      label: const Text('Backend'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAuthBackendDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.auth.authBackendUrl);
    final nextUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auth Backend'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Backend URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextUrl != null) {
      await widget.auth.updateBackendUrl(nextUrl);
    }
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, required this.auth});

  final SculptusState state;
  final AuthController auth;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(state: widget.state),
      DiaryScreen(state: widget.state),
      RecipesScreen(state: widget.state),
      WeightScreen(state: widget.state),
      GoalsScreen(state: widget.state),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance, size: 22),
            SizedBox(width: 10),
            Text(
              'Sculptus',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Today',
            onPressed: () => widget.state.selectDate(DateTime.now()),
            icon: const Icon(Icons.today),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'sign_out') {
                widget.auth.signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(widget.auth.session?.shortName ?? 'Signed in'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'sign_out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: screens[selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed),
            selectedIcon: Icon(Icons.speed),
            label: 'Gauge',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Diary',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Recipes',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight),
            selectedIcon: Icon(Icons.monitor_weight),
            label: 'Weight',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag),
            selectedIcon: Icon(Icons.flag),
            label: 'Events',
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final consumed = state.consumedFor(state.selectedDate);
    final totalBurn = state.totalBurnFor(state.selectedDate);
    final remaining = state.remainingFoodBudgetFor(state.selectedDate);
    final entries = state.entriesFor(state.selectedDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        RomanDayHeader(state: state),
        const SizedBox(height: 12),
        DailySnapshotCard(
          consumed: consumed.calories,
          burned: totalBurn,
          remaining: remaining,
        ),
        const SizedBox(height: 12),
        HomeActivityCard(state: state),
        const SizedBox(height: 12),
        HomeStepsCard(state: state),
        const SizedBox(height: 12),
        HomeFoodCard(state: state, entries: entries, remaining: remaining),
      ],
    );
  }
}

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final entries = state.entriesFor(state.selectedDate);
    final remaining = state.remainingFoodBudgetFor(state.selectedDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        RomanDayHeader(state: state),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                icon: Icons.edit_note,
                title: 'Diary',
                trailing: Text(
                  '$remaining kcal left',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => showQuickFoodDialog(context, state),
                    icon: const Icon(Icons.add),
                    label: const Text('Food'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.recipes.isEmpty
                        ? null
                        : () => showRecipeServingDialog(context, state),
                    icon: const Icon(Icons.soup_kitchen),
                    label: const Text('Recipe'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showRestaurantDialog(context, state),
                    icon: const Icon(Icons.local_dining),
                    label: const Text('Restaurant'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showEstimateDialog(context, state),
                    icon: const Icon(Icons.psychology_alt),
                    label: const Text('Estimate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showActivityDialog(context, state),
                    icon: const Icon(Icons.directions_run),
                    label: const Text('Workout'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showStepsDialog(context, state),
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Steps'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ActivityCard(state: state),
        const SizedBox(height: 12),
        HomeStepsCard(state: state),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const Panel(
            child: EmptyState(
              icon: Icons.restaurant,
              title: 'No entries',
              message: 'Your selected day is clear.',
            ),
          )
        else
          Panel(
            child: Column(
              children: entries
                  .map(
                    (entry) => DiaryEntryRow(
                      entry: entry,
                      onDelete: () => state.deleteEntry(entry.id),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                icon: Icons.menu_book,
                title: 'Recipes',
                action: FilledButton.icon(
                  onPressed: () => showRecipeDialog(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('Recipe'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${state.recipes.length} saved meal prep templates',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (state.recipes.isEmpty)
          const Panel(
            child: EmptyState(
              icon: Icons.menu_book,
              title: 'No recipes',
              message: 'Save a meal prep build once and reuse it daily.',
            ),
          )
        else
          ...state.recipes.map(
            (recipe) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RecipeCard(recipe: recipe, state: state),
            ),
          ),
      ],
    );
  }
}

class WeightScreen extends StatelessWidget {
  const WeightScreen({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final latest = state.latestWeight;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                icon: Icons.monitor_weight,
                title: 'Weight',
                action: FilledButton.icon(
                  onPressed: () => showWeightDialog(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('Weight'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: Icons.scale,
                      label: 'Current',
                      value: latest == null
                          ? '--'
                          : _formatNumber(latest.weight),
                      unit: 'lb',
                      color: _romanRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricTile(
                      icon: Icons.flag,
                      label: 'Target',
                      value: _formatNumber(state.goals.targetWeight),
                      unit: 'lb',
                      color: _olive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(height: 180, child: WeightChart(entries: state.weights)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        WhoopIntegrationCard(state: state),
        const SizedBox(height: 12),
        Panel(
          child: state.weights.isEmpty
              ? const EmptyState(
                  icon: Icons.show_chart,
                  title: 'No weigh-ins',
                  message: 'Log weight to build the trend.',
                )
              : Column(
                  children: state.weights
                      .map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: _parchment,
                            foregroundColor: _romanRed,
                            child: Icon(Icons.monitor_weight),
                          ),
                          title: Text(
                            '${_formatNumber(entry.weight)} lb',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(_displayDate(entry.date)),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            onPressed: () => state.deleteWeight(entry.id),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class WhoopIntegrationCard extends StatefulWidget {
  const WhoopIntegrationCard({super.key, required this.state});

  final SculptusState state;

  @override
  State<WhoopIntegrationCard> createState() => _WhoopIntegrationCardState();
}

class _WhoopIntegrationCardState extends State<WhoopIntegrationCard> {
  bool isSyncing = false;
  String errorMessage = '';

  @override
  Widget build(BuildContext context) {
    final whoop = widget.state.whoop;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.monitor_heart,
            title: 'WHOOP',
            trailing: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          if (!whoop.connected || !whoop.hasUsefulData)
            const EmptyState(
              icon: Icons.watch,
              title: 'Not connected',
              message: 'Recovery, sleep, strain, workout burn, and body data.',
            )
          else ...[
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  foregroundColor: _romanRed,
                  child: Icon(Icons.watch),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        whoop.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        whoop.lastSyncedAt == null
                            ? 'Ready to sync'
                            : 'Synced ${_displayDateTime(whoop.lastSyncedAt!)}',
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 620;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 5 : 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: isWide ? 1.9 : 1.45,
                  children: [
                    MetricTile(
                      icon: Icons.favorite,
                      label: 'Recovery',
                      value: whoop.recoveryScore > 0
                          ? '${whoop.recoveryScore}'
                          : '--',
                      unit: '%',
                      color: _olive,
                    ),
                    MetricTile(
                      icon: Icons.bedtime,
                      label: 'Sleep',
                      value: whoop.sleepPerformance > 0
                          ? '${whoop.sleepPerformance}'
                          : '--',
                      unit: '%',
                      color: _blue,
                    ),
                    MetricTile(
                      icon: Icons.bolt,
                      label: 'Strain',
                      value: whoop.cycleStrain > 0
                          ? _formatNumber(whoop.cycleStrain)
                          : '--',
                      unit: '/21',
                      color: _bronze,
                    ),
                    MetricTile(
                      icon: Icons.local_fire_department,
                      label: 'Workout',
                      value: whoop.todayWorkoutCalories > 0
                          ? '${whoop.todayWorkoutCalories}'
                          : '--',
                      unit: 'kcal',
                      color: _romanRed,
                    ),
                    MetricTile(
                      icon: Icons.directions_walk,
                      label: 'Steps',
                      value: whoop.steps > 0 ? '${whoop.steps}' : '--',
                      unit: 'day',
                      color: _olive,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (whoop.restingHeartRate > 0)
                  RomanChip(label: '${whoop.restingHeartRate} bpm RHR'),
                if (whoop.hrvRmssdMillis > 0)
                  RomanChip(
                    label: '${_formatNumber(whoop.hrvRmssdMillis)} ms HRV',
                  ),
                if (whoop.sleepHours > 0)
                  RomanChip(label: '${_formatNumber(whoop.sleepHours)}h sleep'),
                if (whoop.bodyWeightLb > 0)
                  RomanChip(label: '${_formatNumber(whoop.bodyWeightLb)} lb'),
                if (whoop.stepsSource.trim().isNotEmpty)
                  RomanChip(label: 'Steps: ${whoop.stepsSource}'),
              ],
            ),
          ],
          if (errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage,
              style: const TextStyle(
                color: _romanRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: isSyncing ? null : _syncSelectedDay,
                icon: const Icon(Icons.sync),
                label: const Text('Sync day'),
              ),
              OutlinedButton.icon(
                onPressed: isSyncing ? null : _showBackendDialog,
                icon: const Icon(Icons.settings),
                label: const Text('Backend'),
              ),
              if (whoop.connected)
                OutlinedButton.icon(
                  onPressed: isSyncing ? null : widget.state.disconnectWhoop,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.state.whoopBackendUrl,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncSelectedDay() async {
    if (isSyncing) {
      return;
    }
    setState(() {
      isSyncing = true;
      errorMessage = '';
    });

    try {
      final snapshot = await WhoopApiClient(
        widget.state.whoopBackendUrl,
      ).fetchSummary(widget.state.selectedDate);
      await widget.state.applyWhoopSnapshot(snapshot);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'WHOOP synced for ${_shortDate(widget.state.selectedDate)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
        });
      }
    }
  }

  Future<void> _showBackendDialog() async {
    final controller = TextEditingController(
      text: widget.state.whoopBackendUrl,
    );
    final nextUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WHOOP Backend'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Backend URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (nextUrl != null) {
      await widget.state.updateWhoopBackendUrl(nextUrl);
    }
  }
}

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final goals = state.goals;
    final primary = state.primaryCompetition;
    final upcoming =
        state.competitions
            .where((competition) => competition.daysOut >= 0)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                icon: Icons.flag,
                title: 'Upcoming Events',
                action: FilledButton.icon(
                  onPressed: () => showCompetitionDialog(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('Event'),
                ),
              ),
              const SizedBox(height: 14),
              if (primary == null)
                const EmptyState(
                  icon: Icons.emoji_events,
                  title: 'No events',
                  message: 'Add the competitions you are training toward.',
                )
              else ...[
                Text(
                  primary.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${primary.type} - ${_displayDate(primary.date)} - ${math.max(primary.daysOut, 0)} days',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RomanChip(label: primary.phase),
                    if (primary.targetWeight > 0)
                      RomanChip(
                        label:
                            '${_formatNumber(primary.targetWeight)} lb target',
                      ),
                    if (primary.priority) const RomanChip(label: 'A race'),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (upcoming.isEmpty)
          const Panel(
            child: EmptyState(
              icon: Icons.event_available,
              title: 'No upcoming competitions',
              message: 'Add one event or a full season calendar.',
            ),
          )
        else
          ...upcoming.map(
            (competition) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CompetitionCard(competition: competition, state: state),
            ),
          ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                icon: Icons.tune,
                title: 'Daily Targets',
                action: FilledButton.icon(
                  onPressed: () => showGoalsDialog(context, state),
                  icon: const Icon(Icons.edit),
                  label: const Text('Targets'),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 620;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: isWide ? 4 : 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: isWide ? 1.9 : 1.45,
                    children: [
                      MetricTile(
                        icon: Icons.local_fire_department,
                        label: 'Calories',
                        value: '${goals.dailyCalories}',
                        unit: 'kcal',
                        color: _romanRed,
                      ),
                      MetricTile(
                        icon: Icons.fitness_center,
                        label: 'Protein',
                        value: _formatNumber(goals.protein),
                        unit: 'g',
                        color: _blue,
                      ),
                      MetricTile(
                        icon: Icons.grain,
                        label: 'Carbs',
                        value: _formatNumber(goals.carbs),
                        unit: 'g',
                        color: _olive,
                      ),
                      MetricTile(
                        icon: Icons.water_drop,
                        label: 'Fat',
                        value: _formatNumber(goals.fat),
                        unit: 'g',
                        color: _bronze,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(icon: Icons.cloud_sync, title: 'Data Shape'),
              const SizedBox(height: 10),
              const Text(
                'Local JSON uses separate collections that map cleanly to a future sync backend.',
                style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  RomanChip(label: 'recipes'),
                  RomanChip(label: 'diary_entries'),
                  RomanChip(label: 'activity_entries'),
                  RomanChip(label: 'weight_entries'),
                  RomanChip(label: 'competitions'),
                  RomanChip(label: 'goals'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RomanDayHeader extends StatelessWidget {
  const RomanDayHeader({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _romanRed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _bronze, width: 1.3),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Previous day',
            onPressed: () => state.selectDate(
              state.selectedDate.subtract(const Duration(days: 1)),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Daily Campaign',
                  style: TextStyle(
                    color: _bronze,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _displayDate(state.selectedDate),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Next day',
            onPressed: () => state.selectDate(
              state.selectedDate.add(const Duration(days: 1)),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: _parchment,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stone),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2C241E),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.action,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? action;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _romanRed),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
        ),
        if (trailing != null) trailing!,
        if (action != null) action!,
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CalorieGauge extends StatelessWidget {
  const CalorieGauge({
    super.key,
    required this.consumed,
    required this.target,
    this.activityBurn = 0,
  });

  final int consumed;
  final int target;
  final int activityBurn;

  @override
  Widget build(BuildContext context) {
    final netConsumed = math.max(consumed - activityBurn, 0).toDouble();
    final progress = target <= 0
        ? 0.0
        : (netConsumed / target).clamp(0.0, 1.0).toDouble();
    final remaining = target - consumed + activityBurn;

    return SizedBox(
      width: 126,
      height: 126,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 116,
            height: 116,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              color: remaining >= 0 ? _romanRed : _bronze,
              backgroundColor: _stone,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$remaining',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: remaining >= 0 ? _ink : _romanRed,
                ),
              ),
              const Text(
                'kcal left',
                style: TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MacroBar extends StatelessWidget {
  const MacroBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_formatNumber(value)} / ${_formatNumber(target)}g',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              color: color,
              backgroundColor: _stone,
            ),
          ),
        ],
      ),
    );
  }
}

class DailySnapshotCard extends StatelessWidget {
  const DailySnapshotCard({
    super.key,
    required this.consumed,
    required this.burned,
    required this.remaining,
  });

  final int consumed;
  final int burned;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: CompactStat(
              label: 'Ate',
              value: '$consumed',
              unit: 'kcal',
              color: _romanRed,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CompactStat(
              label: 'Burned',
              value: '$burned',
              unit: 'kcal',
              color: _blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CompactStat(
              label: 'Budget',
              value: '$remaining',
              unit: 'left',
              color: remaining >= 0 ? _olive : _romanRed,
            ),
          ),
        ],
      ),
    );
  }
}

class CompactStat extends StatelessWidget {
  const CompactStat({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _blue,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HomeActivityCard extends StatelessWidget {
  const HomeActivityCard({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final activities = state.activitiesFor(state.selectedDate);
    final burn = state.activityBurnFor(state.selectedDate);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.directions_run,
            title: 'Did you workout?',
            action: FilledButton.icon(
              onPressed: () => showActivityDialog(context, state),
              icon: const Icon(Icons.add),
              label: const Text('Log'),
            ),
          ),
          const SizedBox(height: 12),
          if (activities.isEmpty)
            const Text(
              'CrossFit, HYROX prep, lifting, sport, conditioning.',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RomanChip(label: '$burn kcal'),
                ...activities
                    .take(2)
                    .map((activity) => RomanChip(label: activity.name)),
              ],
            ),
        ],
      ),
    );
  }
}

class HomeStepsCard extends StatelessWidget {
  const HomeStepsCard({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final latest = state.latestStepsFor(state.selectedDate);
    final now = DateTime.now();

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.directions_walk,
            title: 'Steps',
            action: FilledButton.icon(
              onPressed: () => showStepsDialog(context, state),
              icon: const Icon(Icons.add),
              label: const Text('Log'),
            ),
          ),
          const SizedBox(height: 12),
          if (latest == null)
            Text(
              'Current time: ${_displayTime(now)}. Log steps so far and your end-of-day guess.',
              style: const TextStyle(color: _blue, fontWeight: FontWeight.w700),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RomanChip(label: '${latest.steps} at ${latest.timeLabel}'),
                if (latest.projectedSteps > latest.steps)
                  RomanChip(label: '${latest.projectedSteps} projected'),
                RomanChip(label: '${latest.caloriesBurned} kcal'),
              ],
            ),
        ],
      ),
    );
  }
}

class HomeFoodCard extends StatelessWidget {
  const HomeFoodCard({
    super.key,
    required this.state,
    required this.entries,
    required this.remaining,
  });

  final SculptusState state;
  final List<DiaryEntry> entries;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.restaurant_menu,
            title: 'What have you eaten?',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showFoodLookupDialog(context, state),
                  icon: const Icon(Icons.search),
                  label: const Text('Estimate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showQuickFoodDialog(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('Quick add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$remaining kcal left today after logged activity.',
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              'Paste a day like "2 apples, Mexican bowl 800 cals, 10 wings" and Sculptus will make a first-pass estimate.',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
            )
          else
            ...entries
                .take(4)
                .map(
                  (entry) => FoodEntrySummaryRow(
                    entry: entry,
                    onDelete: () => state.deleteEntry(entry.id),
                  ),
                ),
        ],
      ),
    );
  }
}

class FoodEntrySummaryRow extends StatelessWidget {
  const FoodEntrySummaryRow({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  final DiaryEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(entry.source.icon, color: _romanRed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${entry.nutrition.calories} kcal',
            style: const TextStyle(
              color: _romanRed,
              fontWeight: FontWeight.w900,
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class RestaurantBudgetCard extends StatelessWidget {
  const RestaurantBudgetCard({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final remaining = state.remainingFoodBudgetFor(state.selectedDate);
    final totalBurn = state.totalBurnFor(state.selectedDate);
    final color = remaining >= 0 ? _olive : _romanRed;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.local_dining,
            title: 'Restaurant Budget',
            action: FilledButton.icon(
              onPressed: () => showRestaurantDialog(context, state),
              icon: const Icon(Icons.calculate),
              label: const Text('Plan'),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$remaining',
                style: TextStyle(
                  color: color,
                  fontSize: 38,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'kcal available',
                  style: TextStyle(color: _blue, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (totalBurn > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Includes $totalBurn kcal from workouts and steps.',
              style: const TextStyle(color: _blue, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RomanChip(
                label: 'Starter: ${math.max((remaining * 0.25).round(), 0)}',
              ),
              RomanChip(
                label: 'Main: ${math.max((remaining * 0.60).round(), 0)}',
              ),
              RomanChip(
                label: 'Buffer: ${math.max((remaining * 0.15).round(), 0)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final activities = state.activitiesFor(state.selectedDate);
    final burn = state.activityBurnFor(state.selectedDate);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.directions_run,
            title: 'Did You Workout?',
            action: FilledButton.icon(
              onPressed: () => showActivityDialog(context, state),
              icon: const Icon(Icons.add),
              label: const Text('Workout'),
            ),
          ),
          const SizedBox(height: 12),
          if (activities.isEmpty)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Log CrossFit, HYROX training, lifting, sport, or conditioning.',
                    style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => showActivityDialog(context, state),
                  child: const Text('Yes'),
                ),
              ],
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RomanChip(label: '$burn kcal burned'),
                RomanChip(
                  label: '${state.netCaloriesFor(state.selectedDate)} net kcal',
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...activities.map(
              (activity) => ActivityEntryRow(
                entry: activity,
                onDelete: () => state.deleteActivity(activity.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ActivityEntryRow extends StatelessWidget {
  const ActivityEntryRow({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  final ActivityEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (entry.minutes > 0) '${entry.minutes} min',
      '${entry.caloriesBurned} kcal',
    ].join(' - ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _stone)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            foregroundColor: _romanRed,
            child: Icon(Icons.fitness_center),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class DiaryEntryRow extends StatelessWidget {
  const DiaryEntryRow({super.key, required this.entry, required this.onDelete});

  final DiaryEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _stone)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            foregroundColor: _romanRed,
            child: Icon(entry.source.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.source.label} - ${_formatNumber(entry.servings)} serving',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (entry.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _blue, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.nutrition.calories}',
                style: const TextStyle(
                  color: _romanRed,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                '${_formatNumber(entry.nutrition.protein)}p',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class RecipeCard extends StatelessWidget {
  const RecipeCard({super.key, required this.recipe, required this.state});

  final Recipe recipe;
  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final total = recipe.totalNutrition;
    final per = recipe.perServing;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: _romanRed,
                foregroundColor: Colors.white,
                child: Icon(Icons.menu_book),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${recipe.servings} servings - ${recipe.ingredients.length} ingredients',
                      style: const TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Recipe actions',
                onSelected: (value) {
                  if (value == 'edit') {
                    showRecipeDialog(context, state, recipe: recipe);
                  }
                  if (value == 'delete') {
                    state.deleteRecipe(recipe.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RomanChip(label: '${per.calories} kcal per'),
              RomanChip(label: '${_formatNumber(per.protein)}g protein'),
              RomanChip(label: '${total.calories} kcal batch'),
            ],
          ),
          if (recipe.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(recipe.notes, style: const TextStyle(color: _blue)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      showRecipeServingDialog(context, state, preset: recipe),
                  icon: const Icon(Icons.add),
                  label: const Text('Log'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      showRecipeDialog(context, state, recipe: recipe),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CompetitionCard extends StatelessWidget {
  const CompetitionCard({
    super.key,
    required this.competition,
    required this.state,
  });

  final Competition competition;
  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: competition.priority ? _romanRed : _blue,
                foregroundColor: Colors.white,
                child: const Icon(Icons.emoji_events),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      competition.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${competition.type} - ${_displayDate(competition.date)}',
                      style: const TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Event actions',
                onSelected: (value) {
                  if (value == 'edit') {
                    showCompetitionDialog(
                      context,
                      state,
                      competition: competition,
                    );
                  }
                  if (value == 'delete') {
                    state.deleteCompetition(competition.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RomanChip(label: '${math.max(competition.daysOut, 0)} days out'),
              RomanChip(label: competition.phase),
              if (competition.targetWeight > 0)
                RomanChip(
                  label: '${_formatNumber(competition.targetWeight)} lb',
                ),
              if (competition.priority) const RomanChip(label: 'Priority'),
            ],
          ),
          if (competition.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(competition.notes, style: const TextStyle(color: _blue)),
          ],
        ],
      ),
    );
  }
}

class RomanChip extends StatelessWidget {
  const RomanChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stone),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: _bronze, size: 34),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _blue, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.entries});

  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WeightChartPainter(entries),
      child: const SizedBox.expand(),
    );
  }
}

class WeightChartPainter extends CustomPainter {
  const WeightChartPainter(this.entries);

  final List<WeightEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = _stone
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = _romanRed
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = const Color(0x227A2738)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axisPaint);
    }

    final sorted = entries.toList()..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.length < 2) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'Log two weigh-ins for a trend',
          style: TextStyle(color: _blue, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, size.height / 2 - 10),
      );
      return;
    }

    final minWeight = sorted.map((entry) => entry.weight).reduce(math.min);
    final maxWeight = sorted.map((entry) => entry.weight).reduce(math.max);
    final range = math.max(maxWeight - minWeight, 1);
    final points = <Offset>[];

    for (var i = 0; i < sorted.length; i++) {
      final x = sorted.length == 1
          ? size.width / 2
          : size.width * (i / (sorted.length - 1));
      final normalized = (sorted[i].weight - minWeight) / range;
      final y = size.height - (normalized * (size.height - 20)) - 10;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final pointPaint = Paint()
      ..color = _bronze
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 4.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WeightChartPainter oldDelegate) {
    return oldDelegate.entries != entries;
  }
}

Future<void> _disposeControllersAfterDialog(
  List<TextEditingController> controllers,
) async {
  // These controllers are captured by transient dialog routes. Disposing them
  // from the caller can race Flutter's route teardown and crash active fields.
}

Future<void> showFoodLookupDialog(
  BuildContext context,
  SculptusState state,
) async {
  final description = TextEditingController();

  final result = await showDialog<DiaryEntry>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final estimate = estimateFoodText(description.text);

          return AlertDialog(
            title: const Text('Estimate Food'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: description,
                    minLines: 5,
                    maxLines: 9,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Paste what you ate',
                      hintText:
                          '2 apples\nMexican bowl 800 cals\n400g cantaloupe\n10 chicken wings',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (estimate.items.isEmpty)
                    const Text(
                      'Try foods like apples, bananas, eggs, Greek yogurt, cantaloupe, wings, spring rolls, dumplings, pasta, meatballs, falafel, hummus, rice, whey, berries, and explicit calories.',
                      style: TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        RomanChip(label: '${estimate.calories} kcal likely'),
                        RomanChip(
                          label:
                              '${estimate.lowCalories}-${estimate.highCalories} range',
                        ),
                        if (estimate.protein > 0)
                          RomanChip(
                            label:
                                '${_formatNumber(estimate.protein)}g protein',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...estimate.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: _olive,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              '${item.calories}',
                              style: const TextStyle(
                                color: _romanRed,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: estimate.items.isEmpty
                    ? null
                    : () {
                        Navigator.pop(
                          context,
                          DiaryEntry(
                            id: _newId('entry'),
                            date: state.selectedDate,
                            name: 'Food estimate',
                            source: DiarySource.estimate,
                            createdAt: DateTime.now(),
                            nutrition: Nutrition(
                              calories: estimate.calories,
                              protein: estimate.protein,
                            ),
                            notes:
                                'Range ${estimate.lowCalories}-${estimate.highCalories} kcal\n${estimate.notes}',
                          ),
                        );
                      },
                child: const Text('Log estimate'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null) {
    await state.addEntry(result);
  }
}

Future<void> showQuickFoodDialog(
  BuildContext context,
  SculptusState state,
) async {
  final name = TextEditingController();
  final calories = TextEditingController();
  final protein = TextEditingController();
  final carbs = TextEditingController();
  final fat = TextEditingController();

  final result = await showDialog<DiaryEntry>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Add Food'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              NumberField(controller: calories, label: 'Calories'),
              const SizedBox(height: 10),
              NumberField(controller: protein, label: 'Protein g'),
              const SizedBox(height: 10),
              NumberField(controller: carbs, label: 'Carbs g'),
              const SizedBox(height: 10),
              NumberField(controller: fat, label: 'Fat g'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final entryName = name.text.trim();
              if (entryName.isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                DiaryEntry(
                  id: _newId('entry'),
                  date: state.selectedDate,
                  name: entryName,
                  source: DiarySource.quick,
                  createdAt: DateTime.now(),
                  nutrition: Nutrition(
                    calories: _readInt(calories.text),
                    protein: _readDouble(protein.text),
                    carbs: _readDouble(carbs.text),
                    fat: _readDouble(fat.text),
                  ),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      );
    },
  );

  if (result != null) {
    await state.addEntry(result);
  }
  await _disposeControllersAfterDialog([name, calories, protein, carbs, fat]);
}

Future<void> showEstimateDialog(
  BuildContext context,
  SculptusState state,
) async {
  final name = TextEditingController();
  final calories = TextEditingController();
  final protein = TextEditingController();
  final low = TextEditingController();
  final high = TextEditingController();
  final notes = TextEditingController();

  final result = await showDialog<DiaryEntry>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Log Estimate'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use this for restaurant meals, menu lookups, or ChatGPT-style calorie ranges.',
                style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Meal'),
              ),
              const SizedBox(height: 10),
              NumberField(
                controller: calories,
                label: 'Best estimate calories',
              ),
              const SizedBox(height: 10),
              NumberField(controller: protein, label: 'Protein g'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: NumberField(controller: low, label: 'Low'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NumberField(controller: high, label: 'High'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText:
                      'Example: salmon, yellow rice, cauliflower; log 850',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final entryName = name.text.trim();
              if (entryName.isEmpty) {
                return;
              }
              final lowCalories = _readInt(low.text);
              final highCalories = _readInt(high.text);
              final range = lowCalories > 0 && highCalories > 0
                  ? 'Range $lowCalories-$highCalories kcal'
                  : '';
              final noteParts = [
                if (range.isNotEmpty) range,
                if (notes.text.trim().isNotEmpty) notes.text.trim(),
              ];
              Navigator.pop(
                context,
                DiaryEntry(
                  id: _newId('entry'),
                  date: state.selectedDate,
                  name: entryName,
                  source: DiarySource.estimate,
                  createdAt: DateTime.now(),
                  nutrition: Nutrition(
                    calories: _readInt(calories.text),
                    protein: _readDouble(protein.text),
                  ),
                  notes: noteParts.join(' - '),
                ),
              );
            },
            child: const Text('Log'),
          ),
        ],
      );
    },
  );

  if (result != null) {
    await state.addEntry(result);
  }
  await _disposeControllersAfterDialog([
    name,
    calories,
    protein,
    low,
    high,
    notes,
  ]);
}

Future<void> showActivityDialog(
  BuildContext context,
  SculptusState state,
) async {
  final name = TextEditingController(text: 'CrossFit');
  final calories = TextEditingController();
  final minutes = TextEditingController();
  final notes = TextEditingController();

  final result = await showDialog<ActivityEntry>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Did You Workout?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('CrossFit 370'),
                    onPressed: () {
                      name.text = 'CrossFit';
                      calories.text = '370';
                    },
                  ),
                  ActionChip(
                    label: const Text('HYROX prep'),
                    onPressed: () {
                      name.text = 'HYROX prep';
                      minutes.text = '60';
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Workout'),
              ),
              const SizedBox(height: 10),
              NumberField(controller: calories, label: 'Calories burned'),
              const SizedBox(height: 10),
              NumberField(controller: minutes, label: 'Minutes'),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final workoutName = name.text.trim().isEmpty
                  ? 'Workout'
                  : name.text.trim();
              final burned = _readInt(calories.text);
              if (burned <= 0) {
                return;
              }
              Navigator.pop(
                context,
                ActivityEntry(
                  id: _newId('activity'),
                  date: state.selectedDate,
                  name: workoutName,
                  caloriesBurned: burned,
                  minutes: _readInt(minutes.text),
                  notes: notes.text.trim(),
                  createdAt: DateTime.now(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (result != null) {
    await state.addActivity(result);
  }
  await _disposeControllersAfterDialog([name, calories, minutes, notes]);
}

Future<void> showStepsDialog(BuildContext context, SculptusState state) async {
  final now = DateTime.now();
  final steps = TextEditingController();
  final projectedSteps = TextEditingController();
  final timeLabel = TextEditingController(text: _displayTime(now));
  final notes = TextEditingController();

  final result = await showDialog<StepEntry>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final currentSteps = _readInt(steps.text);
          final projected = _readInt(projectedSteps.text);
          final budgetSteps = math.max(currentSteps, projected);
          final stepCalories = (budgetSteps * 0.05).round();

          void setProjection(int value) {
            projectedSteps.text = value.toString();
            setDialogState(() {});
          }

          return AlertDialog(
            title: const Text('Log Steps'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current time: ${_displayTime(now)}',
                    style: const TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('5k now'),
                        onPressed: () {
                          steps.text = '5000';
                          setDialogState(() {});
                        },
                      ),
                      ActionChip(
                        label: const Text('10k guess'),
                        onPressed: () => setProjection(10000),
                      ),
                      ActionChip(
                        label: const Text('12k guess'),
                        onPressed: () => setProjection(12000),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  NumberField(
                    controller: steps,
                    label: 'Steps so far',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: timeLabel,
                    decoration: const InputDecoration(labelText: 'As of'),
                  ),
                  const SizedBox(height: 10),
                  NumberField(
                    controller: projectedSteps,
                    label: 'Projected total today',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  RomanChip(label: '$stepCalories kcal budget estimate'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: budgetSteps <= 0
                    ? null
                    : () {
                        Navigator.pop(
                          context,
                          StepEntry(
                            id: _newId('steps'),
                            date: state.selectedDate,
                            steps: currentSteps,
                            projectedSteps: projected,
                            recordedAt: now,
                            timeLabel: timeLabel.text.trim().isEmpty
                                ? _displayTime(now)
                                : timeLabel.text.trim(),
                            notes: notes.text.trim(),
                          ),
                        );
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null) {
    await state.addStepEntry(result);
  }
  await _disposeControllersAfterDialog([
    steps,
    projectedSteps,
    timeLabel,
    notes,
  ]);
}

Future<void> showRestaurantDialog(
  BuildContext context,
  SculptusState state,
) async {
  final remaining = state.remainingFoodBudgetFor(state.selectedDate);
  final restaurant = TextEditingController();
  final itemCalories = TextEditingController(
    text: math.max(remaining, 0).toString(),
  );
  final protein = TextEditingController();
  final carbs = TextEditingController();
  final fat = TextEditingController();
  final servings = TextEditingController(text: '1');

  final result = await showDialog<DiaryEntry>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final caloriesPer = _readDouble(itemCalories.text);
          final servingCount = _readDouble(servings.text, 1);
          final totalCalories = (caloriesPer * servingCount).round();
          final maxServing = caloriesPer <= 0 ? 0.0 : remaining / caloriesPer;

          void refresh() => setDialogState(() {});

          return AlertDialog(
            title: const Text('Restaurant Plan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$remaining kcal available for ${_shortDate(state.selectedDate)}',
                    style: const TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: restaurant,
                    decoration: const InputDecoration(labelText: 'Meal name'),
                  ),
                  const SizedBox(height: 10),
                  NumberField(
                    controller: itemCalories,
                    label: 'Calories per serving',
                    onChanged: (_) => refresh(),
                  ),
                  const SizedBox(height: 10),
                  NumberField(
                    controller: servings,
                    label: 'Servings',
                    onChanged: (_) => refresh(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: RomanChip(
                          label:
                              'Max ${_formatNumber(math.max(maxServing, 0.0))} servings',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: RomanChip(label: '$totalCalories kcal')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  NumberField(controller: protein, label: 'Protein g'),
                  const SizedBox(height: 10),
                  NumberField(controller: carbs, label: 'Carbs g'),
                  const SizedBox(height: 10),
                  NumberField(controller: fat, label: 'Fat g'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final entryName = restaurant.text.trim().isEmpty
                      ? 'Restaurant meal'
                      : restaurant.text.trim();
                  Navigator.pop(
                    context,
                    DiaryEntry(
                      id: _newId('entry'),
                      date: state.selectedDate,
                      name: entryName,
                      source: DiarySource.restaurant,
                      servings: servingCount,
                      createdAt: DateTime.now(),
                      nutrition: Nutrition(
                        calories: totalCalories,
                        protein: _readDouble(protein.text) * servingCount,
                        carbs: _readDouble(carbs.text) * servingCount,
                        fat: _readDouble(fat.text) * servingCount,
                      ),
                    ),
                  );
                },
                child: const Text('Log'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null) {
    await state.addEntry(result);
  }
  await _disposeControllersAfterDialog([
    restaurant,
    itemCalories,
    protein,
    carbs,
    fat,
    servings,
  ]);
}

Future<void> showRecipeServingDialog(
  BuildContext context,
  SculptusState state, {
  Recipe? preset,
}) async {
  Recipe selected = preset ?? state.recipes.first;
  final servings = TextEditingController(text: '1');

  final result = await showDialog<DiaryEntry>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final servingCount = _readDouble(servings.text, 1);
          final nutrition = selected.perServing.scale(servingCount);

          return AlertDialog(
            title: const Text('Log Recipe'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selected.id,
                    decoration: const InputDecoration(labelText: 'Recipe'),
                    items: state.recipes
                        .map(
                          (recipe) => DropdownMenuItem(
                            value: recipe.id,
                            child: Text(recipe.name),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id == null) {
                        return;
                      }
                      setDialogState(() {
                        selected = state.recipes.firstWhere(
                          (recipe) => recipe.id == id,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  NumberField(
                    controller: servings,
                    label: 'Servings',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      RomanChip(label: '${nutrition.calories} kcal'),
                      RomanChip(
                        label: '${_formatNumber(nutrition.protein)}g protein',
                      ),
                      RomanChip(
                        label: '${_formatNumber(nutrition.carbs)}g carbs',
                      ),
                      RomanChip(label: '${_formatNumber(nutrition.fat)}g fat'),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    DiaryEntry(
                      id: _newId('entry'),
                      date: state.selectedDate,
                      name: selected.name,
                      source: DiarySource.recipe,
                      recipeId: selected.id,
                      servings: servingCount,
                      createdAt: DateTime.now(),
                      nutrition: nutrition,
                    ),
                  );
                },
                child: const Text('Log'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null) {
    await state.addEntry(result);
  }
  await _disposeControllersAfterDialog([servings]);
}

Future<void> showRecipeDialog(
  BuildContext context,
  SculptusState state, {
  Recipe? recipe,
}) async {
  final name = TextEditingController(text: recipe?.name ?? '');
  final servings = TextEditingController(text: '${recipe?.servings ?? 4}');
  final notes = TextEditingController(text: recipe?.notes ?? '');
  final ingredients = TextEditingController(
    text: recipe == null ? '' : _ingredientsToText(recipe.ingredients),
  );

  final result = await showDialog<Recipe>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(recipe == null ? 'New Recipe' : 'Edit Recipe'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Recipe name'),
              ),
              const SizedBox(height: 10),
              NumberField(controller: servings, label: 'Servings'),
              const SizedBox(height: 10),
              TextField(
                controller: ingredients,
                minLines: 7,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Ingredients',
                  hintText: 'Chicken breast, 640, 120, 0, 14',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsedIngredients = _parseIngredients(ingredients.text);
              final recipeName = name.text.trim();
              if (recipeName.isEmpty || parsedIngredients.isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                Recipe(
                  id: recipe?.id ?? _newId('recipe'),
                  name: recipeName,
                  servings: math.max(_readInt(servings.text, 1), 1),
                  ingredients: parsedIngredients,
                  createdAt: recipe?.createdAt ?? DateTime.now(),
                  notes: notes.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (result != null) {
    await state.upsertRecipe(result);
  }
  await _disposeControllersAfterDialog([name, servings, notes, ingredients]);
}

String _ingredientsToText(List<Ingredient> ingredients) {
  return ingredients
      .map((ingredient) {
        final parts = [
          ingredient.name,
          ingredient.nutrition.calories.toString(),
          _formatNumber(ingredient.nutrition.protein),
          _formatNumber(ingredient.nutrition.carbs),
          _formatNumber(ingredient.nutrition.fat),
          if (ingredient.amount.trim().isNotEmpty) ingredient.amount,
        ];
        return parts.join(', ');
      })
      .join('\n');
}

List<Ingredient> _parseIngredients(String raw) {
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);

  return lines.map((line) {
    final parts = line.split(',').map((part) => part.trim()).toList();
    final name = parts.isEmpty || parts.first.isEmpty ? 'Ingredient' : parts[0];
    final calories = parts.length > 1 ? _readInt(parts[1]) : 0;
    final protein = parts.length > 2 ? _readDouble(parts[2]) : 0.0;
    final carbs = parts.length > 3 ? _readDouble(parts[3]) : 0.0;
    final fat = parts.length > 4 ? _readDouble(parts[4]) : 0.0;
    final amount = parts.length > 5 ? parts.sublist(5).join(', ') : '';
    return Ingredient(
      name: name,
      amount: amount,
      nutrition: Nutrition(
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
      ),
    );
  }).toList();
}

Future<void> showWeightDialog(BuildContext context, SculptusState state) async {
  DateTime selected = state.selectedDate;
  final weight = TextEditingController(
    text: state.latestWeight == null
        ? ''
        : _formatNumber(state.latestWeight!.weight),
  );

  final result = await showDialog<WeightEntry>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Log Weight'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: selected,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selected = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_displayDate(selected)),
                  ),
                  const SizedBox(height: 10),
                  NumberField(controller: weight, label: 'Weight lb'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = _readDouble(weight.text);
                  if (value <= 0) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    WeightEntry(
                      id: _newId('weight'),
                      date: selected,
                      weight: value,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null) {
    await state.addWeight(result);
  }
  await _disposeControllersAfterDialog([weight]);
}

Future<void> showCompetitionDialog(
  BuildContext context,
  SculptusState state, {
  Competition? competition,
}) async {
  DateTime selectedDate = competition?.date ?? state.goals.competitionDate;
  bool priority = competition?.priority ?? true;
  final name = TextEditingController(
    text: competition?.name ?? state.goals.competitionName,
  );
  final type = TextEditingController(text: competition?.type ?? 'HYROX');
  final targetWeight = TextEditingController(
    text: competition == null || competition.targetWeight <= 0
        ? _formatNumber(state.goals.targetWeight)
        : _formatNumber(competition.targetWeight),
  );
  final notes = TextEditingController(text: competition?.notes ?? '');

  final result = await showDialog<Competition>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(competition == null ? 'New Event' : 'Edit Event'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Event name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      hintText: 'HYROX, CrossFit, marathon, photoshoot',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: selectedDate,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_displayDate(selectedDate)),
                  ),
                  const SizedBox(height: 10),
                  NumberField(
                    controller: targetWeight,
                    label: 'Target weight lb',
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: priority,
                    onChanged: (value) {
                      setDialogState(() {
                        priority = value;
                      });
                    },
                    title: const Text('Priority event'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final eventName = name.text.trim();
                  if (eventName.isEmpty) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    Competition(
                      id: competition?.id ?? _newId('competition'),
                      name: eventName,
                      date: selectedDate,
                      type: type.text.trim().isEmpty
                          ? 'Competition'
                          : type.text.trim(),
                      targetWeight: _readDouble(targetWeight.text),
                      priority: priority,
                      notes: notes.text.trim(),
                      createdAt: competition?.createdAt ?? DateTime.now(),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null) {
    await state.upsertCompetition(result);
  }
  await _disposeControllersAfterDialog([name, type, targetWeight, notes]);
}

Future<void> showGoalsDialog(BuildContext context, SculptusState state) async {
  final goals = state.goals;
  final calories = TextEditingController(text: '${goals.dailyCalories}');
  final protein = TextEditingController(text: _formatNumber(goals.protein));
  final carbs = TextEditingController(text: _formatNumber(goals.carbs));
  final fat = TextEditingController(text: _formatNumber(goals.fat));
  final targetWeight = TextEditingController(
    text: _formatNumber(goals.targetWeight),
  );

  final result = await showDialog<UserGoals>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Edit Targets'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NumberField(controller: calories, label: 'Daily calories'),
              const SizedBox(height: 10),
              NumberField(controller: protein, label: 'Protein g'),
              const SizedBox(height: 10),
              NumberField(controller: carbs, label: 'Carbs g'),
              const SizedBox(height: 10),
              NumberField(controller: fat, label: 'Fat g'),
              const SizedBox(height: 10),
              NumberField(controller: targetWeight, label: 'Target weight lb'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                goals.copyWith(
                  dailyCalories: math.max(_readInt(calories.text, 1), 1),
                  protein: _readDouble(protein.text),
                  carbs: _readDouble(carbs.text),
                  fat: _readDouble(fat.text),
                  targetWeight: _readDouble(targetWeight.text),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (result != null) {
    await state.updateGoals(result);
  }
  await _disposeControllersAfterDialog([
    calories,
    protein,
    carbs,
    fat,
    targetWeight,
  ]);
}

class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}
