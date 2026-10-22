import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LibrarySyncClient: Sendable {
    private let endpoint: URL
    private let key: String
    private let session: URLSession

    public init(server: URL, key: String, session: URLSession? = nil) {
        endpoint = server.appendingPathComponent("v1/library/sync")
        self.key = key
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration, delegate: SyncRedirectPolicy(), delegateQueue: nil)
        }
    }

    public static func serverURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    public func synchronize(_ document: LibrarySyncDocument) async throws -> LibrarySyncDocument {
        let body = try document.encoded()
        guard body.count <= 8 * 1_024 * 1_024 else { throw LibrarySyncError.tooLarge }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SyncServiceError.invalidResponse }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw SyncServiceError.unauthorized
        case 404: throw SyncServiceError.notDeployed
        case 413: throw LibrarySyncError.tooLarge
        case 429: throw SyncServiceError.rateLimited
        default: throw SyncServiceError.unavailable
        }
        let received: LibrarySyncDocument
        do { received = try LibrarySyncDocument.decode(data) }
        catch { throw SyncServiceError.invalidResponse }
        var merged = Library()
        merged.merge(document)
        merged.merge(received)
        guard merged.syncState == received.state else { throw SyncServiceError.incompleteMerge }
        return received
    }
}

public enum SyncServiceError: LocalizedError {
    case unauthorized, notDeployed, rateLimited, unavailable, invalidResponse, incompleteMerge
    case invalidServer, invalidKey, localStorageUnavailable

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "密钥无效或已失效，请重新设置。"
        case .notDeployed: return "同步接口尚未部署，本机数据已保留。"
        case .rateLimited: return "同步请求过于频繁，请稍后重试。"
        case .unavailable: return "暂时无法连接同步服务，本机数据已保留，稍后会重试。"
        case .invalidResponse: return "同步服务返回的数据格式不正确，本机数据未被替换。"
        case .incompleteMerge: return "同步服务未完整合并数据，请检查服务接口。"
        case .invalidServer: return "请输入有效的 HTTPS 服务地址，不包含账号、密码、查询参数或片段。"
        case .invalidKey: return "请输入同步密钥；更换服务地址时需要重新输入密钥。"
        case .localStorageUnavailable: return "本机数据暂时无法安全保存，已暂停同步，请先处理存储错误。"
        }
    }
}

private final class SyncRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
