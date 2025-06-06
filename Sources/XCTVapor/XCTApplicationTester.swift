import NIOHTTP1
import XCTest

public protocol XCTApplicationTester: Sendable {
    @available(*, noasync, message: "Use the async method instead.")
    func performTest(request: TestingHTTPRequest) throws -> TestingHTTPResponse
    func performTest(request: TestingHTTPRequest) async throws -> TestingHTTPResponse
}

extension Application.Live: XCTApplicationTester {}
extension Application.InMemory: XCTApplicationTester {}

extension Application: XCTApplicationTester {
    public func testable(method: Method = .inMemory) throws -> XCTApplicationTester {
        try self.boot()
        switch method {
        case .inMemory:
            return try InMemory(app: self)
        case let .running(hostname, port):
            return try Live(app: self, hostname: hostname, port: port)
        }
    }

    @available(*, noasync, message: "Use the async method instead.")
    public func performTest(request: TestingHTTPRequest) throws -> TestingHTTPResponse {
        try self.testable().performTest(request: request)
    }

    public func performTest(request: TestingHTTPRequest) async throws -> TestingHTTPResponse {
        try await self.testable().performTest(request: request)
    }
}

extension XCTApplicationTester {
    @discardableResult
    public func test(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        afterResponse: (XCTHTTPResponse) async throws -> ()
    ) async throws -> XCTApplicationTester {
        try await self.test(
            method,
            path,
            headers: headers,
            body: body,
            file: file,
            line: line,
            beforeRequest: { _ in },
            afterResponse: afterResponse
        )
    }

    @available(*, noasync, message: "Use the async method instead.")
    @discardableResult
    public func test(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        afterResponse: (XCTHTTPResponse) throws -> ()
    ) throws -> XCTApplicationTester {
        try self.test(
            method,
            path,
            headers: headers,
            body: body,
            file: file,
            line: line,
            beforeRequest: { _ in },
            afterResponse: afterResponse
        )
    }

    @discardableResult
    public func test(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        beforeRequest: (inout XCTHTTPRequest) async throws -> () = { _ in },
        afterResponse: (XCTHTTPResponse) async throws -> () = { _ in }
    ) async throws -> XCTApplicationTester {
        XCTVaporContext.warnIfInSwiftTestingContext(file: file, line: line)

        var request = XCTHTTPRequest(
            method: method,
            url: .init(path: path),
            headers: headers,
            body: body ?? ByteBufferAllocator().buffer(capacity: 0)
        )
        try await beforeRequest(&request)
        do {
            let response = try await self.performTest(request: request)
            try await afterResponse(response)
        } catch {
            XCTFail("\(String(reflecting: error))", file: file, line: line)
            throw error
        }
        return self
    }

    @available(*, noasync, message: "Use the async method instead.")
    @discardableResult
    public func test(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        beforeRequest: (inout XCTHTTPRequest) throws -> () = { _ in },
        afterResponse: (XCTHTTPResponse) throws -> () = { _ in }
    ) throws -> XCTApplicationTester {
        XCTVaporContext.warnIfInSwiftTestingContext(file: file, line: line)

        var request = XCTHTTPRequest(
            method: method,
            url: .init(path: path),
            headers: headers,
            body: body ?? ByteBufferAllocator().buffer(capacity: 0)
        )
        try beforeRequest(&request)
        do {
            let response = try self.performTest(request: request)
            try afterResponse(response)
        } catch {
            XCTFail("\(String(reflecting: error))", file: file, line: line)
            throw error
        }
        return self
    }
    
    public func sendRequest(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        beforeRequest: (inout XCTHTTPRequest) async throws -> () = { _ in }
    ) async throws -> XCTHTTPResponse {
        XCTVaporContext.warnIfInSwiftTestingContext(file: file, line: line)

        var request = XCTHTTPRequest(
            method: method,
            url: .init(path: path),
            headers: headers,
            body: body ?? ByteBufferAllocator().buffer(capacity: 0)
        )
        try await beforeRequest(&request)
        do {
            return try await self.performTest(request: request)
        } catch {
            XCTFail("\(String(reflecting: error))", file: file, line: line)
            throw error
        }
    }

    @available(*, noasync, message: "Use the async method instead.")
    public func sendRequest(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        beforeRequest: (inout XCTHTTPRequest) throws -> () = { _ in }
    ) throws -> XCTHTTPResponse {
        XCTVaporContext.warnIfInSwiftTestingContext(file: file, line: line)

        var request = XCTHTTPRequest(
            method: method,
            url: .init(path: path),
            headers: headers,
            body: body ?? ByteBufferAllocator().buffer(capacity: 0)
        )
        try beforeRequest(&request)
        do {
            return try self.performTest(request: request)
        } catch {
            XCTFail("\(String(reflecting: error))", file: file, line: line)
            throw error
        }
    }
}
