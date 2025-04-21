import NIOCore
import Logging

public extension Application {
    /// 为 HTTP IO 流配置流处理，如果为 nil，则不进行任何处理
    var httpIOHandler: HTTPIOHandler? { self.storage[HttpIoHandler.self] }
    
    func use(httpIOHandler handler: HTTPIOHandler) {
        self.storage[HttpIoHandler.self] = handler
    }
    
    struct HttpIoHandler: StorageKey, Sendable {
        public typealias Value = HTTPIOHandler
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
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文
    ///
    /// - 参数：
    ///     - request: 从客户端发来的原始的未解密的请求数据 Data
    ///     - context: 该请求连线的上下文
    /// - 返回：解包过后的请求数据 Data，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    func input(request: Data, context: ChannelHandlerContext) -> EventLoopFuture<Data?>
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 Data
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    /// - 返回：处理过后的响应数据 Data，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Data?>
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 从客户端发来的原始的未解密的请求数据 ByteBuffer
    ///     - context: 该请求连线的上下文
    /// - 返回：解包过后的请求数据 ByteBuffer，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    func input(request: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer?>
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 ByteBuffer
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    /// - 返回：处理过后的响应数据 ByteBuffer，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    func output(response: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<ByteBuffer?>
    
    /// 当连线建立后，调用此方法，不提供 Info 参数，因为此时还未初始化该参数。默认不进行任何动作
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void>
    
    /// 当连线将终止后，调用此方法。默认不进行任何动作
    func connectionEnd(context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Void>
}

public extension HTTPIOHandler {
    
    /// 默认不进行任何处理，直接将 request 作为返回值
    func input(request: Data, context: ChannelHandlerContext) -> EventLoopFuture<Data?> { context.eventLoop.makeSucceededFuture(request) }
    
    /// 默认不进行任何处理，直接将 response 作为返回值
    func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Data?> { context.eventLoop.makeSucceededFuture(response) }
    
    /// 默认调用 `func input(request: Data, context: ChannelHandlerContext, info: ChannelInfo)` 完成处理
    func input(request: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer?> {
        let req = Data(buffer: request)
        return input(request: req, context: context).map { reqData in
            guard let data = reqData else { return nil }
            return dataToByteBuffer(data: data)
        }
    }
    
    /// 默认调用 `func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo)` 完成处理
    func output(response: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<ByteBuffer?> {
        let res = Data(buffer: response)
        return output(response: res, context: context, info: info).map { resData in
            guard let data = resData else { return nil }
            return dataToByteBuffer(data: data)
        }
    }
    
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    
    func connectionEnd(context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    
    private func dataToByteBuffer(data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}

final internal class CustomCryptoIOHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    var logger: Logger { app.logger }
    let ioHandler: HTTPIOHandler?
    let app: Application
    
    private var bytes: [ByteBuffer] = []
    private var i = 0
    
    init(app: Application, ioHandler: HTTPIOHandler?) {
        self.app = app
        self.ioHandler = ioHandler
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        if let ioHandler = self.ioHandler {
            ioHandler.input(request: buffer, context: context).flatMap { req in
                if let r = req { context.fireChannelRead(self.wrapOutboundOut(r)) }
                return context.eventLoop.makeSucceededVoidFuture()
            }.flatMapError { err in
                print("error happend")
                self.errorCaught(context: context, label: "Input", error: err)
                return context.eventLoop.makeFailedFuture(err)
            }.whenComplete { _ in }
        } else {
            context.fireChannelRead(data)
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        let channelInfo = app.channels[context.channel]!
        if let ioHandler = self.ioHandler {
            bytes.append(buffer)
            i += 1
            if i == channelInfo.serializeSegment {
                defer {
                    bytes.removeAll()
                }
                var res = ByteBufferAllocator().buffer(capacity: 0)
                for b in bytes {
                    var bb = b
                    res.writeBuffer(&bb)
                }
                i = 0
                ioHandler.output(response: res, context: context, info: channelInfo).flatMap { res in
                    if let r = res { context.writeAndFlush(self.wrapOutboundOut(r), promise: promise) }
                    return context.eventLoop.makeSucceededVoidFuture()
                }.flatMapError { err in
                    self.errorCaught(context: context, label: "Output", error: err)
                    promise?.fail(err)
                    return context.eventLoop.makeFailedFuture(err)
                }.whenComplete { _ in }
            }
        } else {
            bytes.removeAll()
            context.writeAndFlush(data, promise: promise)
        }
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        print("channelInactive 被触发，连接真的关闭了")
        context.fireChannelInactive()
    }
    
    func channelRegistered(context: ChannelHandlerContext) {
        guard let handler = ioHandler else { self.app.channels[context.channel] = .init(); return }
        handler.connectionStart(context: context).flatMapError { err in
            self.errorCaught(context: context, label: "连线建立", error: err)
            return context.eventLoop.makeFailedFuture(err)
        }.whenComplete { _ in self.app.channels[context.channel] = .init() }
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        guard let handler = ioHandler else { end(); return }
        handler.connectionEnd(context: context, info: app.channels[context.channel]!).flatMapError { err in
            self.errorCaught(context: context, label: "连线终止", error: err)
            return context.eventLoop.makeFailedFuture(err)
        }.whenComplete { _ in end() }
        @Sendable func end() {
            app.channels[context.channel] = nil
            context.fireChannelInactive()
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, label: String, error: Error) {
        self.logger.debug("HTTP 流 \(label) 时加解密失败: \(String(reflecting: error))")
        context.fireErrorCaught(error)
        context.close(promise: nil)
    }
}

extension ChannelHandlerContext: @retroactive @unchecked Sendable {}
