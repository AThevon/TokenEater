# TokenEater - Instructions projet

## Langue

- **GitHub (issues, PRs, commits, branches) : toujours en anglais**
- Conversations avec l'utilisateur : en français (cf. instructions globales)

## Build & Test local

### Prérequis
- **Xcode 16.4** (version identique au CI `macos-15`) — installé via `xcodes install 16.4`
- XcodeGen (`brew install xcodegen`)
- Le `DEVELOPMENT_TEAM` n'est pas dans `project.yml` — il est détecté automatiquement depuis le certificat Apple local

### Toolchain CI (iso-prod)

Le CI (`macos-15`) utilise **Xcode 16.4 / Swift 6.1.2**. Pour builder localement un binaire identique à ce que les users reçoivent via brew cask :

```bash
export DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer
```

**NE PAS** mettre à jour le runner CI vers un Xcode plus récent sans tester — `@Observable` a des bugs d'optimisation en Release avec Swift 6.1.x qui ne se reproduisent pas avec Swift 6.2+. Voir la section Notes techniques.

Pour installer Xcode 16.4 à côté de la version courante :
```bash
brew install xcodes  # si pas déjà installé
xcodes install 16.4 --directory /Applications
```

### Build seul (sans install)
```bash
xcodegen generate
DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2)
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null || true
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM build
```

### Build + Nuke + Install (one-liner)

**Utiliser cette commande pour tester en local.** Elle fait tout d'un coup : build Release, kill les processus, nuke tous les caches (app + widget + chrono + LaunchServices), désenregistre le plugin, installe, réenregistre et lance.

macOS cache agressivement les widget extensions (binaire, timeline, rendu). Le nuke est **obligatoire** sinon l'ancien code reste en mémoire.

```bash
# Build
xcodegen generate && \
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' TokenEaterWidget/Info.plist 2>/dev/null; \
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build 2>&1 | tail -3 && \
\
# Nuke : kill processus + caches + plugin
killall TokenEater 2>/dev/null; killall NotificationCenter 2>/dev/null; killall chronod 2>/dev/null; \
rm -rf ~/Library/Application\ Support/com.tokeneater.shared && \
rm -rf ~/Library/Application\ Support/com.claudeusagewidget.shared && \
rm -rf ~/Library/Group\ Containers/group.com.claudeusagewidget.shared && \
rm -rf /private/var/folders/d6/*/0/com.apple.chrono 2>/dev/null; \
rm -rf /private/var/folders/d6/*/T/com.apple.chrono 2>/dev/null; \
rm -rf /private/var/folders/d6/*/C/com.apple.chrono 2>/dev/null; \
rm -rf /private/var/folders/d6/*/C/com.tokeneater.app 2>/dev/null; \
rm -rf /private/var/folders/d6/*/C/com.claudeusagewidget.app 2>/dev/null; \
pluginkit -r -i com.tokeneater.app.widget 2>/dev/null; \
pluginkit -r -i com.claudeusagewidget.app.widget 2>/dev/null; \
\
# Install + register + launch
sleep 2 && \
rm -rf /Applications/TokenEater.app && \
cp -R build/Build/Products/Release/TokenEater.app /Applications/ && \
xattr -cr /Applications/TokenEater.app && \
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R /Applications/TokenEater.app && \
sleep 2 && \
open /Applications/TokenEater.app
```

#### Ce que fait le nuke (pourquoi chaque étape est nécessaire)

