//
//  PrintablesService.swift
//  Printer
//
//  Created by Matt on 2/11/26.
//

import Foundation

/// Service for interacting with the Printables.com GraphQL API.
///
/// No authentication is required for read-only queries. The API is
/// unofficial/reverse-engineered and may change without notice.
actor PrintablesService {

    // MARK: - Types

    /// Errors specific to Printables API operations
    enum PrintablesError: LocalizedError {
        case invalidURL
        case networkError(String)
        case graphQLError(String)
        case decodingError(String)
        case noData
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Printables API URL"
            case .networkError(let detail):
                return "Network error: \(detail)"
            case .graphQLError(let detail):
                return "Printables API error: \(detail)"
            case .decodingError(let detail):
                return "Failed to decode response: \(detail)"
            case .noData:
                return "No data returned from Printables"
            case .downloadFailed(let detail):
                return "File download failed: \(detail)"
            }
        }
    }

    // MARK: - Constants

    private let endpoint = URL(string: "https://api.printables.com/graphql/")!
    private let session: URLSession

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Search Printables models by query string.
    ///
    /// - Parameters:
    ///   - query: Search text (e.g. "benchy", "vase", "raspberry pi case")
    ///   - limit: Maximum number of results per page (default 20)
    ///   - offset: Pagination offset (default 0)
    ///   - ordering: Sort order (default `.bestMatch`)
    /// - Returns: Array of search results
    func search(
        query: String,
        limit: Int = 20,
        offset: Int = 0,
        ordering: PrintablesOrdering = .bestMatch
    ) async throws -> [PrintablesSearchResult] {
        let graphQL = """
        query SearchPrints($query: String!, $limit: Int, $offset: Int, $ordering: SearchChoicesEnum) {
          searchPrints2(query: $query, limit: $limit, offset: $offset, ordering: $ordering) {
            items {
              id
              name
              image {
                filePath
                rotation
              }
              nsfw
              hasModel
              liked
              likesCount
              downloadCount
              datePublished
            }
          }
        }
        """

        let variables: [String: GraphQLValue] = [
            "query": .string(query),
            "limit": .int(limit),
            "offset": .int(offset),
            "ordering": ordering.graphQLValue
        ]

        let request = GraphQLRequest(
            operationName: "SearchPrints",
            query: graphQL,
            variables: variables
        )

        let response: GraphQLResponse<SearchPrintsData> = try await execute(request)

        guard let data = response.data else {
            if let errors = response.errors, let first = errors.first {
                throw PrintablesError.graphQLError(first.message)
            }
            throw PrintablesError.noData
        }

        return data.searchPrints2.items
    }

    /// Fetch full details for a single Printables model.
    ///
    /// Includes images, files (STL/GCode/SLA), author info, description, tags, etc.
    ///
    /// - Parameter id: The Printables model ID (numeric string)
    /// - Returns: Full model detail
    func modelDetail(id: String) async throws -> PrintablesModelDetail {
        let graphQL = """
        query PrintProfile($id: ID!) {
          print(id: $id) {
            id
            name
            images {
              id
              filePath
              rotation
            }
            nsfw
            hasModel
            liked
            likesCount
            downloadCount
            makesCount
            datePublished
            summary
            description
            user {
              id
              publicUsername
              avatarFilePath
              handle
            }
            tags {
              id
              name
            }
            stls {
              id
              name
              fileSize
              filePreviewPath
            }
            gcodes {
              id
              name
              fileSize
              filePreviewPath
            }
            slas {
              id
              name
              fileSize
              filePreviewPath
            }
            category {
              id
              path {
                id
                name
              }
            }
            license {
              id
              name
              disallowRemixing
            }
          }
        }
        """

        let variables: [String: GraphQLValue] = [
            "id": .string(id)
        ]

        let request = GraphQLRequest(
            operationName: "PrintProfile",
            query: graphQL,
            variables: variables
        )

        let response: GraphQLResponse<PrintDetailData> = try await execute(request)

        guard let data = response.data else {
            if let errors = response.errors, let first = errors.first {
                throw PrintablesError.graphQLError(first.message)
            }
            throw PrintablesError.noData
        }

        return data.print
    }

    /// Download a file from Printables to a local temporary directory.
    ///
    /// Uses the `getDownloadLink` mutation to obtain a signed URL, then downloads the file.
    ///
    /// - Parameters:
    ///   - file: The `PrintablesFile` (STL, GCode, or SLA) to download
    ///   - printId: The Printables model ID that owns this file
    ///   - fileType: The type of file ("stl", "gcode", or "sla")
    /// - Returns: Local URL of the downloaded file
    func downloadFile(_ file: PrintablesFile, printId: String, fileType: String) async throws -> URL {
        // Step 1: Get signed download URL via mutation
        let mutation = """
        mutation GetDownloadLink($printId: ID!, $fileType: DownloadFileTypeEnum, $source: DownloadSourceEnum!, $id: ID) {
          getDownloadLink(printId: $printId, fileType: $fileType, source: $source, id: $id) {
            ok
            output {
              link
            }
          }
        }
        """

        let variables: [String: GraphQLValue] = [
            "printId": .string(printId),
            "fileType": .string(fileType),
            "source": .string("model_detail"),
            "id": .string(file.id)
        ]

        let gqlRequest = GraphQLRequest(
            operationName: "GetDownloadLink",
            query: mutation,
            variables: variables
        )

        let response: GraphQLResponse<GetDownloadLinkData> = try await execute(gqlRequest)

        guard let link = response.data?.getDownloadLink.output?.link,
              let downloadURL = URL(string: link) else {
            throw PrintablesError.downloadFailed("Could not obtain download link")
        }

        // Step 2: Download file from the signed URL
        var request = URLRequest(url: downloadURL)
        request.httpMethod = "GET"

        let (data, httpResponse) = try await session.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw PrintablesError.downloadFailed(
                "HTTP \((httpResponse as? HTTPURLResponse)?.statusCode ?? 0)"
            )
        }

        // Save to temp directory with original filename
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrintablesDownloads", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let localURL = tempDir.appendingPathComponent(file.name)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: localURL)
        try data.write(to: localURL)

        return localURL
    }

    // MARK: - Private

    /// Execute a GraphQL request and decode the response.
    private func execute<T: Decodable>(_ graphQLRequest: GraphQLRequest) async throws -> GraphQLResponse<T> {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(graphQLRequest)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PrintablesError.networkError("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PrintablesError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            throw PrintablesError.decodingError(error.localizedDescription)
        }
    }
}
