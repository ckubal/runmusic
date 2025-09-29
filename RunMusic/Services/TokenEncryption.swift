import Foundation
import CryptoKit

struct TokenEncryption {
    static let shared = TokenEncryption()
    
    private init() {}
    
    // Generate a key from the user's Firebase UID for consistent encryption across devices
    private func generateKey(from userId: String) -> SymmetricKey {
        let keyData = userId.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: keyData)
        return SymmetricKey(data: hash)
    }
    
    func encryptTokenData(tokenData: Data, userId: String) throws -> EncryptedToken {
        let key = generateKey(from: userId)
        let sealedBox = try AES.GCM.seal(tokenData, using: key)
        
        guard let encryptedData = sealedBox.ciphertext.base64EncodedString().data(using: .utf8),
              let iv = sealedBox.nonce.withUnsafeBytes({ Data($0) }).base64EncodedString().data(using: .utf8),
              let tag = sealedBox.tag.base64EncodedString().data(using: .utf8) else {
            throw TokenEncryptionError.encryptionFailed
        }
        
        return EncryptedToken(
            encryptedData: String(data: encryptedData, encoding: .utf8) ?? "",
            iv: String(data: iv, encoding: .utf8) ?? "",
            tag: String(data: tag, encoding: .utf8) ?? ""
        )
    }
    
    func decryptTokenData(encryptedToken: EncryptedToken, userId: String) throws -> Data {
        let key = generateKey(from: userId)
        
        guard let encryptedData = Data(base64Encoded: encryptedToken.encryptedData),
              let ivData = Data(base64Encoded: encryptedToken.iv),
              let tagData = Data(base64Encoded: encryptedToken.tag) else {
            throw TokenEncryptionError.invalidEncryptedData
        }
        
        let nonce = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encryptedData, tag: tagData)
        
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    // Convenience methods for token strings
    func encryptTokenString(_ tokenString: String, userId: String) throws -> EncryptedToken {
        guard let tokenData = tokenString.data(using: .utf8) else {
            throw TokenEncryptionError.invalidTokenString
        }
        return try encryptTokenData(tokenData: tokenData, userId: userId)
    }
    
    func decryptTokenString(encryptedToken: EncryptedToken, userId: String) throws -> String {
        let tokenData = try decryptTokenData(encryptedToken: encryptedToken, userId: userId)
        guard let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw TokenEncryptionError.decryptionFailed
        }
        return tokenString
    }
}

enum TokenEncryptionError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidEncryptedData
    case invalidTokenString
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt token data"
        case .decryptionFailed:
            return "Failed to decrypt token data"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        case .invalidTokenString:
            return "Invalid token string"
        }
    }
}

// MARK: - Token Storage Models

struct StorableTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    
    init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}