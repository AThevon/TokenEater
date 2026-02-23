# Onboarding Stepper Modal — Design Document

**Date:** 2026-02-23
**Issue:** https://github.com/AThevon/TokenEater/issues/12
**Branche:** `feat-onboarding`

## Problème

Au premier lancement, l'app s'ouvre sur SettingsView et demande un accès Keychain sans explication. Pas de contexte, pas de preview, pas d'aide si Claude Code est absent.

## Solution

Stepper modal en 3 étapes avec :
- Switch simplifié/détaillé (dev vs non-dev)
- Preview des données de démo avant connexion
- Permission priming avant le dialogue Keychain
- Guide d'installation Claude Code intégré si absent
- Mention plan Pro/Team requis

## Architecture

### State machine

```
App Launch
  ├── hasCompletedOnboarding == true  → MenuBar normal
  └── hasCompletedOnboarding == false → OnboardingWindow
        ├── Step 1: Welcome
        ├── Step 2: Prérequis (détection Claude Code)
        └── Step 3: Connexion (Keychain + API test)
```

### Persistence

`@AppStorage("hasCompletedOnboarding")` dans `UserDefaults`.
Reset possible depuis Settings.

### Détection Claude Code sans dialogue système

Étape 2 utilise `SecItemCopyMatching` avec `kSecReturnAttributes` (pas `kSecReturnData`) pour vérifier l'existence de l'item Keychain sans déclencher le dialogue mot de passe.

## Étapes

### Étape 1 — Welcome

- Logo TokenEater + baseline
- Preview du widget avec données de démo (mêmes circular gauges que le vrai widget)
- Switch "Simplifié / Détaillé" persistant sur toutes les étapes
- Bouton Continuer

### Étape 2 — Prérequis

**Si Claude Code détecté :**
- Message adapté au mode (simplifié : langage accessible / détaillé : termes techniques)
- Mention "Plan Pro ou Team requis"
- Bouton Continuer

**Si Claude Code absent :**
- Mini-guide pas à pas : installer Claude Code, se connecter, revenir
- Lien vers la page d'installation
- Bouton "Réessayer la détection"
- Bouton Continuer grisé tant que non détecté

### Étape 3 — Connexion

- Permission priming adapté au mode
- Bouton "Autoriser l'accès" → `SecItemCopyMatching` avec `kSecReturnData` → dialogue Keychain
- **Succès :** fetch API → preview données réelles + rappel widget + bouton "Commencer"
- **Échec :** message friendly + réessayer

## Style visuel

- Modale avec SF Symbols, style Raycast/CleanShot
- Navigation dots (● ○ ○)
- Animations douces (fade in, transitions entre étapes)
- Copy : fun, chill, humain — pas de corporate speak ni de AI slop

## Fichiers

| Fichier | Action |
|---------|--------|
| `ClaudeUsageApp/OnboardingView.swift` | Nouveau — Container stepper |
| `ClaudeUsageApp/OnboardingSteps/WelcomeStep.swift` | Nouveau |
| `ClaudeUsageApp/OnboardingSteps/PrerequisiteStep.swift` | Nouveau |
| `ClaudeUsageApp/OnboardingSteps/ConnectionStep.swift` | Nouveau |
| `ClaudeUsageApp/ClaudeUsageApp.swift` | Modifier — Conditionner affichage |
| `ClaudeUsageApp/SettingsView.swift` | Modifier — Bouton reset onboarding |
| `Shared/KeychainOAuthReader.swift` | Modifier — Ajouter méthode `exists()` |
| `Shared/en.lproj/Localizable.strings` | Modifier — Strings onboarding |
| `Shared/fr.lproj/Localizable.strings` | Modifier — Traductions |

## Décisions

- **Public cible :** Mix technique/non-technique (utilisateurs Claude Code)
- **Switch dev/non-dev :** Toggle en haut de la modale, pas deux parcours séparés
- **Claude Code absent :** Guide intégré pas à pas (pas juste un message d'erreur)
- **Copy :** Fun et chill, sera itéré après première implémentation
