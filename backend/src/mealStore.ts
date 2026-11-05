import { Collection, MongoClient } from "mongodb";

export type SavedMeal = {
  name: string;
  calories: number;
  proteinGrams: number;
};

export interface MealStore {
  list(userId: string): Promise<SavedMeal[]>;
  save(userId: string, meal: SavedMeal): Promise<void>;
  remove(userId: string, name: string): Promise<void>;
  removeAll(userId: string): Promise<void>;
}

const mealKey = (name: string) => name.trim().toLowerCase();

class MemoryMealStore implements MealStore {
  private readonly meals = new Map<string, Map<string, SavedMeal>>();

  async list(userId: string) {
    return [...(this.meals.get(userId)?.values() ?? [])];
  }

  async save(userId: string, meal: SavedMeal) {
    const meals = this.meals.get(userId) ?? new Map<string, SavedMeal>();
    meals.set(mealKey(meal.name), meal);
    this.meals.set(userId, meals);
  }

  async remove(userId: string, name: string) {
    this.meals.get(userId)?.delete(mealKey(name));
  }

  async removeAll(userId: string) {
    this.meals.delete(userId);
  }
}

class MongoMealStore implements MealStore {
  constructor(private readonly collection: Collection) {}

  async list(userId: string) {
    const docs = await this.collection.find({ userId }).sort({ name: 1 }).toArray();
    return docs.map((doc) => ({
      name: doc.name as string,
      calories: doc.calories as number,
      proteinGrams: doc.proteinGrams as number
    }));
  }

  async save(userId: string, meal: SavedMeal) {
    await this.collection.updateOne(
      { userId, key: mealKey(meal.name) },
      { $set: { userId, key: mealKey(meal.name), ...meal, updatedAt: new Date() } },
      { upsert: true }
    );
  }

  async remove(userId: string, name: string) {
    await this.collection.deleteOne({ userId, key: mealKey(name) });
  }

  async removeAll(userId: string) {
    await this.collection.deleteMany({ userId });
  }
}

export async function createMealStore(
  mongoUri: string,
  dbName: string
): Promise<MealStore> {
  if (!mongoUri) {
    return new MemoryMealStore();
  }

  const client = new MongoClient(mongoUri);
  await client.connect();
  const collection = client.db(dbName).collection("meals");
  await collection.createIndex({ userId: 1, key: 1 }, { unique: true });
  return new MongoMealStore(collection);
}