| Étape | Pourquoi |
|-------|----------|
| `killall TokenEater/NotificationCenter/chronod` | L'app et les daemons widget gardent l'ancien binaire en mémoire |
| `rm -rf ~/Library/Application Support/com.tokeneater.shared` | Supprime le JSON partagé (token + cache usage) — repart à zéro |
| `rm -rf ~/Library/Application Support/com.claudeusagewidget.shared` | Supprime l'ancien répertoire partagé (migration) |
| `rm -rf ~/Library/Group Containers/...` | Ancien group container (plus utilisé mais peut rester) |
| `rm -rf /private/var/folders/.../com.apple.chrono` | **Le plus important** : caches WidgetKit de macOS (timeline, rendu, binaire widget). Sans ça, macOS continue d'utiliser l'ancien widget |
| `pluginkit -r` | Désenregistre l'extension widget pour que macOS ne garde pas l'ancienne en mémoire |
| `lsregister -f -R` | Force LaunchServices à re-scanner le .app (sinon macOS peut garder les métadonnées de l'ancienne version) |

**Après l'install** : supprimer l'ancien widget du bureau et en ajouter un nouveau (clic droit → Modifier les widgets → TokenEater).

## Architecture

Le codebase suit **MV Pattern + Repository Pattern + Protocol-Oriented Design** avec `ObservableObject` + `@Published` :

### Layers
- **Models** (`Shared/Models/`) : Structs Codable pures (UsageResponse, ThemeColors, ProxyConfig, MetricModels, PacingModels)
- **Services** (`Shared/Services/`) : I/O single-responsibility avec design protocol-based (APIClient, KeychainService, SharedFileService, NotificationService)
- **Repository** (`Shared/Repositories/`) : Orchestre le pipeline Keychain → API → SharedFile
- **Stores** (`Shared/Stores/`) : Conteneurs d'état `ObservableObject` injectés via `@EnvironmentObject` (UsageStore, ThemeStore, SettingsStore)
- **Helpers** (`Shared/Helpers/`) : Fonctions pures (PacingCalculator, MenuBarRenderer)

### Key Patterns
- **Pas de singletons** — toutes les dépendances sont injectées
- **@EnvironmentObject DI** — les stores sont passés via `.environmentObject()` SwiftUI
- **Services protocol-based** — chaque service a un protocole pour la testabilité
- **Strategy pattern pour les thèmes** — presets ThemeColors + support thème custom

### Partage App/Widget
- **App principale** (sandboxée) : lit le token OAuth depuis le Keychain Claude Code, appelle l'API, écrit les données dans `~/Library/Application Support/com.tokeneater.shared/shared.json`
- **Widget** (sandboxé, read-only) : lit le fichier JSON partagé via `SharedFileService`, affiche les données. Ne touche ni au Keychain ni au réseau.
- Le partage utilise des `temporary-exception` entitlements (pas d'App Groups — incompatible avec les comptes Apple Developer gratuits sur macOS Sequoia)
- Migration automatique depuis l'ancien chemin `com.claudeusagewidget.shared/` — code de migration conservé indéfiniment pour les mises à jour tardives via Homebrew Cask

## Règles SwiftUI — ne pas enfreindre

Leçons apprises à la dure. Chaque règle a causé un bug en production.

### App struct

- **PAS de `@StateObject` dans le `App` struct** — utiliser `private let` pour les stores. `@StateObject` force `App.body` à se ré-évaluer sur chaque `objectWillChange` de n'importe quel store, ce qui cascade dans tout l'arbre de vues. Les stores sont injectés via `.environmentObject()`, les vues enfants les observent individuellement.
- Utiliser `@AppStorage` pour les bindings nécessaires au niveau App (ex: `isInserted` du `MenuBarExtra`), pas un binding vers un store.

### Bindings

- **PAS de binding vers des computed properties** — `$store.computedProp` crée un `LocationProjection` instable que l'AttributeGraph ne peut jamais mémoïser → boucle infinie. Utiliser `@State` local + `.onChange` pour synchroniser.
- **PAS de `Binding(get:set:)`** — les closures ne sont pas `Equatable`, AG voit toujours "différent" → ré-évaluation infinie. Même solution : `@State` + `.onChange`.

### Keychain

- **Toujours utiliser `readOAuthTokenSilently()` (`kSecUseAuthenticationUISkip`)** pour les lectures automatiques (refresh, recovery, popover open). La lecture interactive (`readOAuthToken()`) est réservée **uniquement** au premier connect pendant l'onboarding.
- Ne jamais ajouter de nouveau call site pour `syncKeychainToken()` (interactif) — utiliser `syncKeychainTokenSilently()`.

### Observation framework

- **PAS de `@Observable`** — voir section dédiée ci-dessous.
- **PAS de `@Bindable`** — utiliser `$store.property` via `@EnvironmentObject`.
- **PAS de `@Environment(Store.self)`** — utiliser `@EnvironmentObject var store: Store`.

### Précautions Release builds

- Les bugs SwiftUI se manifestent **uniquement en Release** (optimisations du compilateur + pas d'AnyView wrapping). Toujours tester en Release avec `DEVELOPER_DIR` pointant vers Xcode 16.4 avant de valider un fix SwiftUI.
- `SWIFT_ENABLE_OPAQUE_TYPE_ERASURE` (Xcode 16+) wrappe les vues en `AnyView` en Debug, masquant les problèmes d'identité de vue.

## Notes techniques

- `UserDefaults(suiteName:)` ne fonctionne PAS pour le partage app/widget avec un compte Apple gratuit (Personal Team) — `cfprefsd` vérifie le provisioning profile
- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` retourne une URL sur macOS même sans provisioning valide, mais le sandbox bloque l'accès côté widget
- `FileManager.default.homeDirectoryForCurrentUser` retourne le chemin sandbox container, pas le vrai home — utiliser `getpwuid(getuid())` pour le vrai chemin
- WidgetKit exige `app-sandbox: true` — un widget sans sandbox ne s'affiche pas

### @Observable interdit

**NE PAS utiliser `@Observable`** (Swift 5.9 Observation framework). Le projet utilise `ObservableObject` + `@Published` exclusivement.

Raison : `@Observable` provoque un freeze 100% CPU (boucle infinie de ré-évaluation SwiftUI) en Release builds compilés avec Swift 6.1.x (Xcode 16.4, utilisé par le CI `macos-15`). Le bug ne se reproduit PAS en Debug ni avec Swift 6.2+ (Xcode 26+), ce qui le rend impossible à diagnostiquer localement sans le bon toolchain.

Pattern à utiliser :
- `class Store: ObservableObject` (pas `@Observable`)
- `@Published var property` (pas de propriété nue)
- `@EnvironmentObject var store: Store` (pas `@Environment(Store.self)`)
- `.environmentObject(store)` (pas `.environment(store)`)
- `private let store = Store()` dans l'App struct (pas `@StateObject` ni `@State`)
- `@ObservedObject` pour les sous-vues qui reçoivent un store
- `$store.property` pour les bindings (pas `@Bindable`)

### Test iso-prod (mega nuke)

Pour tester localement un binaire **identique à ce que brew cask livre**, utiliser le workflow `test-build.yml` :
```bash
gh workflow run test-build.yml -f branch=<branche>
# Attendre la fin, puis télécharger le DMG :
gh run download <run-id> -n TokenEater-test -D /tmp/tokeneater-test/
```

Avant d'installer le DMG, faire un mega nuke (inclut UserDefaults + sandbox containers — le nuke standard ne suffit pas) :
```bash
killall TokenEater NotificationCenter chronod cfprefsd 2>/dev/null; sleep 1
defaults delete com.tokeneater.app 2>/dev/null
defaults delete com.claudeusagewidget.app 2>/dev/null
rm -f ~/Library/Preferences/com.tokeneater.app.plist ~/Library/Preferences/com.claudeusagewidget.app.plist
for c in com.tokeneater.app com.tokeneater.app.widget com.claudeusagewidget.app com.claudeusagewidget.app.widget; do
    d="$HOME/Library/Containers/$c/Data"; [ -d "$d" ] && rm -rf "$d/Library/Preferences/"* "$d/Library/Caches/"* "$d/Library/Application Support/"* "$d/tmp/"* 2>/dev/null
done
rm -rf ~/Library/Application\ Support/com.tokeneater.shared ~/Library/Caches/com.tokeneater.app
rm -rf /Applications/TokenEater.app
# Puis: monter DMG, copier .app, xattr -cr, lsregister, lancer manuellement
```
