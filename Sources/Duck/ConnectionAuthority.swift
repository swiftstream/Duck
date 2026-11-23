import Foundation

/// Exact internal authority carried by one public Connection handle.
struct ConnectionAuthority: Hashable, Sendable {
    /// Identity of the reusable Connection runtime/core.
    let coreId: ConnectionId
    /// Standalone-handle nonce or complete pooled checkout token and ownership.
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

    /// Creates the exact authority for one checkout with the supplied ownership.
    static func pooled(
        _ token: ConnectionPoolLeaseToken,
        ownership: ConnectionPoolLeaseOwnership = .scoped
    ) -> ConnectionAuthority {
        ConnectionAuthority(
            coreId: token.connectionID,
            generation: .pooled(token, ownership)
        )
    }

    /// Full pooled token when this authority represents a pooled checkout.
    var poolLeaseToken: ConnectionPoolLeaseToken? {
        guard case .pooled(let token, _) = generation else {
            return nil
        }
        return token
    }

    /// Exact token when this authority owns a manually held Pool checkout.
    var manualPoolLeaseToken: ConnectionPoolLeaseToken? {
        guard case .pooled(let token, .manual) = generation else {
            return nil
        }
        return token
    }

    /// Scoped leases admit user operations only within their matching dynamic scope.
    var permitsCurrentScope: Bool {
        switch generation {
        case .pooled(let token, .scoped):
            return token == ConnectionPoolLeaseContext.current
        case .pooled(_, .manual), .standalone:
            return true
        }
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
    /// Full pool, core, and lease-generation token with its checkout ownership.
    case pooled(ConnectionPoolLeaseToken, ConnectionPoolLeaseOwnership)
}

/// Distinguishes closure-scoped checkout from a manually held lease.
enum ConnectionPoolLeaseOwnership: Hashable, Sendable {
    /// The caller borrows the handle inside a pool-managed dynamic scope.
    case scoped
    /// The caller owns the handle across calls until the lease is released.
    case manual
}
