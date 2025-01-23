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
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    /// - 返回：解包过后的请求数据 Data
    func input(request: Data, context: ChannelHandlerContext, info: ChannelInfo) throws -> Data
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 Data
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    /// - 返回：处理过后的响应数据 Data
    func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo) throws -> Data
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 从客户端发来的原始的未解密的请求数据 ByteBuffer
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    /// - 返回：解包过后的请求数据 ByteBuffer
    func input(request: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo) throws -> ByteBuffer
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 ByteBuffer
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    /// - 返回：处理过后的响应数据 ByteBuffer
    func output(response: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo) throws -> ByteBuffer
}

public extension HTTPIOHandler {
    
    /// 默认不进行任何处理，直接将 request 作为返回值
    func input(request: Data, context: ChannelHandlerContext, info: ChannelInfo) throws -> Data { request }
    
    /// 默认不进行任何处理，直接将 response 作为返回值
    func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo) throws -> Data { response }
    
    /// 默认调用 `func input(request: Data, context: ChannelHandlerContext, info: ChannelInfo)` 完成处理
    func input(request: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo) throws -> ByteBuffer {
        let req = Data(buffer: request)
        return try dataToByteBuffer(data: input(request: req, context: context, info: info))
    }
    
    /// 默认调用 `func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo)` 完成处理
    func output(response: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo) throws -> ByteBuffer {
        let res = Data(buffer: response)
        return try dataToByteBuffer(data: output(response: res, context: context, info: info))
    }
    
    private func dataToByteBuffer(data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}

final internal class CustomCryptoIOHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    var logger: Logger { app.logger }
    let ioHandler: HTTPIOHandler?
    let app: Application
    
    var bytes: [ByteBuffer] = []
    var i = 0
    
    init(app: Application, ioHandler: HTTPIOHandler?) {
        self.app = app
        self.ioHandler = ioHandler
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        let channelInfo = app.channels[context.channel]!
        if let ioHandler = self.ioHandler {
            do {
                let req = try ioHandler.input(request: buffer, context: context, info: channelInfo)
                context.fireChannelRead(self.wrapOutboundOut(req))
            } catch let err {
                errorCaught(context: context, input: true, error: err)
            }
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
                do {
                    let res = try ioHandler.output(response: res, context: context, info: channelInfo)
                    context.writeAndFlush(self.wrapOutboundOut(res), promise: promise)
                } catch let err {
                    errorCaught(context: context, input: false, error: err)
                }
            }
        } else {
            bytes.removeAll()
            context.writeAndFlush(data, promise: promise)
        }
    }
    
    func channelRegistered(context: ChannelHandlerContext) {
        app.channels[context.channel] = .init()
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        app.channels[context.channel] = nil
        context.fireChannelInactive()
    }
    
    func errorCaught(context: ChannelHandlerContext, input: Bool, error: Error) {
        self.logger.debug("\(input ? "Input" : "Output") HTTP 流加解密失败 \(String(reflecting: error))")
        context.fireErrorCaught(error)
    }
}
