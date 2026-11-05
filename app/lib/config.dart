/// Default backend URL. Replace with your laptop's LAN IP (it can also be
/// changed at run time on the login screen).
const String kDefaultServer = 'http://192.168.1.10:3000';

/// Path (inside the iOS bundle) of the official Pluto drone model.
/// Leave null to use the built-in placeholder drone made from primitives.
/// Example: 'models.scnassets/pluto.dae'  (see docs/PROJECT_DOCUMENTATION.md)
const String? kPlutoModelPath = null;
const double kPlutoModelScale = 0.01;
