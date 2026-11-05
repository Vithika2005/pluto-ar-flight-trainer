# Viva preparation - likely questions

**Why Flutter?** One code base, widget-based UI, plugins for ARKit, hot reload. Dart is strongly typed and null-safe.
**Why is the simulation separate from the UI?** Testable without a phone; the same logic could drive an Android or web UI.
**Explain the architecture.** UI -> training session -> flight model -> AR scene; app <-> REST API <-> SQLite.
**How does AR placement work?** ARKit detects horizontal planes; a tap does a hit-test returning a world transform; all objects are children of one anchored node.
**What is the state machine and why?** Disarmed, Armed, Taking off, Flying, Landing, Landed. It stops illegal actions (flying while disarmed) like a real flight controller.
**How do the joysticks work?** `Listener` widgets track one pointer each, so both thumbs work at once; output is -1..1, springs back to 0 on release.
**How is hovering simulated?** Velocity eases toward the stick command; zero command means zero velocity, so altitude and position hold.
**Why add wind?** Without drift hovering would be trivial; drift makes corrective stick input a real skill and gives meaningful feedback.
**How does the tutorial validate actions?** Each stage has a rule evaluated every frame on the real simulated state (altitude tolerance, hold timers, distances) - not a canned animation.
**How is the data stored?** Relational schema with foreign keys; users 1-N attempts; tutorial progress has composite primary key (user, stage).
**How are passwords protected?** scrypt with a random salt; constant-time comparison; tokens are HMAC-SHA256 signed with an expiry.
**What happens when the server is down?** Login and saving fail with a clear message; flying still works (limitation: no offline queue).
**What are the limits?** iOS only, simplified physics, placeholder model until the official one is added.
**How would you extend it?** Android via ARCore, real drone link (UDP/WebSocket), instructor dashboard, replay.
**How did you use Git?** Small commits per feature: backend, simulation, UI, docs.
