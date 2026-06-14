//
//  GitOriginApp.swift
//  GitOrigin
//

import SwiftUI

@main
struct GitOriginApp: App {
    @State private var store = RepositoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
