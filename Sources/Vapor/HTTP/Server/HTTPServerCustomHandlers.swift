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
    func input(request: Data, context: ChannelHandlerContext) throws -> Data
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取
    func output(response: Data, context: ChannelHandlerContext) throws -> Data
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    func input(request: ByteBuffer, context: ChannelHandlerContext) throws -> ByteBuffer
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    func output(response: ByteBuffer, context: ChannelHandlerContext) throws -> ByteBuffer
}

public extension HTTPIOHandler {
    
    func input(request: Data, context: ChannelHandlerContext) throws -> Data { request }
    
    func output(response: Data, context: ChannelHandlerContext) throws -> Data { response }
    
    func input(request: ByteBuffer, context: ChannelHandlerContext) throws -> ByteBuffer {
        let req = Data(buffer: request)
        return try dataToByteBuffer(data: input(request: req, context: context))
    }
    
    func output(response: ByteBuffer, context: ChannelHandlerContext) throws -> ByteBuffer {
        let res = Data(buffer: response)
        return try dataToByteBuffer(data: output(response: res, context: context))
    }
    
    private func dataToByteBuffer(data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}

final class CustomCryptoIOHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    let logger: Logger
    let ioHandler: HTTPIOHandler
    let context: ChannelHandlerContext
    
    var bytes: [ByteBuffer] = []
    var i = 0
    
    init(logger: Logger, ioHandler: HTTPIOHandler, context: ChannelHandlerContext) {
        self.logger = logger
        self.ioHandler = ioHandler
        self.context = context
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        do {
            let req = try ioHandler.input(request: buffer, context: context)
            context.fireChannelRead(self.wrapOutboundOut(req))
        } catch let err {
            errorCaught(context: context, input: true, error: err)
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        bytes.append(buffer)
        i += 1
        if i == 3 {
            var res = ByteBufferAllocator().buffer(capacity: 0)
            for b in bytes {
                var bb = b
                res.writeBuffer(&bb)
            }
            i = 0
            do {
                let res = try ioHandler.output(response: res, context: context)
                context.writeAndFlush(self.wrapOutboundOut(res), promise: promise)
            } catch let err {
                errorCaught(context: context, input: false, error: err)
            }
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, input: Bool, error: Error) {
        self.logger.debug("\(input ? "Input" : "Output") HTTP 流加解密失败 \(String(reflecting: error))")
        context.fireErrorCaught(error)
    }
}
