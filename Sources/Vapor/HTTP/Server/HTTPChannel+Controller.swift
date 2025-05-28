//import NIOCore
//
//public extension Application {
//    /// 记录了当前所有客户端连线的 Channel 信息，其中包括当前请求的 ID，以及是否为 WebSocket 连线的附加信息
//    var channels: Channels? { self.storage[Channels.self] }
//}
//
///// 记录了当前所有客户端连线的 Channel 信息，其中包括当前请求的 ID，以及是否为 WebSocket 连线的附加信息
/////
///// 可以通过 `app.channels` 取得该对象
//final public class Channels: StorageKey, @unchecked Sendable {
//    public typealias Value = Channels
//    
//    private var channelInfos: [ObjectIdentifier: (Channel, ChannelInfo)] = [:]
//    private var channels: [ObjectIdentifier: Channel] = [:]
//    private let lock = DispatchQueue(label: "woo.sys.channels.controller.lock")
//    
//    /// 获取所有的连线 Channel
//    public var allChannels: [ObjectIdentifier: Channel].Values {
//        lock.sync { channels.values }
//    }
//    
//    /// 支持字典语法，按 Channel 获取对应的 ChannelInfo，`app.channels[yourChannel]`
//    public internal(set) subscript(channel: Channel) -> ChannelInfo? {
//        get {
//            let identifier = ObjectIdentifier(channel)
//            return lock.sync {
//                channelInfos[identifier]?.1
//            }
//        }
//        set {
//            let identifier = ObjectIdentifier(channel)
//            if let info = newValue {
//                lock.sync {
//                    channelInfos[identifier] = (channel, info)
//                    channels[ObjectIdentifier(info)] = channel
//                }
//            } else {
//                lock.sync {
//                    if let info = channelInfos[identifier]?.1 { _ = channels.removeValue(forKey: ObjectIdentifier(info)) }
//                    _ = channelInfos.removeValue(forKey: identifier)
//                }
//            }
//        }
//    }
//    
//    /// 支持字典语法，按请求 ID 获取 ChannelInfo，`app.channels[request.id]`
//    public subscript(requestId: String) -> Channel? {
//        for (_, v) in channelInfos {
//            if v.1.currentRequestID == requestId {
//                return v.0
//            }
//        }
//        return nil
//    }
//    
//    public subscript(info: ChannelInfo) -> Channel? { channels[ObjectIdentifier(info)] }
//    
//    internal init() {}
//    
//    // 添加上下文
//    internal func add(channel: Channel) {
//        let identifier = ObjectIdentifier(channel)
//        lock.sync {
//            channelInfos[identifier] = (channel, ChannelInfo())
//        }
//    }
//    
//    // 移除上下文
//    internal func remove(channel: Channel) {
//        let identifier = ObjectIdentifier(channel)
//        lock.sync {
//            let _ = channelInfos.removeValue(forKey: identifier)
//        }
//    }
//}
//
//public final class ChannelInfo: @unchecked Sendable {
//    public internal(set) var upgraded: Bool = false
//    public internal(set) var contentSize: Int? = nil
//    public internal(set) var currentRequestID: String! = nil
//    internal var serializeSegment: Int { upgraded ? 2 : 3 }
//}
