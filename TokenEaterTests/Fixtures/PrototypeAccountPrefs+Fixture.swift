import Foundation

/// Preferences as a build of the second-account prototype (#284) writes
/// them, after its user turned the second account on and picked Claude Work
/// mode: its segments and elements carry the `work*` kinds next to the
/// regular ones, with that build's field set (id, kind, style, isHidden,
/// options).
enum PrototypeAccountPrefsFixture {
    static let menuBarAll = """
    {"segments":[
      {"id":"8C1D2E3F-0000-4000-8000-000000000001","kind":"session","style":"labelValue","isHidden":false,"options":{}},
      {"id":"8C1D2E3F-0000-4000-8000-000000000002","kind":"weekly","style":"labelValue","isHidden":false,"options":{}},
      {"id":"8C1D2E3F-0000-4000-8000-000000000003","kind":"workSession","style":"labelValue","isHidden":false,"options":{}},
      {"id":"8C1D2E3F-0000-4000-8000-000000000004","kind":"workWeekly","style":"labelValue","isHidden":false,"options":{}},
      {"id":"8C1D2E3F-0000-4000-8000-000000000005","kind":"workSessionPacing","style":"dot","isHidden":true,"options":{}}
    ]}
    """

    static let menuBarWork = """
    {"segments":[
      {"id":"8C1D2E3F-0000-4000-8000-000000000011","kind":"workSession","style":"labelValue","isHidden":false,"options":{}},
      {"id":"8C1D2E3F-0000-4000-8000-000000000012","kind":"workWeeklyPacing","style":"dot","isHidden":false,"options":{}}
    ]}
    """

    static let popoverAll = """
    {"version":2,"showPlanBadge":true,"showRefreshButton":true,"elements":[
      {"id":"9D1D2E3F-0000-4000-8000-000000000001","kind":"session","style":"gaugeRing","width":"half","isHidden":false,"options":{}},
      {"id":"9D1D2E3F-0000-4000-8000-000000000002","kind":"weekly","style":"gaugeRing","width":"half","isHidden":false,"options":{}},
      {"id":"9D1D2E3F-0000-4000-8000-000000000003","kind":"workSession","style":"chip","width":"half","isHidden":false,"options":{}},
      {"id":"9D1D2E3F-0000-4000-8000-000000000004","kind":"workWeekly","style":"chip","width":"half","isHidden":false,"options":{}},
      {"id":"9D1D2E3F-0000-4000-8000-000000000005","kind":"workWeeklyPacing","style":"paceBar","width":"full","isHidden":false,"options":{}}
    ]}
    """

    static let popoverTemplates = """
    [{"id":"AD1D2E3F-0000-4000-8000-000000000001","name":"Both accounts","composition":
      {"version":2,"showPlanBadge":true,"showRefreshButton":true,"elements":[
        {"id":"AD1D2E3F-0000-4000-8000-000000000002","kind":"session","style":"chip","width":"half","isHidden":false,"options":{}},
        {"id":"AD1D2E3F-0000-4000-8000-000000000003","kind":"workSession","style":"chip","width":"half","isHidden":false,"options":{}}
      ]}}]
    """

    static let extraAccounts = """
    [{"service":"Claude Code-credentials-1a2b3c4d","label":"Work","enabled":true}]
    """

    static let heroWindows = #"{"claude":"weekly","claudeWork":"session","codex":"session"}"#

    /// Every key the prototype writes, as it writes them.
    static var prefs: [String: Any] {
        [
            "activeProviderMode": "claudeWork",
            "menuBarComposition": Data(menuBarAll.utf8),
            "menuBarComposition.claudeWork": Data(menuBarWork.utf8),
            "popoverComposition": Data(popoverAll.utf8),
            "popoverComposition.claudeWork": Data(popoverAll.utf8),
            "dashboardComposition.claudeWork": Data(#"{"version":1,"entries":[{"block":"hero","isHidden":false}]}"#.utf8),
            "popoverUserTemplates": Data(popoverTemplates.utf8),
            "extraClaudeAccounts": Data(extraAccounts.utf8),
            "workAccountLabel": "Work",
            "workAccountMenuBarSeeded": true,
            "sessionPacingSamples.1a2b3c4d": Data("[]".utf8),
            "heroWindows": Data(heroWindows.utf8),
        ]
    }
}
