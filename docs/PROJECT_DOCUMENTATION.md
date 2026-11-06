---
title: "Pluto AR Flight Trainer - Project Documentation"
subtitle: "CPAD Lab Examination - Mini Project"
---

**Student name:** Vithika Surve  **Roll no.:** 241071902  **Division:** LY BTECH CE
**Framework used:** Flutter (Dart)  **AR platform:** Apple ARKit (iPhone)
**Source repository:** https://github.com/Vithika2005/pluto-ar-flight-trainer.git (GitHub link)

# 1. Abstract

Learning to fly a drone is difficult for beginners: joystick inputs must be translated into movement in 3D space, and mistakes on a real drone cause crashes and damage. The **Pluto AR Flight Trainer** is a mobile augmented-reality application that lets a beginner practise the basic operations of the Pluto drone safely. A virtual Pluto drone is placed on a real surface using the phone camera and is controlled with virtual joysticks that copy the layout of the Pluto Controller app. A seven-stage guided tutorial and three training missions teach arming, take-off, hovering, directional movement, navigation and landing. Progress, scores and a leaderboard are stored in a backend database.

# 2. Problem statement and objectives

The problem statement is the *AR/XR Flight Simulator* challenge (Domain: drone technology, AR/XR, simulation and interactive learning). Objectives:

1. Show a virtual Pluto drone inside the real camera view and keep it anchored to a surface.
2. Provide virtual throttle, yaw, pitch and roll joysticks plus ARM/DISARM, TAKE OFF and LAND buttons.
3. Simulate arming, take-off, ascent, descent, hover, movement, rotation and landing with a state machine.
4. Teach the complete basic flight procedure with an interactive tutorial that reacts to real user actions.
5. Provide at least three practical missions with scoring.
6. Store users, tutorial progress and mission attempts in a backend database (mandatory for the CPAD exam).
7. Work without a physical drone.

# 3. Technology stack

| Layer | Technology | Why |
|---|---|---|
| Mobile framework (the one CPAD framework used) | **Flutter 3 / Dart 3** | Single code base, fast UI, strong plugin ecosystem |
| AR | **ARKit** via the `arkit_plugin` Flutter package | Plane detection, hit-testing and SceneKit 3D rendering on iPhone |
| Math | `vector_math` | 3D vectors used by the flight model |
| Networking / storage on device | `http`, `shared_preferences` | REST calls, remembering server URL and login token |
| Backend | **Node.js 22** (built-in `http`, `crypto`) | No external dependencies, easy to run |
| Database | **SQLite** (`node:sqlite`) | Relational database in a single file, no server to install |
| Version control | **Git** | Commit history shows incremental development |

# 4. System architecture

```
 iPhone (Flutter app)                                   Laptop
+---------------------------------------------+        +------------------------------+
| UI layer   login / home / progress / AR HUD |        |  Node.js REST API (server.js) |
|    |                                        |  HTTP  |    auth.js  (scrypt + HMAC)   |
| Training sessions (tutorial, missions)      | -----> |    db.js    (SQLite)          |
|    |                                        |  JSON  |  pluto.db: users,             |
| Flight model + state machine (pure Dart)    | <----- |    tutorial_progress,         |
|    |                                        |        |    attempts                   |
| AR layer: ARKit scene (drone, pad, markers) |        +------------------------------+
+---------------------------------------------+
        ^ camera + motion tracking (ARKit)
```

The code is layered so that the simulation (`lib/sim`) does not depend on Flutter or ARKit. This makes it unit-testable without a phone.

| Folder / file | Responsibility |
|---|---|
| `lib/sim/flight_model.dart` | Flight state machine, physics, ground/fence/obstacle handling |
| `lib/sim/tutorial_session.dart` | Seven tutorial stages and their validation rules |
| `lib/sim/mission_session.dart` | Missions 1-3, objectives, scoring, failure rules |
| `lib/sim/training_session.dart` | Common interface, scene description, score function |
| `lib/screens/ar_screen.dart` | ARKit view, placement, 3D nodes, HUD, controls, result dialog |
| `lib/widgets/joystick.dart` | Spring-loaded virtual joystick (multi-touch safe) |
| `lib/services/api.dart` | REST client |
| `backend/server.js, db.js, auth.js` | API routes, SQL schema, password and token handling |

# 5. AR implementation

