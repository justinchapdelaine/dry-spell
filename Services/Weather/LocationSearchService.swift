import CoreLocation
import Combine
import Foundation
import MapKit

struct LocationSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

struct ResolvedGardenLocation: Equatable, Sendable {
    let displayName: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
}

enum LocationSearchError: LocalizedError {
    case missingCompletion
    case noMapItemFound
    case noCoordinateFound
    case noTimeZoneFound

    var errorDescription: String? {
        switch self {
        case .missingCompletion:
            return "That result is no longer available. Please try again."
        case .noMapItemFound:
            return "Couldn't turn that place into a saved location."
        case .noCoordinateFound:
            return "Couldn't find coordinates for that place."
        case .noTimeZoneFound:
            return "Couldn't determine the time zone for that place."
        }
    }
}

@MainActor
final class LocationSearchService: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            updateSearchQuery()
        }
    }

    @Published private(set) var suggestions: [LocationSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let completer: MKLocalSearchCompleter
    private var completionBySuggestionID: [String: MKLocalSearchCompletion] = [:]

    init(completer: MKLocalSearchCompleter = MKLocalSearchCompleter()) {
        self.completer = completer
        super.init()

        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func resolveSuggestion(_ suggestion: LocationSuggestion) async throws -> ResolvedGardenLocation {
        guard let completion = completionBySuggestionID[suggestion.id] else {
            throw LocationSearchError.missingCompletion
        }

        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let mapItem = response.mapItems.first else {
            throw LocationSearchError.noMapItemFound
        }

        let location = mapItem.location

        let timeZone = try resolvedTimeZone(for: mapItem)
        let displayName = displayName(for: mapItem, fallback: suggestion)

        return ResolvedGardenLocation(
            displayName: displayName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private func updateSearchQuery() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.count < 2 {
            completer.cancel()
            isSearching = false
            errorMessage = nil
            completionBySuggestionID = [:]
            suggestions = []
            return
        }

        errorMessage = nil
        isSearching = true
        completer.queryFragment = trimmedQuery
    }

    private func resolvedTimeZone(for mapItem: MKMapItem) throws -> TimeZone {
        if let timeZone = mapItem.timeZone {
            return timeZone
        }

        throw LocationSearchError.noTimeZoneFound
    }

    private func displayName(for mapItem: MKMapItem, fallback suggestion: LocationSuggestion) -> String {
        if let name = mapItem.name, !name.isEmpty {
            if suggestion.subtitle.isEmpty {
                return name
            }

            return "\(name), \(suggestion.subtitle)"
        }

        if suggestion.subtitle.isEmpty {
            return suggestion.title
        }

        return "\(suggestion.title), \(suggestion.subtitle)"
    }
}

extension LocationSearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isSearching = false
        errorMessage = nil

        var completionBySuggestionID: [String: MKLocalSearchCompletion] = [:]
        suggestions = completer.results.map { completion in
            let suggestion = LocationSuggestion(
                title: completion.title,
                subtitle: completion.subtitle
            )
            completionBySuggestionID[suggestion.id] = completion
            return suggestion
        }
        self.completionBySuggestionID = completionBySuggestionID
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        isSearching = false
        completionBySuggestionID = [:]
        suggestions = []
        errorMessage = error.localizedDescription
    }
}
