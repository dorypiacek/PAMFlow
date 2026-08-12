//
//  UserProfileStore.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation

/// Persistence boundary for the lightweight local user profile.
protocol UserProfileStoring {
    func load() -> UserProfile?
    func save(_ profile: UserProfile)
    func delete()
}

/// UserDefaults-backed profile store for MVP local identity.
final class UserProfileStore: UserProfileStoring {
    private let key = "user_profile"

    func load() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func delete() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
