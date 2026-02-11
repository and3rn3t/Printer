//
//  PrintablesModels.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation

// MARK: - GraphQL Request/Response Wrappers

/// Wrapper for GraphQL POST requests to the Printables API
struct GraphQLRequest: Encodable {
    let operationName: String
    let query: String
    let variables: [String: GraphQLValue]
}

/// Type-erased wrapper for GraphQL variables (String, Int, Bool, nil, etc.)
enum GraphQLValue: Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

/// Top-level GraphQL response envelope
struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

/// GraphQL error returned by the server
struct GraphQLError: Decodable, Sendable {
    let message: String
}

// MARK: - Search Response

/// Response type for the `searchPrints2` query
struct SearchPrintsData: Decodable {
    let searchPrints2: SearchPrintsList
}

struct SearchPrintsList: Decodable {
    let items: [PrintablesSearchResult]
}

// MARK: - Model Detail Response

/// Response type for the `print(id:)` query
struct PrintDetailData: Decodable {
    let print: PrintablesModelDetail
}

/// Response type for the `getDownloadLink` mutation
struct GetDownloadLinkData: Decodable {
    let getDownloadLink: GetDownloadLinkResult
}

struct GetDownloadLinkResult: Decodable {
    let ok: Bool
    let output: GetDownloadLinkOutput?
}

struct GetDownloadLinkOutput: Decodable {
    let link: String
}

// MARK: - Printables Data Types

/// A search result from `searchPrints2` — lightweight summary
struct PrintablesSearchResult: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let image: PrintablesImage
    let nsfw: Bool
    let hasModel: Bool
    let liked: Bool?
    let likesCount: Int
    let downloadCount: Int
    let datePublished: String
    let gcodes: [PrintablesFileRef]?
    let slas: [PrintablesFileRef]?

    /// Whether this model includes pre-sliced files (GCode or SLA/resin)
    var hasSlicedFiles: Bool {
        !(gcodes ?? []).isEmpty || !(slas ?? []).isEmpty
    }

    /// Human-readable date (e.g. "Feb 14, 2025")
    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: datePublished) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: datePublished) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return datePublished
    }
}

/// Full model detail from `print(id:)` — includes files, description, author
struct PrintablesModelDetail: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let images: [PrintablesImage]?
    let nsfw: Bool
    let hasModel: Bool
    let liked: Bool?
    let likesCount: Int
    let downloadCount: Int
    let makesCount: Int
    let datePublished: String
    let summary: String?
    let description: String?
    let user: PrintablesUser?
    let tags: [PrintablesTag]?
    let stls: [PrintablesFile]?
    let gcodes: [PrintablesFile]?
    let slas: [PrintablesFile]?
    let category: PrintablesCategory?
    let license: PrintablesLicense?
}

/// Image associated with a Printables model
struct PrintablesImage: Decodable, Identifiable, Sendable {
    let id: String?
    let filePath: String
    let rotation: Int

    /// Full URL for loading the media asset
    var imageURL: URL? {
        let path = filePath.hasPrefix("/") ? filePath : "/\(filePath)"
        return URL(string: "https://media.printables.com\(path)")
    }
}

/// Author of a Printables model
struct PrintablesUser: Decodable, Sendable {
    let id: String
    let publicUsername: String
    let avatarFilePath: String
    let handle: String

    /// Full URL for the user's avatar
    var avatarURL: URL? {
        let path = avatarFilePath.hasPrefix("/") ? avatarFilePath : "/\(avatarFilePath)"
        return URL(string: "https://media.printables.com\(path)")
    }
}

/// Tag / keyword on a Printables model
struct PrintablesTag: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// A downloadable file (STL, GCODE, or SLA) from Printables
struct PrintablesFile: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let fileSize: Int
    let filePreviewPath: String

    /// Human-readable file size
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    /// File extension inferred from the file name
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}

/// Category of a Printables model
struct PrintablesCategory: Decodable, Sendable {
    let id: String
    let path: [PrintablesCategoryPath]?
}

struct PrintablesCategoryPath: Decodable, Identifiable, Sendable {
    let id: String
    let name: String?
}

/// License info for a Printables model
struct PrintablesLicense: Decodable, Sendable {
    let id: String
    let name: String?
    let disallowRemixing: Bool?
}

/// Lightweight file reference used in search results (ID only)
struct PrintablesFileRef: Decodable, Identifiable, Sendable {
    let id: String
}

// MARK: - Search Ordering

/// Sort order for Printables search results
enum PrintablesOrdering: String, CaseIterable, Identifiable {
    case bestMatch = "Best Match"
    case latest = "Newest"
    case popular = "Popular"
    case makesCount = "Most Makes"
    case rating = "Top Rated"

    var id: String { rawValue }

    /// GraphQL enum value (null = best match)
    var graphQLValue: GraphQLValue {
        switch self {
        case .bestMatch: return .null
        case .latest: return .string("latest")
        case .popular: return .string("popular")
        case .makesCount: return .string("makes_count")
        case .rating: return .string("rating")
        }
    }
}
