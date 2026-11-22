import Foundation

/// Exact internal authority carried by one public Connection handle.
struct ConnectionAuthority: Hashable, Sendable {
    /// Identity of the reusable Connection runtime/core.
    let coreId: ConnectionId
    /// Standalone-handle nonce or complete pooled checkout token.
    let generation: ConnectionAuthorityGeneration

    private init(
        coreId: ConnectionId,
        generation: ConnectionAuthorityGeneration
    ) {
        self.coreId = coreId
        self.generation = generation
    }

    /// Creates the unique transitional authority for one standalone handle.
    static func standalone(coreId: ConnectionId) -> ConnectionAuthority {
        ConnectionAuthority(
            coreId: coreId,
            generation: .standalone(StandaloneConnectionAuthorityId())
        )
    }

    /// Creates the exact authority for one pooled lease generation.
    static func pooled(_ token: ConnectionPoolLeaseToken) -> ConnectionAuthority {
        ConnectionAuthority(
            coreId: token.connectionID,
            generation: .pooled(token)
        )
    }

    /// Full pooled token when this authority represents a pooled checkout.
    var poolLeaseToken: ConnectionPoolLeaseToken? {
        guard case .pooled(let token) = generation else {
            return nil
        }
        return token
    }
}

/// Exact standalone-handle identity used only before canonical pooling is implemented.
struct StandaloneConnectionAuthorityId: Hashable, Sendable {
    /// Opaque nonce preventing standalone authority reuse across handles.
    let rawValue = UUID()
}

/// Distinguishes transitional standalone authority from exact pooled lease authority.
enum ConnectionAuthorityGeneration: Hashable, Sendable {
    /// Unique identity for one transitional standalone handle.
    case standalone(StandaloneConnectionAuthorityId)
    /// Full pool, core, and lease-generation token for pooled authority.
    case pooled(ConnectionPoolLeaseToken)
}