1. The app opens an `ARKitSceneView` with horizontal plane detection and feature-point display.
2. The user taps a detected surface. A hit-test returns the world position of that point (the *anchor*).
3. A parent node `course` is created at the anchor. The pad, the drone, its shadow, target zones, checkpoints and obstacles are children of this node, so everything stays fixed to the real surface while the user walks around.
4. Each rendered frame the drone node's position and Euler angles are updated from the simulation. The red nose marker shows heading.
5. **Scale:** the course node can be scaled 0.25x / 0.5x / 1x so it fits on a desk or a room floor, and rotated in 45 degree steps (menu).
6. **Interruptions:** if the app goes to the background the simulation pauses; "Re-place course" re-anchors the scene if tracking drifts. The AR view is not available on non-ARKit devices; the app shows a message instead.

The drone is drawn from primitives (box body, arms, four translucent rotors, red nose). To use the official Pluto 3D model, set `kPlutoModelPath` in `lib/config.dart` (section 9.7).

# 6. Flight simulation

## 6.1 Coordinate system and controller mapping

World axes: x right, y up, z toward the pilot, forward at yaw 0 is -z. The pad is at the origin. Mode-2 layout, as in the Pluto Controller app:

| Control | Stick | Effect | Limit |
|---|---|---|---|
| Throttle | Left stick up/down | Climb / descend (vertical speed) | 0.7 m/s |
| Yaw | Left stick right/left | Rotate clockwise / counter-clockwise | 100 deg/s |
| Pitch | Right stick up/down | Move forward / back (along the nose) | 1.0 m/s |
| Roll | Right stick right/left | Move sideways right / left | 1.0 m/s |
| ARM / DISARM | Button | Power the motors on / off (only on ground) | - |
| TAKE OFF | Button | Automatic climb to 0.6 m | 0.5 m/s |
| LAND | Button | Automatic descent | 0.35 m/s |

## 6.2 Simplified dynamics

Each update with time step *dt* (clamped to 50 ms):

* Target velocity: `target = forward * pitch * 1.0 + right * roll * 1.0 + up * throttle * 0.7` (rotated by the current yaw).
* Stabilisation: `velocity += (target - velocity) * (1 - exp(-4 * dt))`. With the sticks released the target is zero, so the drone smoothly stops and holds its altitude (hover).
* `position += velocity * dt`, `yaw += yawRate * dt`.
* Wind (tutorial stage 4, missions 2-3): a bounded random-walk drift of 0.05-0.12 m/s is added to the target, so hovering needs correction.
* Ground detection: when `y <= 0` while flying or landing the drone touches down; an impact faster than 0.5 m/s is a hard landing (counted as a collision).
* Ceiling 2.0 m; square geofence of +/-2.0 m (position clamped, warning shown).
* Obstacles are vertical cylinders. If the drone (radius 0.15 m) overlaps one below its height, it is pushed out and a collision is counted (at most once per 0.8 s).

## 6.3 Flight-state machine

```
 DISARMED --arm--> ARMED --takeOff--> TAKING OFF --(y >= 0.6 m)--> FLYING
     ^                |  (throttle > 35%: manual lift-off)            |  ^
     |                v                                      land     |  | throttle > 50%
  disarm <-------- LANDED <---(touchdown)--- LANDING <---------------+  | (go-around)
                                                  +---------------------+
```

| Command | Allowed in | Otherwise |
|---|---|---|
| ARM | Disarmed | "Drone is already armed." |
| TAKE OFF | Armed, Landed | "Arm the drone before taking off." / "already in the air" |
| LAND | Taking off, Flying | "Arm and take off before landing." / "already on the ground" |
| DISARM | Armed, Landed | "Land the drone before disarming." |
| Stick movement | Flying, Landing (partial), Armed (throttle only) | Ignored on the ground / disarmed |

Invalid commands never change the state; they show a warning and count as an invalid action (small score penalty).

# 7. Guided tutorial and missions

## 7.1 Tutorial (stage advances only when the validation rule is satisfied)

| Stage | Task | Validation rule |
|---|---|---|
| 1 Familiarisation | Practise all stick directions | All 8 stick directions pushed beyond 60% |
| 2 Arming | Press ARM | Flight state leaves *Disarmed* |
| 3 Take-off | Take off and climb | Flying and altitude within 1.0 m +/- 0.12 m for 1.5 s |
| 4 Hovering | Hold the green zone | Inside 0.25 m radius and +/-0.2 m altitude for 5 s; timer resets on drift; hint says which way to correct |
| 5 Directional movement | Fly in 4 directions | At least 0.5 m accumulated movement forward, back, left and right (nose-relative) |
| 6 Navigation | 4 checkpoints in order | Within 0.3 m of the active glowing sphere |
| 7 Landing | Land on the pad and disarm | Touchdown within 0.35 m of the pad centre, then state *Disarmed* |

