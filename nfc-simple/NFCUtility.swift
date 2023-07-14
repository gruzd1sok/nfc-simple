//
//  NFCUtility.swift
//  nfc-simple
//
//  Created by Ilya Gruzdev on 21.12.2022.
//


import CoreNFC

typealias NFCReadingCompletion = (Result<TagModel?, NFCError>) -> Void
typealias ReadCompletion = (Result<NFCNDEFMessage?, NFCError>) -> Void

enum NFCError: Error {
    case unavailable
    case invalidated(Error)
    case invalidatedPayloadSize
}

class NFCUtility: NSObject {
    enum NFCAction {
        case read
        case write(message: String)
        case setup(tagModel: TagModel)
        
        var alertMessage: String {
            switch self {
            case .read:
                return "Поднесите iPhone к NFC метке для считывания"
            case let .write(message):
                return "Поднесите iPhone к NFC метке для записи \n\(message)"
            case .setup:
                return "Поднесите iPhone к NFC метке для перезаписи"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var session: NFCTagReaderSession?
    private var writeSession: NFCNDEFReaderSession?
    private let nfcAvailable: Bool
    private var action: NFCAction?
    private var completion: NFCReadingCompletion?
    
    
    // MARK: - Init
    
    override init() {
        self.nfcAvailable = NFCNDEFReaderSession.readingAvailable
    }
    
    // MARK: - Public Methods
    
    public func read(completion: NFCReadingCompletion? = nil) {
        guard nfcAvailable else {
            completion?(.failure(.unavailable))
            return
        }
        
        session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: self
        )
        
        action = .read
        self.completion = completion
        session?.alertMessage = action?.alertMessage ?? "Read NFC"
        session?.begin()
    }
    
    public func write(action: NFCAction, completion: NFCReadingCompletion? = nil) {
        guard nfcAvailable else {
            completion?(.failure(.unavailable))
            return
        }
        
        writeSession = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: false
        )
        
        self.action = action
        self.completion = completion
        writeSession?.alertMessage = self.action?.alertMessage ?? "Write NFC"
        writeSession?.begin()
    }
    
    // MARK: - Private Methods
    
    private func readTag(
        tag: NFCNDEFTag,
        readCompletion: ReadCompletion? = nil
    ) {
        tag.readNDEF { [weak self] message, error in
            guard
                let message,
                error == nil
            else {
                self?.session?.invalidate(errorMessage: "Could not decode tag data.")
                return
            }
            
            readCompletion?(.success(message))
            self?.session?.invalidate()
        }
    }
    
    private func getMifareTagUid(_ tag: NFCMiFareTag) -> String {
        var byteData = [UInt8]()
        tag.identifier.withUnsafeBytes { byteData.append(contentsOf: $0) }
        var uid = "0"
        byteData.forEach {
            uid.append(String($0, radix: 16))
        }
        return uid
    }
    
