//
//  SpeciesCatalog.swift
//  PAMFlow
//
//  Created by Dory on 18/06/2026.
//

import Foundation

/// High-level taxonomic group supported by the bundled offline taxonomy.
public enum TaxonGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case elasmobranch
    case odontocete
}

/// Immutable species reference decoded from the bundled taxonomy resource.
public struct Species: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let scientificName: String
    public let genus: String
    public let family: String
    public let commonName: String?
    public let group: TaxonGroup

    public init(
        id: Int,
        scientificName: String,
        genus: String,
        family: String,
        commonName: String?,
        group: TaxonGroup
    ) {
        self.id = id
        self.scientificName = scientificName
        self.genus = genus
        self.family = family
        self.commonName = commonName
        self.group = group
    }
}

public extension Species {
    /// Species epithet extracted from the scientific binomial.
    var speciesName: String {
        scientificName
            .split(separator: " ")
            .dropFirst()
            .joined(separator: " ")
    }

    /// Searchable, user-facing label containing scientific and common names.
    var displayName: String {
        guard let commonName, !commonName.isEmpty else { return scientificName }
        return "\(scientificName) (\(commonName))"
    }
}

/// Taxonomic choice shown in the optional species selector.
public struct SpeciesTaxon: Identifiable, Hashable, Sendable {
    public var id: String { "\(speciesID)" }

    public let speciesID: Int
    public let family: String
    public let genus: String
    public let species: String
    public let commonName: String?

    public init(speciesID: Int, family: String, genus: String, species: String, commonName: String? = nil) {
        self.speciesID = speciesID
        self.family = family
        self.genus = genus
        self.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        self.commonName = commonName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(_ species: Species) {
        self.init(
            speciesID: species.id,
            family: species.family,
            genus: species.genus,
            species: species.speciesName,
            commonName: species.commonName
        )
    }

    public var fullName: String {
        "\(genus) \(species)"
    }

    /// Searchable, user-facing label containing scientific and common names.
    public var displayName: String {
        guard let commonName, !commonName.isEmpty else { return fullName }
        return "\(fullName) (\(commonName))"
    }

    public func matches(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }
        return [commonName, fullName, genus, family]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }
}

/// Read-only taxonomy lookup backed by the bundled species JSON resource.
public protocol TaxonomyServiceType: Sendable {
    /// All species decoded from the offline taxonomy resource.
    var allSpecies: [Species] { get }

    /// Returns the species with the matching stable taxonomy identifier.
    func species(id: Int) -> Species?

    /// Searches common name, scientific name, genus, and family for picker suggestion use.
    func search(_ query: String, group: TaxonGroup?) -> [Species]
}

/// Lightweight in-memory taxonomy repository for bundled species reference data.
public final class TaxonomyService: TaxonomyServiceType, @unchecked Sendable {
    public static let shared = TaxonomyService()

    public let allSpecies: [Species]

    private let speciesByID: [Int: Species]

    public init(bundle: Bundle = .main, resourceName: String = "species") {
        let species = Self.loadSpecies(bundle: bundle, resourceName: resourceName)
        self.allSpecies = species
        self.speciesByID = Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0) })
    }

    public func species(id: Int) -> Species? {
        speciesByID[id]
    }

    public func search(_ query: String, group: TaxonGroup? = nil) -> [Species] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allSpecies.filter { species in
            guard group == nil || species.group == group else { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return [
                species.commonName,
                species.scientificName,
                species.genus,
                species.family
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    private static func loadSpecies(bundle: Bundle, resourceName: String) -> [Species] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            AppLog.info("Missing bundled taxonomy resource: \(resourceName).json")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Species].self, from: data)
        } catch {
            AppLog.info("Failed to decode bundled taxonomy resource: \(error.localizedDescription)")
            return []
        }
    }
}

/// Species lists available for modules that need species assignment.
public enum SpeciesCatalog {
    public static var cetaceans: [SpeciesTaxon] {
        TaxonomyService.shared
            .search("", group: .odontocete)
            .map(SpeciesTaxon.init)
    }

    public static var elasmobranchs: [SpeciesTaxon] {
        TaxonomyService.shared
            .search("", group: .elasmobranch)
            .map(SpeciesTaxon.init)
    }
}