Commands not yet taught are disabled (e.g. TAKE OFF is blocked before stage 3). Each stage shows an instruction, a corrective hint when the user struggles, a checklist, and a completion message. Completed stages are saved to the database.

## 7.2 Missions

| Mission | Objectives | Extras |
|---|---|---|
| 1 Takeoff and Landing | Arm, take off above 0.8 m, hold 0.8-1.4 m for 3 s, land on pad, disarm | Par time 45 s, limit 150 s |
| 2 Hover and Directional Control | Arm, hold 1.0 m, fly a 0.8 m square (forward, right, back, left) keeping altitude within +/-0.25 m, land | Wind 0.08 m/s; seconds outside the 0.7-1.3 m band are penalised; par 70 s |
| 3 AR Navigation Challenge | Arm, take off, pass 5 gates while avoiding 5 pillars, land | Wind 0.05 m/s; par 100 s, limit 260 s |

**Scoring:** `score = 100 - 10 x collisions - 2 x invalid actions (max 10) - 3 x seconds outside altitude band (max 30) - 0.3 x seconds over par (max 30)`, limited to 0-100. Stars: 3 stars from 85, 2 from 65, otherwise 1. A mission fails after 5 collisions or at the time limit. **Stability** = percentage of airborne time with horizontal speed below 0.25 m/s and vertical speed below 0.25 m/s.

# 8. Backend and database

## 8.1 Schema

```
users(id PK, username UNIQUE, password_hash, created_at)
tutorial_progress(user_id FK -> users, stage 1..7, completed_at, PK(user_id, stage))
attempts(id PK, user_id FK -> users, mode, score 0..100, duration_sec,
         collisions, stability, success, created_at)
```
One user has many attempts and up to seven tutorial-progress rows (1:N relationships). Foreign keys cascade on delete; indexes support the history and leaderboard queries.

## 8.2 REST API

| Method and path | Auth | Purpose |
|---|---|---|
| GET /api/health | no | Connection test |
| POST /api/auth/register | no | Create account, returns token |
| POST /api/auth/login | no | Log in, returns token |
| GET /api/me/summary | yes | Completed tutorial stages, best score per mission |
| POST /api/tutorial/stage | yes | Save a completed tutorial stage (idempotent) |
| POST /api/attempts | yes | Save a tutorial or mission result |
| GET /api/attempts?limit= | yes | Attempt history of the user |
| GET /api/leaderboard?mode= | yes | Top 10 per mode |

**Security:** passwords are hashed with scrypt and a random salt; sessions use HMAC-SHA256 signed tokens that expire after 7 days; all SQL uses parameterised statements; inputs are validated (ranges, enum of modes); request bodies are limited to 100 KB.

# 9. Setup, build and run

## 9.1 Requirements

| Item | Requirement |
|---|---|
| Phone | iPhone 6s or newer (ARKit, A9+), iOS 13 or later |
| Build machine | Mac with Xcode 15+ and Flutter 3.16+ (`flutter doctor` green for iOS) |
| Backend machine | Any laptop with Node.js 22.13+ (can be the same Mac) |
| Network | Phone and laptop on the same Wi-Fi |
| Apple account | Free Apple ID is enough for a personal device (app expires after 7 days) |

## 9.2 Backend

```
cd backend
npm test
npm start
```
The console prints addresses such as `http://192.168.1.23:3000`. Allow incoming connections if the firewall asks.

## 9.3 App project

```
cd app
./setup.sh
```
This generates the `ios/` runner, adds the camera and local-network permission texts to `Info.plist`, sets the iOS deployment target to 13.0 and runs `flutter pub get` and `pod install`.

## 9.4 iPhone preparation

1. Connect the iPhone by cable and tap **Trust**.
2. iOS 16+: Settings > Privacy & Security > **Developer Mode** > On (phone restarts).
3. Open `ios/Runner.xcworkspace` in Xcode > Runner > *Signing & Capabilities* > tick *Automatically manage signing* > choose your Apple ID as Team > change the bundle identifier to something unique (e.g. `com.yourname.plutoar`).

## 9.5 Run

```
flutter devices
flutter run --release -d <your-iphone-id>
```
Use `--release` so the app keeps working when the cable is unplugged. On first launch trust the developer certificate: Settings > General > VPN & Device Management > your Apple ID > Trust. Allow *Camera* and *Local Network* when asked.

