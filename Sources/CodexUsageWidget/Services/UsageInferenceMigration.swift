import Foundation

extension UsageIndexStore {
    func migrateInferenceRecordingStart(home: URL, now: Date) throws {
        guard try rows("SELECT value FROM index_meta WHERE key='inference-recording-start'",limit:1).isEmpty else { return }
        struct Recording: Decodable { let recordingStartedAt: Date }
        struct Envelope: Decodable { let version: Int; let archive: Recording }
        let path=home.appendingPathComponent("Library/Application Support/codexU/inference-performance-v1.json")
        var started=now
        if let metadata=try? path.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey]),metadata.isSymbolicLink != true,
           let size=metadata.fileSize,size<=32*1024*1024,
           let data=try? Data(contentsOf:path,options:.mappedIfSafe),
           let envelope=try? JSONDecoder().decode(Envelope.self,from:data),envelope.version==1 {
            started=min(started,envelope.archive.recordingStartedAt)
        }
        try execute("INSERT OR IGNORE INTO index_meta(key,value) VALUES ('inference-recording-start',?)",[.text(String(started.timeIntervalSince1970))])
    }
}
