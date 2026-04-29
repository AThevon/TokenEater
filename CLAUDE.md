# TokenEater - Project Instructions

## Language

- **GitHub (issues, PRs, commits, branches): always in English**
- Conversations with the user: in English

## Build & Test local

### Prérequis
- **Xcode 16.4** (version identique au CI `macos-15`) - installé via `xcodes install 16.4`
- XcodeGen (`brew install xcodegen`)
- `DEVELOPMENT_TEAM=S7B8M9JYF4` est hardcodé dans `project.yml` (paid Apple Developer Program, post-cert v5.0)

### Statut signing + notarisation (depuis v5.0)

- **Local Release builds** (la commande mega-nuke ci-dessous) -> signés avec **Apple Development** cert via Automatic style, donc Gatekeeper bloque la première ouverture (normal pour un ad-hoc dev build)
- **CI Release builds** (déclenchés par push d'un tag `v*`) -> signés avec **Developer ID Application** cert (importé depuis le secret `APPLE_CERT_P12_BASE64`) + hardened runtime + notarisés via `notarytool` + ticket staplé sur le DMG. Conséquence : les users qui téléchargent le DMG depuis Releases l'ouvrent **sans aucun prompt Gatekeeper**, peu importe le compte macOS
- **Brew cask** (`brew install --cask tokeneater` depuis `AThevon/homebrew-tokeneater`) -> pointe vers le même DMG notarisé, donc même expérience zero-friction. Note : le repo cask doit avoir son `postflight` `xattr -cr` retiré (sinon il strip le ticket de notarisation à l'install)
- **In-app updater** (UpdateService) -> télécharge le DMG depuis le release GitHub, vérifie sa signature EdDSA Sparkle (clé publique embarquée dans `Resources/SparklePublicKey.txt`), puis monte + copie vers `/Applications` via un AppleScript helper avec admin prompt (une fois)
- **App Group** -> `group.com.tokeneater` enregistré dans Developer Portal, ajouté aux App IDs `com.tokeneater.app` + `com.tokeneater.app.widget`. L'entitlement `com.apple.security.application-groups` est dans les deux fichiers `.entitlements`. Path du container : `~/Library/Group Containers/S7B8M9JYF4.group.com.tokeneater/`
- **SharedFileService fallback** -> si le container App Group n'est pas accessible (cas dev avec Personal Team), bascule sur `~/Library/Application Support/com.tokeneater.shared/` automatiquement

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

### Tests unitaires

**80 tests** couvrent la logique métier (stores, repository, pacing, token recovery). Les tests ne couvrent PAS le rendu SwiftUI ni le widget en conditions réelles — pour ça, utiliser le build + nuke + install.

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test
```

**Quand lancer les tests :**
- Avant chaque commit qui touche `Shared/` (stores, services, repository, helpers, models)
- Le CI (`ci.yml`) les lance automatiquement sur chaque PR et push sur main

**Quand tester manuellement (build + nuke + install) :**
- Changements SwiftUI (vues, layout, bindings)
- Changements widget (timeline, rendu)
- Toujours en **Release** avec Xcode 16.4 pour les changements SwiftUI

**Écriture de tests :**
- Framework : Swift Testing (`import Testing`, `@Test`, `#expect`)
- Les mocks sont dans `TokenEaterTests/Mocks/` — chaque service a son mock protocol-based
- Les fixtures sont dans `TokenEaterTests/Fixtures/`
- Les stores sont `@MainActor` → les suites de test doivent aussi être `@MainActor`
- `UserDefaults.standard` est partagé entre tests → utiliser `.serialized` sur les suites qui écrivent dans UserDefaults + nettoyer dans un helper

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
rm -rf ~/Library/Group\ Containers/S7B8M9JYF4.group.com.tokeneater && \
rm -rf ~/Library/Group\ Containers/group.com.tokeneater && \
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

> Note v5.0+ : le `xattr -cr` ci-dessus est uniquement requis pour les ad-hoc dev builds locaux. Les releases officielles passent par `codesign Developer ID` + notarisation dans la CI (voir `release.yml`), donc les DMG livrés aux users ne sont PAS quarantainés et Gatekeeper les accepte au premier lancement sans `xattr` ni approbation manuelle.

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
- **App principale** (non-sandboxée depuis v5.0) : shell-out à `/usr/bin/security find-generic-password -s "Claude Code-credentials"` via `SecurityCLIReader` pour lire le token OAuth, appelle l'API, écrit les données dans le shared container (App Group si dispo, sinon fallback `~/Library/Application Support/com.tokeneater.shared/shared.json`)
- **Widget** (sandboxé, read-only - WidgetKit l'impose) : lit le fichier JSON partagé via `SharedFileService`. Ne touche ni au Keychain ni au réseau.
- Le partage utilise l'App Group `group.com.tokeneater` une fois le Developer Team payant activé (voir `scripts/enable-app-groups.sh` pour réinjecter l'entitlement après réception du cert). Fallback `~/Library/Application Support/com.tokeneater.shared/` tant que l'App Group n'est pas valide.
- Migration automatique depuis l'ancien chemin `com.claudeusagewidget.shared/` → `com.tokeneater.shared/` → App Group. `SharedFileService.init()` gère les deux sauts au premier lancement.
- `LegacyHelperCleanupService` au premier lancement d'une v5.0 désinstalle le LaunchAgent v4.x (`com.tokeneater.helper`) + supprime le binaire + nettoie `keychain-token.json`. Gated par un flag UserDefaults pour ne tourner qu'une fois.

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

- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` retourne l'URL du container App Group si l'entitlement est présent + Team ID valide, sinon nil. `SharedFileService` gère le fallback vers `~/Library/Application Support/com.tokeneater.shared/` pour permettre les dev builds (Personal Team) de fonctionner
- `FileManager.default.homeDirectoryForCurrentUser` retourne le chemin sandbox container pour les vues sandboxées (le widget), pas le vrai home — utiliser `getpwuid(getuid())` pour le vrai chemin (cf. `SharedFileService`)
- WidgetKit exige `app-sandbox: true` — un widget sans sandbox ne s'affiche pas. La main app peut désandboxer (v5.0+) mais pas le widget.
- Planning migration Apple Developer Program : voir `docs/APPLE_DEV_MIGRATION.md` pour le plan complet des phases, ce qui reste à faire après activation du cert, et les secrets GitHub à créer (`APPLE_CERT_P12_BASE64`, `APPLE_CERT_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`)

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
