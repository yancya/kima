import Foundation

// MARK: - JSON-RPC Types

public struct JSONRPCRequest: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var id: Int
    public var method: String
    public var params: [String: JSONValue]?

    public init(id: Int, method: String, params: [String: JSONValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var id: Int
    public var result: JSONValue?
    public var error: JSONRPCError?

    public init(id: Int, result: JSONValue? = nil, error: JSONRPCError? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - JSON Value

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - RPC Method Names

public enum RPCMethod {
    public static let containerRun = "container.run"
    public static let containerPs = "container.ps"
    public static let containerStop = "container.stop"
    public static let containerRm = "container.rm"
    public static let imagePull = "image.pull"
    public static let imageList = "image.list"
    public static let machineStatus = "machine.status"
}
