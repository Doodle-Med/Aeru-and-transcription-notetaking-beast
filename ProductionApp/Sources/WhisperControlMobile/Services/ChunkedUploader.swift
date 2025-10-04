import Foundation

final class ChunkedUploader {
    private let threshold: Int64 = 50 * 1024 * 1024 // 50 MB

    func shouldStream(fileSize: Int64) -> Bool {
        fileSize >= threshold
    }

    func uploadFile(_ request: URLRequest, fileURL: URL, progressHandler: ((Double) -> Void)? = nil) async throws -> (Data, URLResponse) {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard shouldStream(fileSize: fileSize) else {
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
            return (data, response)
        }

        let delegate = StreamingDelegate(fileURL: fileURL, expectedBytes: fileSize, progressHandler: progressHandler)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 10 * 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return try await delegate.upload(using: session, request: request)
    }

    private final class StreamingDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
        private let fileURL: URL
        private let expectedBytes: Int64
        private let progressHandler: ((Double) -> Void)?
        private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        private var responseData = Data()
        private var response: URLResponse?
        private var totalBytesSent: Int64 = 0
        private var session: URLSession?

        init(fileURL: URL, expectedBytes: Int64, progressHandler: ((Double) -> Void)?) {
            self.fileURL = fileURL
            self.expectedBytes = expectedBytes
            self.progressHandler = progressHandler
        }

        func upload(using session: URLSession, request: URLRequest) async throws -> (Data, URLResponse) {
            self.session = session
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                var streamingRequest = request
                streamingRequest.httpBodyStream = InputStream(url: fileURL)
                let task = session.uploadTask(withStreamedRequest: streamingRequest)
                task.resume()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            self.totalBytesSent = totalBytesSent
            guard expectedBytes > 0 else { return }
            progressHandler?(min(Double(totalBytesSent) / Double(expectedBytes), 1.0))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
            completionHandler(InputStream(url: fileURL))
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            responseData.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            defer {
                session.finishTasksAndInvalidate()
                self.session = nil
            }
            guard let continuation else { return }
            if let error {
                continuation.resume(throwing: error)
                self.continuation = nil
                return
            }

            let finalResponse = task.response ?? response
            guard let finalResponse else {
                continuation.resume(throwing: URLError(.badServerResponse))
                self.continuation = nil
                return
            }

            continuation.resume(returning: (responseData, finalResponse))
            self.continuation = nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response
            completionHandler(.allow)
        }
    }
}