## 9.6 Using the app

Enter the server URL, create an account, choose *Guided tutorial* or a mission, point the camera at a floor or table, wait for yellow feature points, tap to place the course, then fly.

## 9.7 Using the official Pluto 3D model

1. Convert the supplied model to `.dae` or `.scn` (Blender, or Xcode > Editor > Convert) and put it in a folder named `models.scnassets`.
2. Drag the folder into the Runner target in Xcode (*Create folder references*, tick *Copy items if needed*).
3. In `lib/config.dart` set `kPlutoModelPath = 'models.scnassets/pluto.dae'` and adjust `kPlutoModelScale` until the size looks right.

## 9.8 Troubleshooting

| Problem | Fix |
|---|---|
| "Cannot reach the server" | Same Wi-Fi? Correct IP and port 3000? Use *Test server connection*; allow Node in the firewall; allow *Local Network* for the app |
| Black screen / no camera | Settings > Privacy > Camera > enable for the app |
| Course cannot be placed | Move the phone slowly over a textured, well-lit surface until yellow points appear |
| `arkit_plugin` compile errors after `pub get` | Pin the version that was used during development (`flutter pub add arkit_plugin:<version>`) |
| Signing error in Xcode | Pick a Team, use a unique bundle identifier |
| App closes after 7 days | Free Apple ID limit; re-run `flutter run --release` |

# 10. Testing

## 10.1 Automated tests

* `backend`: `npm test` - 4 API tests (health, register/login rules, token protection, progress/attempts/leaderboard).
* `app`: `flutter test` - flight-state transitions, invalid commands, controls ignored before arming, forward movement, hover on stick release, geofence, obstacle collision, yaw direction, tutorial stage validation and a full scripted run of Mission 1.

## 10.2 Manual test cases on the iPhone (fill in Result and attach screenshots / video)

| ID | Test | Expected | Result |
|---|---|---|---|
| T1 | Tap a surface | Pad and drone appear and stay fixed when walking around | |
| T2 | Press TAKE OFF while disarmed | Warning "Arm the drone before taking off", state unchanged | |
| T3 | Move sticks while disarmed | Drone does not move | |
| T4 | ARM, TAKE OFF | Drone climbs to about 0.6 m, state FLYING | |
| T5 | Push throttle up / release | Drone climbs, then hovers | |
| T6 | Push pitch up | Drone moves along the red nose direction | |
| T7 | Yaw right | Nose turns clockwise | |
| T8 | Fly into a pillar (Mission 3) | Red warning, haptic, HITS counter increases | |
| T9 | Fly toward the edge | "Out of the flight area" warning, drone stays inside | |
| T10 | Stage 4 drift | Timer resets, hint says which stick to move | |
| T11 | Complete tutorial | 7 stage messages, result dialog, row in database | |
| T12 | Complete Missions 1, 2, 3 | Score and stars shown, attempts visible in *Progress* | |
| T13 | Send app to background and return | Simulation paused until Resume | |
| T14 | Stop the server and finish a mission | App keeps working; result is not saved (known limitation) | |

# 11. Known limitations

* ARKit is available only on iOS; the app is therefore iPhone-only (an Android version would need ARCore).
* Flight physics are intentionally simplified; they teach control logic, not real aerodynamics.
* The scene is anchored with one hit-test point; strong tracking loss can make the course drift (use *Re-place course*).
* Results are saved only when the server is reachable (no offline queue).
* The controller layout follows the standard Mode-2 Pluto layout and should be checked against the Pluto Controller app supplied by the organisers.
* The placeholder drone is built from primitives until the official model is added (section 9.7).
* The backend uses HTTP on a local network; use HTTPS and a strong `TOKEN_SECRET` for any real deployment.

# 12. Future enhancements

Flight-path visualisation, replay, difficulty levels, voice instructions, Android (ARCore) build, optional live connection to a real Pluto drone, instructor dashboard.

# 13. Git workflow

```
git init
git add .
git commit -m "message"
git remote add origin <your-github-url>
git push -u origin main
```
Commit history: backend -> simulation logic -> AR/UI -> documentation.

# 14. References

Apple ARKit and SceneKit documentation; Flutter documentation (flutter.dev); `arkit_plugin` package (pub.dev); Node.js documentation (`node:sqlite`, `crypto`); Pluto drone and Pluto Controller app material provided by the organisers.
