import NIOCore
import Logging
import NIOHTTP1
import Foundation

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
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：解包过后的请求数据 Data，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    /// - 注意：当 streaming 为 true 时，不会考虑您的返回值，无论其为 nil 或 Data
    func input(request: Data, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<Data?>
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 Data
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：处理过后的响应数据 Data
    func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo, streaming: Bool) -> EventLoopFuture<Data>
    /// 当接受到请求时，解析传来的请求。通常是进行解密操作，以将密文转为下一步可解析的 HTTP 报文。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 从客户端发来的原始的未解密的请求数据 ByteBuffer
    ///     - context: 该请求连线的上下文
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：解包过后的请求数据 ByteBuffer，若返回 nil 则意味着捕获该请求，而不再进行后续处理
    /// - 注意：当 streaming 为 true 时，不会考虑您的返回值，无论其为 nil 或 Data
    func input(request: ByteBuffer, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<ByteBuffer?>
    /// 当该服务器对客户端做出响应时，包装将要做出的响应。通常是进行加密操作，以保护响应不被窃取。免去 ByteBuffer 与 Data 互转的步骤，直接操作 ByteBuffer，更加轻量
    ///
    /// - 参数：
    ///     - request: 服务器将要发送给客户端的响应数据 ByteBuffer
    ///     - context: 该请求连线的上下文，可以通过其获取对应的 Info，见下一个参数
    ///     - info: 该连线的附加信息，包括是否为 WebSocket，以及当前请求的 ID
    ///     - streaming: 表示当前数据正在分片传送中，尚未完成
    /// - 返回：处理过后的响应数据 ByteBuffer
    func output(response: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo, streaming: Bool) -> EventLoopFuture<ByteBuffer>
    
    /// 当连线建立后，调用此方法，不提供 Info 参数，因为此时还未初始化该参数。默认不进行任何动作
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void>
    
    /// 当连线将终止后，调用此方法。默认不进行任何动作
    func connectionEnd(context: ChannelHandlerContext, info: ChannelInfo) -> EventLoopFuture<Void>
}

public extension HTTPIOHandler {
    
    /// 默认不进行任何处理，直接将 request 作为返回值
    func input(request: Data, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<Data?> { context.eventLoop.makeSucceededFuture(request) }
    
    /// 默认不进行任何处理，直接将 response 作为返回值
    func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo, streaming: Bool) -> EventLoopFuture<Data> { context.eventLoop.makeSucceededFuture(response) }
    
