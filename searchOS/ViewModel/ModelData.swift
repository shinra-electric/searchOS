//
//  ModelData.swift
//  searchOS
//
//  Created by シェイミ on 23/06/2021.
//

import Foundation
import SwiftUI

@MainActor
final class ModelData: ObservableObject {
    @Published var oses: [MacOSModel] = []
    @Published var favorites = Set<MacOSModel>()
    
    private var loadTask: Task<Void, Never>?
    private let dataSource: OSDataSource
    
    init(dataSource: OSDataSource = BundleOSDataSource()) {
        self.dataSource = dataSource
        loadTask = Task(priority: .userInitiated) { await load() }
    }
    
    deinit {
        loadTask?.cancel()
    }
    
    // MARK: Search
    @AppStorage("searchText") private var storedSearchText: String = ""
    var searchText: String {
        get { storedSearchText }
        set { storedSearchText = newValue }
    }
    
    var searchResults: [MacOSModel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filteredOS }
        return filteredOS.filter { os in
            os.codename.localizedCaseInsensitiveContains(trimmed)
        }
    }
    
    @AppStorage("favoriteIDsData") private var favoriteIDsData: Data = Data()
    private var favoriteIDs: Set<MacOSModel.ID> {
        get {
            (try? JSONDecoder().decode(Set<MacOSModel.ID>.self, from: favoriteIDsData)) ?? []
        }
        set {
            favoriteIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func toggle(favorite os: MacOSModel) {
        if favorites.contains(os) {
            favorites.remove(os)
            var ids = favoriteIDs
            ids.remove(os.id)
            favoriteIDs = ids
        } else {
            favorites.insert(os)
            var ids = favoriteIDs
            ids.insert(os.id)
            favoriteIDs = ids
        }
    }
    
    
    // MARK: Filtering
    @AppStorage("showFavoritesOnly") private var storedShowFavoritesOnly: Bool = false
    var showFavoritesOnly: Bool {
        get { storedShowFavoritesOnly }
        set { storedShowFavoritesOnly = newValue }
    }
    @AppStorage("filterCategory") private var storedFilterRawValue: String = FilterCategory.all.rawValue
    var filter: FilterCategory {
        get { FilterCategory(rawValue: storedFilterRawValue) ?? .all }
        set { storedFilterRawValue = newValue.rawValue }
    }
    
    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case ppc = "PowerPC"
        case intel = "Intel"
        case arm = "ARM"
        
        case thirtyTwoBit = "32-bit"
        case sixtyFourBit = "64-bit"
        
        var id: FilterCategory { self }
    }
    
    var filteredOS: [MacOSModel] {
        oses.filter { os in
            (!showFavoritesOnly
             || favorites.contains(os)) &&
            (filter == .all
             || os.architecture.rawValue.contains(filter.rawValue)
             || os.applications.rawValue.contains(filter.rawValue)
            )
        }
    }
    
    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }
    
    @Published private(set) var loadState: LoadState = .idle
    
    // MARK: - Async Loading
    func load() async {
        loadState = .loading
        do {
            try Task.checkCancellation()
            let decoded = try await dataSource.fetchOSList()
            try Task.checkCancellation()
            oses = decoded
            let ids = favoriteIDs
            favorites = Set(decoded.filter { ids.contains($0.id) })
            loadState = .loaded
        } catch is CancellationError {
            loadState = .idle
        } catch {
            #if DEBUG
            print("Failed to load macos.json: \(error)")
            #endif
            loadState = .failed(error)
        }
    }
}

protocol OSDataSource {
    func fetchOSList() async throws -> [MacOSModel]
}

struct BundleOSDataSource: OSDataSource {
    func fetchOSList() async throws -> [MacOSModel] {
        try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "macos.json", withExtension: nil) else {
                throw URLError(.fileDoesNotExist)
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([MacOSModel].self, from: data)
        }.value
    }
}

