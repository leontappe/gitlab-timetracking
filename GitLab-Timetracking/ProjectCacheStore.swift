//
//  ProjectCacheStore.swift
//  My GitLab Timetracking
//

import Foundation

struct PersistedProjectCache: Codable {
    let baseURL: String
    let projects: [GitLabProject]
    let updatedAt: Date
}

struct ProjectCacheStore {
    private let defaults: UserDefaults
    private let key = "gitlab.cachedProjects"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for baseURL: String) -> PersistedProjectCache? {
        guard
            let data = defaults.data(forKey: key),
            let cache = try? JSONDecoder().decode(PersistedProjectCache.self, from: data),
            cache.baseURL == baseURL
        else {
            return nil
        }

        return cache
    }

    func save(projects: [GitLabProject], baseURL: String, updatedAt: Date = Date()) {
        let cache = PersistedProjectCache(baseURL: baseURL, projects: projects, updatedAt: updatedAt)
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
