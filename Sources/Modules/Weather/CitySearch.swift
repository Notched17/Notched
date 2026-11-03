// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// Searching for a city (Open-Meteo's geocoder), shared by the Weather strip on
/// the Today tab and Settings ▸ Weather. Searches as you type, after a pause,
/// and ignores an answer that arrives after a newer search was started.
@MainActor
@Observable
final class CitySearchModel {
    static let minimumLength = 2
    /// How long typing must pause before a search is made.
    static let pause: Duration = .milliseconds(450)

    var query = ""
    private(set) var results: [GeocodeResult] = []
    private(set) var message: String?
    private(set) var isSearching = false

    /// Runs one search. Replaced with the real client by the module.
    @ObservationIgnored var searcher: (String) async throws -> [GeocodeResult] = { _ in [] }
    @ObservationIgnored private var generation = 0

    init(searcher: @escaping (String) async throws -> [GeocodeResult] = { _ in [] }) {
        self.searcher = searcher
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSearch: Bool { trimmedQuery.count >= Self.minimumLength && !isSearching }

    /// Empties the field and the results.
    func reset() {
        generation += 1
        query = ""
        results = []
        message = nil
        isSearching = false
    }

    /// Searches for the current text now. A newer search (or a reset) makes
    /// this one's answer obsolete.
    func search() async {
        let text = trimmedQuery
        guard text.count >= Self.minimumLength else {
            results = []
            message = nil
            return
        }
        generation += 1
        let mine = generation
        isSearching = true
        message = nil
        do {
            let found = try await searcher(text)
            guard mine == generation else { return }
            results = found
            message = found.isEmpty ? "No cities found." : nil
        } catch {
            guard mine == generation else { return }
            results = []
            message = "Couldn't search. Check your connection."
        }
        isSearching = false
    }

    /// For `.task(id: query)`: waits for a pause in typing, then searches.
    /// Cancelled (and so skipped) when the text changes again meanwhile.
    func searchAfterPause() async {
        guard trimmedQuery.count >= Self.minimumLength else {
            results = []
            message = nil
            return
        }
        try? await Task.sleep(for: Self.pause)
        guard !Task.isCancelled else { return }
        await search()
    }
}

/// The inline city picker on the Weather strip: a search field, up to four
/// results, and Cancel. Typing needs keyboard focus, which the island gives
/// only while this is open (the Today tab claims it, ADR-0026).
struct CityPickerView: View {
    let model: WeatherModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var picker = model.picker
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search for a city", text: $picker.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($fieldFocused)
                        .onSubmit { Task { await picker.search() } }
                        .onExitCommand { model.closePicker() }
                    if picker.isSearching {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, 5)
                .background(.white.opacity(0.1), in: Capsule())

                Button("Cancel") { model.closePicker() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let message = picker.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(picker.results.prefix(4)) { result in
                Button {
                    model.choose(result)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle").foregroundStyle(.secondary)
                        Text(result.label).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(result.label)")
            }
        }
        .task(id: picker.query) { await picker.searchAfterPause() }
        .onAppear { fieldFocused = true }
    }
}