    private func getMifareTagFamily(_ tag: NFCMiFareTag) -> String {
        switch tag.mifareFamily {
        case .desfire:
            return "MiFare Desfire"
        case .plus:
            return "MiFare Plus"
        case .ultralight:
            return "MiFare Ultralight"
        case .unknown:
            return "unknown"
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCUtility: NFCTagReaderSessionDelegate {
    func readerSession(
        _ session: NFCReaderSession,
        didDetect tags: [__NFCTag]
    ) {
        // not used
    }
    
    func tagReaderSessionDidBecomeActive(
        _ session: NFCTagReaderSession
    ) {
        // not used
    }
    
    func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        // not used
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard
            let tag = tags.first,
            tags.count == 1
        else {
            session.alertMessage = "There are too many tags present. Remove all and then try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                session.invalidate(errorMessage: "Many tags")
            }
            return
        }
        
        var ndefTag: NFCNDEFTag
        var tagID = ""
        var tagType = ""
        
        switch tag {
        case let .miFare(mifareTag):
            tagID = getMifareTagUid(mifareTag)
            tagType = getMifareTagFamily(mifareTag)
            ndefTag = mifareTag
        case let .feliCa(felicaTag):
            ndefTag = felicaTag
        case let .iso15693(isoTag):
            ndefTag = isoTag
        case let .iso7816(isoTag):
            ndefTag = isoTag
        default:
            session.invalidate(errorMessage: "Unsupported tag")
            return
        }
        
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                session.invalidate(errorMessage: "Connection error. Please try again.")
                return
            }
            
            ndefTag.queryNDEFStatus() { status, _, error in
                switch (status, self.action) {
                case (.notSupported, _):
                    session.invalidate(errorMessage: "Unsupported tag.")
                case (.readOnly, .read), (.readWrite, .read):
                    self.readTag(tag: ndefTag) { message in
                        guard let message = try? message.get() else {
                            session.alertMessage = "Tag read success, NDEF message not found"
                            session.invalidate()
                            return
                        }
                        
                        guard let record = message.records.first,
                              var tagModel = try? JSONDecoder().decode(TagModel.self, from: record.payload) else {
                            self.session?.invalidate(errorMessage: "Could not decode tag data.")
                            return
                        }
                        tagModel.tagID = tagID
                        tagModel.tagType = tagType
                        self.completion?(.success(tagModel))
                        self.session?.alertMessage = "Tag read succcess: \(tagModel.name) \n\(tagModel.records)"
                        self.session?.invalidate()
                    }
                default:
                    break
                }
            }
        }
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCUtility: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Not used
    }
    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        // not used
    }
    
    func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: Error
    ) {
        guard
            let error = error as? NFCReaderError,
            error.code != .readerSessionInvalidationErrorFirstNDEFTagRead &&
            error.code != .readerSessionInvalidationErrorUserCanceled
        else {
            self.session = nil
            self.completion = nil
            return
        }
        completion?(.failure(NFCError.invalidated(error)))
    }
    
    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetect tags: [NFCNDEFTag]
    ) {
        guard
            let tag = tags.first,
            tags.count == 1
        else {
            session.alertMessage = "There are too many tags present. Remove all and then try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                session.restartPolling()
            }
            return
        }
        
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            guard error == nil else {
                session.invalidate(errorMessage: "Connection error. Please try again.")
                return
            }
            
            tag.queryNDEFStatus { status, capacity, error in
                switch (status, self.action) {
                case (.notSupported, _):
                    session.invalidate(errorMessage: "Unsupported tag.")
                case (.readOnly, _):
                    session.invalidate(errorMessage: "Unable to write to tag.")
                case (.readWrite, let .setup(tagModel)):
                    guard let encodeTagModel = try? JSONEncoder().encode(tagModel) else { return }
                    
                    let payload = NFCNDEFPayload(
                        format: .unknown,
                        type: Data(),
                        identifier: Data(),
                        payload: encodeTagModel
                    )
                    
                    let message = NFCNDEFMessage(records: [payload])
                    
                    guard message.length <= capacity else {
                        self.completion?(.failure(.invalidatedPayloadSize))
                        session.invalidate(errorMessage: "Invalid Payload size")
                        return
                    }
                    
                    tag.writeNDEF(message) { error in
                        if let error {
                            debugPrint(error)
                            session.invalidate(errorMessage: error.localizedDescription)
                            return
                        }
                        self.completion?(.success(tagModel))
                        session.invalidate()
                    }
                case (.readWrite, let .write(recordMessage)):
                    self.readTag(tag: tag) { ndefMessage in
                        guard
                            let ndefMessage = try? ndefMessage.get(),
                            let record = ndefMessage.records.first,
                            var tagModel = try? JSONDecoder().decode(TagModel.self, from: record.payload)
                        else {
                            session.invalidate(errorMessage: "Cant decode tag data.")
                            return
                        }
                        
                        tagModel.records.append(recordMessage)
                        
                        guard let encodeTagModel = try? JSONEncoder().encode(tagModel) else {return }
                        
                        let payload = NFCNDEFPayload(
                            format: .unknown,
                            type: Data(),
                            identifier: Data(),
                            payload: encodeTagModel
                        )
                        
                        let message = NFCNDEFMessage(records: [payload])
                        
                        guard message.length <= capacity else {
                            self.completion?(.failure(.invalidatedPayloadSize))
                            session.invalidate(errorMessage: "Invalid Payload size")
                            return
                        }
                        
                        tag.writeNDEF(message) { error in
                            if let error = error {
                                debugPrint(error)
                                session.invalidate(errorMessage: error.localizedDescription)
                                return
                            }
                            self.completion?(.success(tagModel))
                            session.alertMessage = "Success add message"
                            session.invalidate()
                        }
                    }
                default:
                    return
                }
            }
        }
    }
}
