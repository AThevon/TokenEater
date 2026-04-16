import SwiftUI

struct ResetFormatPicker: View {
    @Binding var selection: ResetDisplayFormat

    var body: some View {
        Picker(String(localized: "settings.reset.format"), selection: $selection) {
            ForEach(ResetDisplayFormat.allCases) { format in
                Text(format.localizedLabel).tag(format)
            }
        }
        .pickerStyle(.menu)
        .font(.system(size: 11))
    }
}
