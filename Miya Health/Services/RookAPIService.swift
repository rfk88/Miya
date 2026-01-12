//
//  RookAPIService.swift
//  Miya Health
//
//  REST API client for Rook Connect API-based data sources (Oura, Whoop, Fitbit, etc.)
//  This handles OAuth authorization flows for API-based sources, separate from the SDK.
//

import Foundation

/// REST API client for Rook Connect authorization endpoints
/// Handles API-based sources (Oura, Whoop, Fitbit, Garmin, etc.)
final class RookAPIService {
    static let shared = RookAPIService()
    
    // Reuse credentials from RookService
    private let clientUUID = "f60e5d66-1d2f-4e71-ba6c-f90c6c8ac2dc"
    private let secretKey = "kO6KBCELDtz4jBMWLrw63WFG8ppzSkQIND4E"
    
    // Sandbox base URL (update to production URL when transitioning)
    private let baseURL = "https://api.rook-connect.review"
    
    private init() {}
    
    /// Errors that can occur when calling Rook API
    enum RookAPIError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case unauthorized
        case notFound
        case rateLimited
        case serverError(Int)
        case invalidData
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server"
            case .unauthorized:
                return "Unauthorized - check your credentials"
            case .notFound:
                return "Resource not found"
            case .rateLimited:
                return "Rate limit exceeded - please try again later"
            case .serverError(let code):
                return "Server error: \(code)"
            case .invalidData:
                return "Invalid data received"
            }
        }
    }
    
    /// Response structure for authorizer endpoint (matches Rook API v1)
    struct RookAuthorizerResponse: Decodable {
        let dataSource: String
        let authorized: Bool
        let authorizationUrl: String?
    }
    
    /// Helper to create HTTP Basic Auth header
    private func createBasicAuthHeader() -> String {
        let credentials = "\(clientUUID):\(secretKey)"
        guard let data = credentials.data(using: .utf8) else {
            return ""
        }
        let base64 = data.base64EncodedString()
        return "Basic \(base64)"
    }
    
    /// Helper to create a properly configured URLRequest for authorizer endpoint
    private func createAuthorizerRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(createBasicAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("MiyaHealth/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    
    /// Helper to create a properly configured URLRequest for other endpoints
    private func createRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(createBasicAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("MiyaHealth/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }
    
    /// Convert lowercase data source ID to capitalized format for Rook API
    private func capitalizeDataSource(_ dataSource: String) -> String {
        switch dataSource.lowercased() {
        case "oura": return "Oura"
        case "whoop": return "Whoop"
        case "fitbit": return "Fitbit"
        case "garmin": return "Garmin"
        default:
            // Capitalize first letter as fallback
            return dataSource.prefix(1).uppercased() + dataSource.dropFirst().lowercased()
        }
    }
    
    /// Get the OAuth authorization info for a specific data source
    /// Uses official Rook API v1 endpoint: /api/v1/user_id/{userId}/data_source/{DataSource}/authorizer
    /// - Parameters:
    ///   - dataSource: Rook data source identifier (e.g., "whoop", "oura", "fitbit") - will be capitalized
    ///   - userId: Authenticated user's ID (MUST be Miya auth UUID)
    /// - Returns: RookAuthorizerResponse with authorized status and authorization_url
    func getAuthorizerInfo(dataSource: String, userId: String) async throws -> RookAuthorizerResponse {
        // Validate UUID format
        print("🔍 RookAPIService: Validating user ID format...")
        let uuidRegex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        let range = NSRange(location: 0, length: userId.utf16.count)
        if let regex = uuidRegex, regex.firstMatch(in: userId, range: range) != nil {
            print("✅ RookAPIService: User ID is valid UUID format")
        } else {
            print("⚠️ RookAPIService: User ID does NOT match UUID format - API calls may fail!")
            print("   Expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
            print("   Received: \(userId)")
        }
        
        // Capitalize data source name (Oura, Whoop, Fitbit, Garmin)
        let capitalizedDataSource = capitalizeDataSource(dataSource)
        
        // Official Rook API v1 endpoint format
        let endpoint = "/api/v1/user_id/\(userId)/data_source/\(capitalizedDataSource)/authorizer"
        let urlString = baseURL + endpoint
        
        guard let url = URL(string: urlString) else {
            throw RookAPIError.invalidURL
        }
        
        let request = createAuthorizerRequest(url: url)
        
        // Log request URL (without credentials)
        print("🟢 RookAPIService: Requesting authorizer for \(dataSource) (capitalized: \(capitalizedDataSource))")
        print("   User ID in API call: \(userId)")
        print("   Final authorizer URL: \(urlString)")
        print("   Method: GET")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RookAPIError.invalidResponse
            }
            
            print("📡 RookAPIService: HTTP status: \(httpResponse.statusCode)")
            
            // Log raw JSON body for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 RookAPIService: Raw JSON body: \(jsonString)")
            }
            
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                do {
                    let authorizerResponse = try decoder.decode(RookAuthorizerResponse.self, from: data)
                    
                    print("✅ RookAPIService: Decode success")
                    print("   data_source: \(authorizerResponse.dataSource)")
                    print("   authorized: \(authorizerResponse.authorized)")
                    if let authURL = authorizerResponse.authorizationUrl {
                        let preview = String(authURL.prefix(60))
                        print("   authorization_url: \(preview)...")
                        print("   ✅ authorization_url will be opened")
                    } else {
                        print("   authorization_url: nil")
                    }
                    
                    return authorizerResponse
                } catch {
                    print("❌ RookAPIService: Decode failure: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("   Response body: \(jsonString)")
                    }
                    throw RookAPIError.invalidData
                }
                
            case 401:
                print("❌ RookAPIService: Unauthorized (401)")
                throw RookAPIError.unauthorized
            case 403:
                print("❌ RookAPIService: Forbidden (403) - check headers and endpoint format")
                throw RookAPIError.unauthorized
            case 404:
                print("❌ RookAPIService: Not found (404)")
                throw RookAPIError.notFound
            case 429:
                print("❌ RookAPIService: Rate limited (429)")
                throw RookAPIError.rateLimited
            case 500...599:
                print("❌ RookAPIService: Server error (\(httpResponse.statusCode))")
                throw RookAPIError.serverError(httpResponse.statusCode)
            default:
                print("❌ RookAPIService: Unexpected status code: \(httpResponse.statusCode)")
                throw RookAPIError.invalidResponse
            }
        } catch let error as RookAPIError {
            throw error
        } catch {
            print("❌ RookAPIService: Network error: \(error.localizedDescription)")
            throw RookAPIError.networkError(error)
        }
    }
    
    /// Check if a data source is currently connected for a user
    /// Uses the authorizer endpoint as the single source of truth (authorized: true/false)
    /// - Parameters:
    ///   - dataSource: Rook data source identifier
    ///   - userId: Authenticated user's ID
    /// - Returns: true if authorized (connected), false otherwise
    func checkConnectionStatus(dataSource: String, userId: String) async throws -> Bool {
        // Use authorizer endpoint as single source of truth (no /status endpoint)
        let capitalizedDataSource = capitalizeDataSource(dataSource)
        let endpoint = "/api/v1/user_id/\(userId)/data_source/\(capitalizedDataSource)/authorizer"
        let urlString = baseURL + endpoint
        
        guard let url = URL(string: urlString) else {
            throw RookAPIError.invalidURL
        }
        
        let request = createAuthorizerRequest(url: url)
        
        print("🟢 RookAPIService: Authorizer state for \(dataSource) (endpoint: \(endpoint))")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RookAPIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                do {
                    let authorizerResponse = try decoder.decode(RookAuthorizerResponse.self, from: data)
                    
                    // Log the result as requested
                    if authorizerResponse.authorized {
                        print("🟢 RookAPIService: Authorizer state for \(dataSource) (authorized=true)")
                    } else {
                        let authUrlStatus = authorizerResponse.authorizationUrl != nil ? "present" : "nil"
                        print("🟢 RookAPIService: Authorizer state for \(dataSource) (authorized=false, authorization_url=\(authUrlStatus))")
                    }
                    
                    return authorizerResponse.authorized
                } catch {
                    print("❌ RookAPIService: Decode failure: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("   Response body: \(jsonString)")
                    }
                    throw RookAPIError.invalidData
                }
                
            case 401:
                print("❌ RookAPIService: Unauthorized (401)")
                throw RookAPIError.unauthorized
            case 403:
                print("❌ RookAPIService: Forbidden (403)")
                throw RookAPIError.unauthorized
            case 404:
                print("❌ RookAPIService: Not found (404)")
                throw RookAPIError.notFound
            case 429:
                print("❌ RookAPIService: Rate limited (429)")
                throw RookAPIError.rateLimited
            case 500...599:
                print("❌ RookAPIService: Server error (\(httpResponse.statusCode))")
                throw RookAPIError.serverError(httpResponse.statusCode)
            default:
                print("❌ RookAPIService: Unexpected status code: \(httpResponse.statusCode)")
                throw RookAPIError.invalidResponse
            }
        } catch let error as RookAPIError {
            throw error
        } catch {
            print("❌ RookAPIService: Network error: \(error.localizedDescription)")
            throw RookAPIError.networkError(error)
        }
    }
    
    /// Disconnect a data source for a user
    /// NOTE: This endpoint format may need to be updated to match Rook API v1 format
    /// - Parameters:
    ///   - dataSource: Rook data source identifier
    ///   - userId: Authenticated user's ID
    func disconnectDataSource(dataSource: String, userId: String) async throws {
        // TODO: Verify correct endpoint format for disconnect in Rook API v1
        // Currently using old format - may need update similar to authorizer endpoint
        let capitalizedDataSource = capitalizeDataSource(dataSource)
        let endpoint = "/api/v1/user_id/\(userId)/data_source/\(capitalizedDataSource)"
        let urlString = baseURL + endpoint
        
        guard let url = URL(string: urlString) else {
            throw RookAPIError.invalidURL
        }
        
        let request = createRequest(url: url, method: "DELETE")
        
        print("🟢 RookAPIService: Disconnecting \(dataSource)")
        print("   URL: \(baseURL)\(endpoint)")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RookAPIError.invalidResponse
            }
            
            print("📡 RookAPIService: Disconnect response: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200, 204:
                print("✅ RookAPIService: Successfully disconnected \(dataSource)")
                return
                
            case 401:
                throw RookAPIError.unauthorized
            case 404:
                // Already disconnected, treat as success
                print("⚠️ RookAPIService: \(dataSource) not found (already disconnected?)")
                return
            case 429:
                throw RookAPIError.rateLimited
            case 500...599:
                throw RookAPIError.serverError(httpResponse.statusCode)
            default:
                throw RookAPIError.invalidResponse
            }
        } catch let error as RookAPIError {
            throw error
        } catch {
            throw RookAPIError.networkError(error)
        }
    }
}

// Make AuthorizerResponse accessible outside the class
extension RookAPIService {
    struct AuthorizerInfo {
        let authorized: Bool
        let authorizationURL: URL?
    }
}

