import NIOCore
import Logging
import NIOHTTP1
import NIOAdvanced
import Foundation
import NIOFoundationCompat

public extension Application {
    /// 为 HTTP IO 流配置流处理，如果为 nil，则不进行任何处理
    @inlinable
    var httpIOHandler: AnyHTTPIOHandler? { self.storage[HttpIoHandler.self] }
    
    @inlinable
    func use(httpIOHandler handler: AnyHTTPIOHandler) {
        self.storage[HttpIoHandler.self] = handler
    }
    
    @frozen
    struct HttpIoHandler: StorageKey, Sendable {
        public typealias Value = AnyHTTPIOHandler
    }
}

/// 实现该协议为 HTTP IO 流配置流处理，例如加解密
///
/// 可以实现 `func input(request: Data) throws -> Data` 以及 `func output(response: Data) throws -> Data` 方法对
///
/// 或 `func input(request: ByteBuffer) throws -> ByteBuffer` 和 `func output(response: ByteBuffer) throws -> ByteBuffer` 方法对
///
/// 它们的作用相同，不同仅仅在于数据类型不同，后者免去了从底层 ByteBuffer 与 Data 互转的步骤，直接操作更底层的 ByteBuffer，更加轻量
public protocol HTTPIOHandler: Sendable {
    
