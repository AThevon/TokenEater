# TokenEater - Instructions projet

## Build & Test local

### Prérequis
- Xcode 15+, XcodeGen (`brew install xcodegen`)
- Le `DEVELOPMENT_TEAM` n'est pas dans `project.yml` — le passer en CLI : `DEVELOPMENT_TEAM=S7B8M9JYF4`

### Build
```bash
xcodegen generate
plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' ClaudeUsageWidget/Info.plist 2>/dev/null || true
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageApp -configuration Release -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=S7B8M9JYF4 build
```

### Install local (IMPORTANT : nuclear cleanup obligatoire)

macOS cache agressivement les widget extensions (binaire, timeline, rendu). **À chaque réinstall du widget, il faut TOUT nettoyer** sinon l'ancien code reste en mémoire :

```bash
# 1. Kill tous les processus
killall TokenEater 2>/dev/null; killall NotificationCenter 2>/dev/null; killall chronod 2>/dev/null

# 2. Supprimer les caches widget
rm -rf ~/Library/Application\ Support/com.claudeusagewidget.shared
rm -rf ~/Library/Group\ Containers/group.com.claudeusagewidget.shared
rm -rf /private/var/folders/d6/*/0/com.apple.chrono 2>/dev/null
rm -rf /private/var/folders/d6/*/T/com.apple.chrono 2>/dev/null
rm -rf /private/var/folders/d6/*/C/com.apple.chrono 2>/dev/null
rm -rf /private/var/folders/d6/*/C/com.claudeusagewidget.app 2>/dev/null

# 3. Désenregistrer l'ancien plugin
pluginkit -r -i com.claudeusagewidget.app.widget 2>/dev/null

# 4. Installer
sleep 2
rm -rf /Applications/TokenEater.app
cp -R build/Build/Products/Release/TokenEater.app /Applications/
xattr -cr /Applications/TokenEater.app

# 5. Réenregistrer avec LaunchServices
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R /Applications/TokenEater.app

# 6. Lancer
sleep 2
open /Applications/TokenEater.app
```

**Après l'install** : supprimer l'ancien widget du bureau et en ajouter un nouveau (clic droit → Modifier les widgets → TokenEater).

## Architecture

- **App principale** (sandboxée) : lit le token OAuth depuis le Keychain Claude Code, appelle l'API, écrit les données dans `~/Library/Application Support/com.claudeusagewidget.shared/shared.json`
- **Widget** (sandboxé, read-only) : lit le fichier JSON partagé, affiche les données. Ne touche ni au Keychain ni au réseau.
- Le partage utilise des `temporary-exception` entitlements (pas d'App Groups — incompatible avec les comptes Apple Developer gratuits sur macOS Sequoia)

## Notes techniques

- `UserDefaults(suiteName:)` ne fonctionne PAS pour le partage app/widget avec un compte Apple gratuit (Personal Team) — `cfprefsd` vérifie le provisioning profile
- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` retourne une URL sur macOS même sans provisioning valide, mais le sandbox bloque l'accès côté widget
- `FileManager.default.homeDirectoryForCurrentUser` retourne le chemin sandbox container, pas le vrai home — utiliser `getpwuid(getuid())` pour le vrai chemin
- WidgetKit exige `app-sandbox: true` — un widget sans sandbox ne s'affiche pas
