import SwiftUI

struct MirrorSelectionColumnView: View {
    let title: String
    let items: [String]
    let selection: Binding<String?>

    @State private var searchText = ""

    private var filteredItems: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return items
        }
        return items.filter { matchesFuzzy(item: $0, query: trimmed) }
    }

    private func matchesFuzzy(item: String, query: String) -> Bool {
        if item.localizedCaseInsensitiveContains(query) {
            return true
        }
        let itemChars = Array(item.lowercased())
        let queryChars = Array(query.lowercased())
        var index = 0
        for char in queryChars {
            var found = false
            while index < itemChars.count {
                if itemChars[index] == char {
                    found = true
                    index += 1
                    break
                }
                index += 1
            }
            if !found {
                return false
            }
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            List(selection: selection) {
                ForEach(filteredItems, id: \.self) { item in
                    Text(item)
                        .tag(item)
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 150, minHeight: 180, maxHeight: 220)

            TextField("common.search".localized(), text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
