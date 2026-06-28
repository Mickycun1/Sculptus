# Sculptus

Sculptus is a Roman-inspired nutrition and training prep diary built with Flutter for iOS and Android.

## Current MVP

- Simple home screen around today's food, workout, and calorie budget
- Quick food logging
- Pasted-food estimator for common real-world logs like fruit, bowls, wings, dumplings, pasta, yogurt, eggs, and explicit calorie notes
- Restaurant/menu estimate logging with calorie ranges and notes
- Reusable meal prep recipes with per-serving nutrition
- Daily workout/activity burn logging
- Separate step logging with current time and projected end-of-day steps
- Restaurant budget calculator that includes logged activity burn
- Weight log with trend chart
- WHOOP integration surface for recovery, sleep, strain, workout burn, and body data
- Multiple upcoming competitions with prep phase, priority, date, and target weight
- Daily calorie, macro, and target-weight goals
- Local-first persistence through `shared_preferences`

The local JSON state is organized around the same collections a future sync backend would use: `recipes`, `diary_entries`, `activity_entries`, `step_entries`, `weight_entries`, `competitions`, `goals`, and `whoop`.

## WHOOP Integration

WHOOP OAuth needs a backend because the client secret and refresh token must not ship inside the mobile app. The Flutter app syncs from:

```text
GET http://127.0.0.1:8787/api/whoop/summary?date=YYYY-MM-DD
```

The backend uses WHOOP OAuth, refreshes access tokens, then pulls profile, body measurement, recovery, cycle, sleep, and workout data. For local development it can store tokens in memory; for persistent tokens, set `MONGODB_URI` to a MongoDB database. It also exposes:

```text
GET http://127.0.0.1:8787/api/whoop/steps?date=YYYY-MM-DD
```

Current official WHOOP API data does not expose daily step count in the OpenAPI spec. Sculptus has the import path ready and will create a WHOOP step entry if the backend receives an explicit step field, but today this route returns `steps: 0` with `stepsSource: not_available_in_official_whoop_api`. For reliable automatic steps, the next source should be Apple HealthKit on iOS and Google Fit/Health Connect on Android.

Setup:

```sh
cd backend
cp .env.example .env
npm install
npm run dev
```

You do not need MongoDB for a first local test. Leave `MONGODB_URI=` blank and the backend will use in-memory token storage. That means you will need to reconnect WHOOP after restarting the backend.

For persistent WHOOP tokens, use MongoDB Atlas or local Mongo and set both values in `backend/.env`:

```env
MONGODB_URI=mongodb+srv://USER:PASSWORD@cluster.mongodb.net/
MONGODB_DB=sculptus
```

If a database password was pasted into chat or logs, rotate it in Atlas first, then put the rotated value only in `backend/.env`. The backend uses `MONGODB_DB` explicitly, so a cluster-root Atlas URI will still write to the `sculptus` database instead of MongoDB's default `test` database.

Create an app in the WHOOP Developer Dashboard, set the redirect URL to:

```text
http://127.0.0.1:8787/api/whoop/callback
```

Then put `WHOOP_CLIENT_ID` and `WHOOP_CLIENT_SECRET` in `backend/.env`, open:

```text
http://127.0.0.1:8787/api/whoop/connect
```

and authorize the returned `authorizationUrl`. After authorization, use the WHOOP card on the Weight screen to sync the selected day. If WHOOP returns workout energy for that date, Sculptus imports it as a WHOOP workout entry so the daily calorie budget updates.

## Run

```sh
flutter pub get
flutter run
```

For a specific emulator or device:

```sh
flutter devices
flutter run -d <device-id>
```

## Verified Builds

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --debug
```

The Android debug APK is written to:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

The iOS simulator app is written to:

```text
build/ios/iphonesimulator/Runner.app
```
