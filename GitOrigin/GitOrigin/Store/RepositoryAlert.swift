//
//  RepositoryAlert.swift
//  GitOrigin
//
//  Payload for modal alerts shown from RepositoryStore (errors and confirmations).
//

import Foundation

struct RepositoryAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
