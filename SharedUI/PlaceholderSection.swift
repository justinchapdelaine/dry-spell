import SwiftUI

struct PlaceholderSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        Section(title) {
            content
        }
    }
}
