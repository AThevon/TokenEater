# TokenEater - Instructions projet

## Langue

- **GitHub (issues, PRs, commits, branches) : toujours en anglais**
- Conversations avec l'utilisateur : en français (cf. instructions globales)

## Build & Test local

### Prérequis
- Xcode 15+, XcodeGen (`brew install xcodegen`)
- Le `DEVELOPMENT_TEAM` n'est pas dans `project.yml` — il est détecté automatiquement depuis le certificat Apple local

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

Le codebase suit **MV Pattern + Repository Pattern + Protocol-Oriented Design** avec `@Observable` (Swift 5.9+) :

### Layers
- **Models** (`Shared/Models/`) : Structs Codable pures (UsageResponse, ThemeColors, ProxyConfig, MetricModels, PacingModels)
- **Services** (`Shared/Services/`) : I/O single-responsibility avec design protocol-based (APIClient, KeychainService, SharedFileService, NotificationService)
- **Repository** (`Shared/Repositories/`) : Orchestre le pipeline Keychain → API → SharedFile
- **Stores** (`Shared/Stores/`) : Conteneurs d'état `@Observable` injectés via `@Environment` (UsageStore, ThemeStore, SettingsStore)
- **Helpers** (`Shared/Helpers/`) : Fonctions pures (PacingCalculator, MenuBarRenderer)

### Key Patterns
- **Pas de singletons** — toutes les dépendances sont injectées
- **@Environment DI** — les stores sont passés via l'environment SwiftUI
- **Services protocol-based** — chaque service a un protocole pour la testabilité
- **Strategy pattern pour les thèmes** — presets ThemeColors + support thème custom

### Partage App/Widget
- **App principale** (sandboxée) : lit le token OAuth depuis le Keychain Claude Code, appelle l'API, écrit les données dans `~/Library/Application Support/com.tokeneater.shared/shared.json`
- **Widget** (sandboxé, read-only) : lit le fichier JSON partagé via `SharedFileService`, affiche les données. Ne touche ni au Keychain ni au réseau.
- Le partage utilise des `temporary-exception` entitlements (pas d'App Groups — incompatible avec les comptes Apple Developer gratuits sur macOS Sequoia)
- Migration automatique depuis l'ancien chemin `com.claudeusagewidget.shared/` — code de migration conservé indéfiniment pour les mises à jour tardives via Homebrew Cask

## Notes techniques

- `UserDefaults(suiteName:)` ne fonctionne PAS pour le partage app/widget avec un compte Apple gratuit (Personal Team) — `cfprefsd` vérifie le provisioning profile
- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` retourne une URL sur macOS même sans provisioning valide, mais le sandbox bloque l'accès côté widget
- `FileManager.default.homeDirectoryForCurrentUser` retourne le chemin sandbox container, pas le vrai home — utiliser `getpwuid(getuid())` pour le vrai chemin
- WidgetKit exige `app-sandbox: true` — un widget sans sandbox ne s'affiche pas
