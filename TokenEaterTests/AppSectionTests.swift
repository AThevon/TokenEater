import Testing
import Foundation

@Suite("NavigationTarget")
struct NavigationTargetTests {

    // MARK: - Top-level spaces

    @Test("top-level space payloads parse to their space")
    func topLevelSpaces() {
        #expect(NavigationTarget.parse("monitoring") == NavigationTarget(space: .monitoring))
        #expect(NavigationTarget.parse("history") == NavigationTarget(space: .history))
        #expect(NavigationTarget.parse("studio") == NavigationTarget(space: .studio))
        #expect(NavigationTarget.parse("settings") == NavigationTarget(space: .settings))
    }

    @Test("legacy dashboard and stats aliases land on monitoring")
    func legacyMonitoringAliases() {
        #expect(NavigationTarget.parse("dashboard") == NavigationTarget(space: .monitoring))
        #expect(NavigationTarget.parse("stats") == NavigationTarget(space: .monitoring))
    }

    // MARK: - Studio surfaces

    @Test("studio.<surface> payloads parse to the studio surface")
    func studioSurfaces() {
        #expect(NavigationTarget.parse("studio.popover")
                == NavigationTarget(space: .studio, studioSection: .popover))
        #expect(NavigationTarget.parse("studio.menuBar")
                == NavigationTarget(space: .studio, studioSection: .menuBar))
        #expect(NavigationTarget.parse("studio.themes")
                == NavigationTarget(space: .studio, studioSection: .themes))
    }

    @Test("bare studio. prefix falls back to the studio space")
    func bareStudioPrefix() {
        #expect(NavigationTarget.parse("studio.") == NavigationTarget(space: .studio))
    }

    @Test("unknown studio surface is rejected")
    func unknownStudioSurface() {
        #expect(NavigationTarget.parse("studio.widgets") == nil)
    }

    // MARK: - Legacy customization payloads remap to Studio

    @Test("legacy flat customization payloads land on their studio surface")
    func legacyFlatCustomizationAliases() {
        #expect(NavigationTarget.parse("themes")
                == NavigationTarget(space: .studio, studioSection: .themes))
        #expect(NavigationTarget.parse("display")
                == NavigationTarget(space: .studio, studioSection: .menuBar))
        #expect(NavigationTarget.parse("popover")
                == NavigationTarget(space: .studio, studioSection: .popover))
    }

    @Test("legacy settings.-prefixed customization payloads land on their studio surface")
    func legacyPrefixedCustomizationAliases() {
        #expect(NavigationTarget.parse("settings.themes")
                == NavigationTarget(space: .studio, studioSection: .themes))
        #expect(NavigationTarget.parse("settings.display")
                == NavigationTarget(space: .studio, studioSection: .menuBar))
        #expect(NavigationTarget.parse("settings.popover")
                == NavigationTarget(space: .studio, studioSection: .popover))
    }

    // MARK: - Settings sections

    @Test("settings.<section> payloads parse to the settings sub-section")
    func settingsSections() {
        for section in SettingsSection.allCases {
            #expect(NavigationTarget.parse("settings.\(section.rawValue)")
                    == NavigationTarget(space: .settings, settingsSection: section))
        }
    }

    @Test("legacy flat settings section names keep working")
    func legacyFlatSettingsSections() {
        #expect(NavigationTarget.parse("general")
                == NavigationTarget(space: .settings, settingsSection: .general))
        #expect(NavigationTarget.parse("notifications")
                == NavigationTarget(space: .settings, settingsSection: .notifications))
    }

    @Test("bare settings. prefix falls back to the settings space")
    func bareSettingsPrefix() {
        #expect(NavigationTarget.parse("settings.") == NavigationTarget(space: .settings))
    }

    @Test("unknown payloads are rejected")
    func unknownPayloads() {
        #expect(NavigationTarget.parse("") == nil)
        #expect(NavigationTarget.parse("settings.performance") == nil)
        #expect(NavigationTarget.parse("nonsense") == nil)
    }

    // MARK: - Enum invariants

    @Test("every space, settings section and studio surface has an icon and a label key")
    func enumMetadata() {
        for space in AppSpace.allCases {
            #expect(!space.iconName.isEmpty)
            #expect(!space.labelKey.isEmpty)
        }
        for section in SettingsSection.allCases {
            #expect(!section.iconName.isEmpty)
            #expect(!section.labelKey.isEmpty)
        }
        for surface in StudioSection.allCases {
            #expect(!surface.iconName.isEmpty)
            #expect(!surface.labelKey.isEmpty)
            #expect(surface.hintKey == surface.labelKey + ".hint")
        }
    }

    @Test("studio context-menu payload round trip: every surface rawValue parses back")
    func studioPayloadRoundTrip() {
        for surface in StudioSection.allCases {
            #expect(NavigationTarget.parse("studio.\(surface.rawValue)")
                    == NavigationTarget(space: .studio, studioSection: surface))
        }
    }
}
