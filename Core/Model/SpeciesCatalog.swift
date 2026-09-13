//
//  SpeciesCatalog.swift
//  PAMFlow
//
//  Created by Dory on 18/06/2026.
//

import Foundation

/// Taxonomic choice shown in the optional species selector.
struct SpeciesTaxon: Identifiable, Hashable {
    var id: String { "\(family)::\(genus)::\(species)" }

    let family: String
    let genus: String
    let species: String
    let commonName: String?

    init(family: String, genus: String, species: String, commonName: String? = nil) {
        self.family = family
        self.genus = genus
        self.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        self.commonName = commonName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var fullName: String {
        "\(genus) \(species)"
    }

    /// Searchable, user-facing label containing scientific and common names.
    var displayName: String {
        guard let commonName, !commonName.isEmpty else { return fullName }
        return "\(fullName) (\(commonName))"
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || displayName.localizedCaseInsensitiveContains(query)
    }
}

/// Hardcoded MVP species lists available for modules that need species assignment.
enum SpeciesCatalog {
    static let cetaceans: [SpeciesTaxon] = [
        SpeciesTaxon(family: "Delphinidae", genus: "Tursiops", species: "truncatus"),
        SpeciesTaxon(family: "Delphinidae", genus: "Delphinus", species: "delphis"),
        SpeciesTaxon(family: "Delphinidae", genus: "Lagenorhynchus", species: "albirostris"),
        SpeciesTaxon(family: "Phocoenidae", genus: "Phocoena", species: "phocoena"),
        SpeciesTaxon(family: "Physeteridae", genus: "Physeter", species: "macrocephalus")
    ]

    static let elasmobranchs: [SpeciesTaxon] = [
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "amblyrhynchos", commonName: "Grey Reef Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "brachyurus", commonName: "Copper Shark (Bronze Whaler)"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "falciformis", commonName: "Silky Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "leucas", commonName: "Bull Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "limbatus", commonName: "Blacktip Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "obscurus", commonName: "Dusky Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "plumbeus", commonName: "Sandbar Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "humani", commonName: "Humans Whaler Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Carcharhinus", species: "sp", commonName: "Unidentified Requiem Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Galeocerdo", species: "cuvier", commonName: "Tiger Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Loxodon", species: "maculatus", commonName: "Sliteye Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Negaprion", species: "acutidens", commonName: "Sicklefin Lemon Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Prionace", species: "glauca", commonName: "Blue Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Rhizoprionodon", species: "acutus", commonName: "Milk Shark"),
        SpeciesTaxon(family: "Carcharhinidae", genus: "Triaenodon", species: "obesus", commonName: "Whitetip Reef Shark"),
        SpeciesTaxon(family: "Sphyrnidae", genus: "Sphyrna", species: "lewini", commonName: "Scalloped Hammerhead"),
        SpeciesTaxon(family: "Sphyrnidae", genus: "Sphyrna", species: "mokarran", commonName: "Great Hammerhead"),
        SpeciesTaxon(family: "Sphyrnidae", genus: "Sphyrna", species: "zygaena", commonName: "Smooth Hammerhead"),
        SpeciesTaxon(family: "Sphyrnidae", genus: "Sphyrna", species: "tudes", commonName: "Smalleye Hammerhead"),
        SpeciesTaxon(family: "Lamnidae", genus: "Carcharodon", species: "carcharias", commonName: "White Shark"),
        SpeciesTaxon(family: "Lamnidae", genus: "Isurus", species: "oxyrinchus", commonName: "Shortfin Mako"),
        SpeciesTaxon(family: "Lamnidae", genus: "Isurus", species: "paucus", commonName: "Longfin Mako"),
        SpeciesTaxon(family: "Lamnidae", genus: "Lamna", species: "nasus", commonName: "Porbeagle"),
        SpeciesTaxon(family: "Odontaspididae", genus: "Carcharias", species: "taurus", commonName: "Ragged-Tooth Shark"),
        SpeciesTaxon(family: "Odontaspididae", genus: "Odontaspis", species: "ferox", commonName: "Smalltooth Sand Tiger"),
        SpeciesTaxon(family: "Rhinobatidae", genus: "Acroteriobatus", species: "annulatus", commonName: "Lesser Guitarfish"),
        SpeciesTaxon(family: "Rhinobatidae", genus: "Rhinobatos", species: "schlegelii", commonName: "Brown Guitarfish"),
        SpeciesTaxon(family: "Rhinobatidae", genus: "Rhinobatos", species: "leucospilus", commonName: "Greyspot Guitarfish"),
        SpeciesTaxon(family: "Rhinidae", genus: "Rhina", species: "ancylostoma", commonName: "Bowmouth Guitarfish"),
        SpeciesTaxon(family: "Rhinidae", genus: "Rhynchobatus", species: "djiddensis", commonName: "Whitespotted Wedgefish"),
        SpeciesTaxon(family: "Dasyatidae", genus: "Himantura", species: "sp"),
        SpeciesTaxon(family: "Dasyatidae", genus: "Pateobatis", species: "jenkinsii", commonName: "Jenkins' Whipray"),
        SpeciesTaxon(family: "Dasyatidae", genus: "Taeniura", species: "meyeni", commonName: "Round Ribbontail Ray"),
        SpeciesTaxon(family: "Myliobatidae", genus: "Aetobatus", species: "oscellatus", commonName: "Ocellated Eagle Ray"),
        SpeciesTaxon(family: "Myliobatidae", genus: "Rhinoptera", species: "javanica", commonName: "Flapnose Cownose Ray"),
        SpeciesTaxon(family: "Myliobatidae", genus: "Rhinoptera", species: "marginata", commonName: "Lusitanian Cownose Ray"),
        SpeciesTaxon(family: "Mobulidae", genus: "Mobula", species: "alfredi", commonName: "Reef Manta Ray"),
        SpeciesTaxon(family: "Mobulidae", genus: "Mobula", species: "birostris", commonName: "Oceanic Manta Ray"),
        SpeciesTaxon(family: "Mobulidae", genus: "Mobula", species: "kuhlii", commonName: "Shortfin Devil Ray"),
        SpeciesTaxon(family: "Torpedinidae", genus: "Torpedo", species: "sinuspersici", commonName: "Marbled Electric Ray / Gulf Torpedo Ray")
    ]

}