    /// 默认调用 `func input(request: Data, context: ChannelHandlerContext, info: ChannelInfo)` 完成处理
    func input(request: ByteBuffer, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<ByteBuffer?> {
        let req = Data(buffer: request)
        return input(request: req, context: context, streaming: streaming).map { reqData in
            guard let data = reqData else { return nil }
            return dataToByteBuffer(data: data)
        }
    }
    
    /// 默认调用 `func output(response: Data, context: ChannelHandlerContext, info: ChannelInfo)` 完成处理
    func output(response: ByteBuffer, context: ChannelHandlerContext, info: ChannelInfo, streaming: Bool) -> EventLoopFuture<ByteBuffer> {
        let res = Data(buffer: response)
        return output(response: res, context: context, info: info, streaming: streaming).map { resData in
            return dataToByteBuffer(data: resData)
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

public struct ChunkTool {
    public static var maxChunk: Int { 8192 }

    public static var maxChunkStr: String { formatByteSize(maxChunk) }

    public static let eof = ByteBuffer(string: "EOF")

    public static func formatByteSize(_ bytes: Int) -> String {
        let units = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB"]
        
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.2f %@", size, units[unitIndex])
    }

    public static func isProperSize(bytes: Int) -> Bool { bytes <= maxChunk }

    public static func concatenateBuffers(_ buffer1: inout ByteBuffer, _ buffer2: inout ByteBuffer) -> ByteBuffer {
        let totalSize = buffer1.readableBytes + buffer2.readableBytes
        var resultBuffer = ByteBufferAllocator().buffer(capacity: totalSize)
        resultBuffer.writeBuffer(&buffer1)
        resultBuffer.writeBuffer(&buffer2)
        return resultBuffer
    }
}

final internal class CustomCryptoIOHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    var logger: Logger { app.logger }
    let ioHandler: HTTPIOHandler?
    let app: Application
    
    private var buffers: [ByteBuffer] = []
    private var i = 0
    
    init(app: Application, ioHandler: HTTPIOHandler?) {
        self.app = app
        self.ioHandler = ioHandler
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = self.unwrapInboundIn(data)
        guard let ioHandler = self.ioHandler else { context.fireChannelRead(data); return }
        let streaming: Bool
        if let bufferSuffix = buffer.readSlice(length: ChunkTool.eof.readableBytes) { 
            streaming = bufferSuffix != ChunkTool.eof 
        } 
        else { streaming = true }
        if streaming { buffer.moveReaderIndex(to: 0) }
        ioHandler.input(request: buffer, context: context, streaming: streaming).whenComplete { result in
            switch result {
            case .success(let req):
                if let req = req {
                    context.fireChannelRead(self.wrapOutboundOut(req))
                }
            case .failure(let err):
                self.errorHappend(context: context, label: "Input", error: err)
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        let channelInfo = app.channels[context.channel]!
        if let _ = self.ioHandler {
            buffers.append(buffer)
            i += 1
            if i == channelInfo.serializeSegment {
                let r = send(chunk: buffers[0], streaming: true).flatMap {
                    var res = ByteBufferAllocator().buffer(capacity: 0)
                    for b in self.buffers[1..<self.buffers.count] {
                        var bb = b
                        res.writeBuffer(&bb)
                    }
                    return sendWithChunk(data: &res).map {
                        self.i = 0
                        self.buffers.removeAll()
                    }
                }
                if let p = promise { r.cascade(to: p) }
            }
        } else {
            buffers.removeAll()
            context.writeAndFlush(data, promise: promise)
        }

        @Sendable
        func sendWithChunk(data: inout ByteBuffer) -> EventLoopFuture<Void> {
            var r = context.eventLoop.makeSucceededVoidFuture()
            while data.readableBytes > 0 {
                guard let chunk = data.readSlice(length: min(ChunkTool.maxChunk, data.readableBytes)) else { break }
                let eof = data.readableBytes == 0
                r = r.flatMap {
                    send(chunk: chunk, streaming: !eof)
                }
            }
            
            return r.flatMapError { err in
                self.errorHappend(context: context, label: "Output", error: err)
                return context.eventLoop.makeFailedFuture(err)
            }
        }

        @Sendable
        func send(chunk: ByteBuffer, streaming: Bool) -> EventLoopFuture<Void> {
            guard let ioHandler = self.ioHandler else { return context.eventLoop.makeSucceededVoidFuture() }
            return ioHandler.output(response: chunk, context: context, info: channelInfo, streaming: streaming).flatMap { res in
                if !streaming {
                    var r = res
                    var eof = ChunkTool.eof
                    return context.writeAndFlush(self.wrapOutboundOut(ChunkTool.concatenateBuffers(&eof, &r))) 
                }
                return context.writeAndFlush(self.wrapOutboundOut(res))
            }
        }
    }

    func channelRegistered(context: ChannelHandlerContext) {
        guard let handler = ioHandler else { self.app.channels[context.channel] = .init(); return }
        handler.connectionStart(context: context).flatMapError { err in
            self.errorHappend(context: context, label: "连线建立", error: err)
            return context.eventLoop.makeFailedFuture(err)
        }.whenComplete { _ in self.app.channels[context.channel] = .init() }
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        guard let handler = ioHandler else { end(); return }
        handler.connectionEnd(context: context, info: app.channels[context.channel]!).flatMapError { err in
            self.errorHappend(context: context, label: "连线终止", error: err)
            return context.eventLoop.makeFailedFuture(err)
        }.whenComplete { _ in end() }
        @Sendable func end() {
            app.channels[context.channel] = nil
            context.fireChannelInactive()
        }
    }
    
    func errorHappend(context: ChannelHandlerContext, label: String, error: Error) {
        self.logger.report(error: error)
        struct BodyReply: Content {
            let error: Bool
            let reason: String
        }

        if context.channel.isActive {
            var headers = HTTPHeaders()
            var body = try! ByteBuffer(data: JSONEncoder().encode(BodyReply(error: true, reason: "\(error)")))
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Content-Length", value: "\(body.readableBytes)")
            headers.add(name: "Connection", value: "close")

            let head = HTTPResponseHead(
                version: .http1_1,
                status: ((error as? HTTPParserError) == .invalidChunkSize) ? .payloadTooLarge : .internalServerError,
                headers: headers
            )

            var buffer = ChunkTool.eof
            buffer.writeString(httpResponseHeadToString(head))
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

extension ChannelHandlerContext: @retroactive @unchecked Sendable {}