    associatedtype Failure: Error
    
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文
    ///
    /// - 参数：
    ///     - request: 从客户端发来的原始的未解密的请求数据 Data
    ///     - context: 该请求连线的上下文
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：解包过后的请求数据 Data，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    /// - 注意：当 streaming 为 true 时，不会考虑您的返回值，无论其为 nil 或 Data
    func input(request: Data, context: ChannelHandlerContext) -> EventLoopResult<Data, Failure>
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 Data
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：处理过后的响应数据 Data
    func output(response: Data, context: ChannelHandlerContext) -> EventLoopResult<Data, Failure>
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 从客户端发来的原始的未解密的请求数据 ByteBuffer
    ///     - context: 该请求连线的上下文
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：解包过后的请求数据 ByteBuffer，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    /// - 注意：当 streaming 为 true 时，不会考虑您的返回值，无论其为 nil 或 Data
    func input(request: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, Failure>
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 ByteBuffer
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：处理过后的响应数据 ByteBuffer
    func output(response: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, Failure>
    
    /// 当连线建立后，调用此方法，不提供 Info 参数，因为此时还未初始化该参数。默认不进行任何动作
    func connectionStart(context: ChannelHandlerContext) -> EventLoopResult<Void, Failure>
    
    /// 当连线将终止后，调用此方法。默认不进行任何动作
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopResult<Void, Failure>
}

public extension HTTPIOHandler {
    
    /// 默认不进行任何处理，直接将 request 作为返回值
    @inlinable
    func input(request: Data, context: ChannelHandlerContext) -> EventLoopResult<Data, Failure> { context.eventLoop.makeSucceededResult(request) }
    
    /// 默认不进行任何处理，直接将 response 作为返回值
    @inlinable
    func output(response: Data, context: ChannelHandlerContext) -> EventLoopResult<Data, Failure> { context.eventLoop.makeSucceededResult(response) }
    
    /// 默认调用 `func input(request: Data, context: ChannelHandlerContext)` 完成处理
    @inlinable
    func input(request: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, Failure> {
        let req = Data(buffer: request)
        return input(request: req, context: context).map { reqData in
            return dataToByteBuffer(data: reqData)
        }
    }
    
    /// 默认调用 `func output(response: Data, context: ChannelHandlerContext)` 完成处理
    @inlinable
    func output(response: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, Failure> {
        let res = Data(buffer: response)
        return output(response: res, context: context).map { resData in
            return dataToByteBuffer(data: resData)
        }
    }
    
    @inlinable
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    
    @inlinable
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    
    @usableFromInline
    internal func dataToByteBuffer(data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}

final internal class CustomCryptoIOHandler<IOHandler>: ChannelDuplexHandler, @unchecked Sendable where IOHandler: HTTPIOHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    let logger: Logger
    let ioHandler: IOHandler
    
    private var headerSent = false
    private var i: Int = 0

    init(ioHandler: IOHandler, logger: Logger) {
        self.ioHandler = ioHandler
        self.logger = logger
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        ioHandler.input(request: buffer, context: context).whenComplete { result in
            switch result {
            case .success(let req):
                context.fireChannelRead(self.wrapOutboundOut(req))
            case .failure(let err):
                self.errorHappend(context: context, label: "Input", error: err)
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        let res = ioHandler.output(response: buffer, context: context).wrapped.flatMap { res in
            return context.writeAndFlush(self.wrapOutboundOut(res))
        }
        
        if let p = promise {
            res.cascade(to: p)
        }
    }

    func channelRegistered(context: ChannelHandlerContext) {
        context.fireChannelRegistered()
        ioHandler.connectionStart(context: context).whenFailure { err in
            self.errorHappend(context: context, label: "连线建立", error: err)
        }
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        context.fireChannelUnregistered()
        ioHandler.connectionEnd(context: context).whenFailure { err in
            self.errorHappend(context: context, label: "连线终止", error: err)
        }
    }
    
    struct BodyReply: Content {
        let error: Bool
        let reason: String
    }
    
    func errorHappend(context: ChannelHandlerContext, label: String, error: Error) {
        self.logger.report(error: error)
        

        if context.channel.isActive {
            var headers = HTTPHeaders()
            var body = try! ByteBuffer(data: JSONEncoder().encode(BodyReply(error: true, reason: "\(error)")))
            headers.add(name: .contentType, value: "application/json")
            headers.add(name: .contentLength, value: "\(body.readableBytes)")
            headers.add(name: .connection, value: "close")

            let head = HTTPResponseHead(
                version: .http1_1,
                status: ((error as? HTTPParserError) == .invalidChunkSize) ? .payloadTooLarge : .internalServerError,
                headers: headers
            )

            var buffer = context.channel.allocator.buffer(string: httpResponseHeadToString(head))
            buffer.writeBuffer(&body)
            buffer.writeBytes([])
            context.writeAndFlush(self.wrapOutboundOut(buffer)).whenComplete { _ in
                context.close(promise: nil)
            }
        } else {
            context.close(promise: nil)
        }

        func httpResponseHeadToString(_ head: HTTPResponseHead) -> String {
            var lines: [String] = []
            let statusLine = "HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)"
            lines.append(statusLine)
            for (name, value) in head.headers {
                lines.append("\(name): \(value)")
            }
            lines.append("")
            return lines.joined(separator: "\r\n") + "\r\n"
        }
    }
}

extension ChannelHandlerContext: @unchecked @retroactive Sendable {}

@frozen
public struct AnyHTTPIOHandler: HTTPIOHandler, Sendable {
    
    @usableFromInline let _inputData: @Sendable (Data, ChannelHandlerContext) -> EventLoopResult<Data, any Error>
    @usableFromInline let _outputData: @Sendable (Data, ChannelHandlerContext) -> EventLoopResult<Data, any Error>
    @usableFromInline let _inputBuffer: @Sendable (ByteBuffer, ChannelHandlerContext) -> EventLoopResult<ByteBuffer, any Error>
    @usableFromInline let _outputBuffer: @Sendable (ByteBuffer, ChannelHandlerContext) -> EventLoopResult<ByteBuffer, any Error>
    @usableFromInline let _connectionStart: @Sendable (ChannelHandlerContext) -> EventLoopResult<Void, any Error>
    @usableFromInline let _connectionEnd: @Sendable (ChannelHandlerContext) -> EventLoopResult<Void, any Error>
    
    @inlinable
    public init<H: HTTPIOHandler>(_ base: H) {
        _inputData = { base.input(request: $0, context: $1).flatMapErrorThrowing { throw $0 } }
        _outputData = { base.output(response: $0, context: $1).flatMapErrorThrowing { throw $0 } }
        _inputBuffer = { base.input(request: $0, context: $1).flatMapErrorThrowing { throw $0 } }
        _outputBuffer = { base.output(response: $0, context: $1).flatMapErrorThrowing { throw $0 } }
        _connectionStart = { base.connectionStart(context: $0).flatMapErrorThrowing { throw $0 } }
        _connectionEnd = { base.connectionEnd(context: $0).flatMapErrorThrowing { throw $0 } }
    }
    
    @inlinable
    public func input(request: Data, context: ChannelHandlerContext) -> EventLoopResult<Data, any Error> {
        _inputData(request, context)
    }
    
    @inlinable
    public func output(response: Data, context: ChannelHandlerContext) -> EventLoopResult<Data, any Error> {
        _outputData(response, context)
    }
    
    @inlinable
    public func input(request: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, any Error> {
        _inputBuffer(request, context)
    }
    
    @inlinable
    public func output(response: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, any Error> {
        _outputBuffer(response, context)
    }
    
    @inlinable
    public func connectionStart(context: ChannelHandlerContext) -> EventLoopResult<Void, any Error> {
        _connectionStart(context)
    }
    
    @inlinable
    public func connectionEnd(context: ChannelHandlerContext) -> EventLoopResult<Void, any Error> {
        _connectionEnd(context)
    }
}
