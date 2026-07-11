import SwiftUI
import UIKit

// On-device "Sổ Bạn Nhỏ" (little-friends book) — the pet Pokédex. Photos are
// the collectible, so unlike the body scan (RAM-only), they persist — but
// strictly in the app sandbox: never uploaded, never written to the shared
// Photo library, excluded from iCloud backup. Catching mints NO activity
// points (petting a cat isn't exercise — economy firewall); progression is a
// purely local, cosmetic "collector level".

struct CaughtCritter: Codable, Identifiable {
    let id: UUID
    let species: String        // "cat" | "dog"
    let nickname: String
    let caughtAt: Date
    let photoFile: String      // filename inside the critters dir

    var critter: Critter { Critter(rawValue: species) ?? .cat }
}

struct CritterCollection: Codable {
    var critters: [CaughtCritter] = []
    /// Cosmetic-only XP; never touches points_ledger / the server.
    var collectorXP: Int = 0

    var collectorLevel: Int { 1 + collectorXP / 100 }
    var xpInLevel: Int { collectorXP % 100 }
    var catCount: Int { critters.filter { $0.species == "cat" }.count }
    var dogCount: Int { critters.filter { $0.species == "dog" }.count }

    /// Milestone badges derived from the collection — glory, not currency.
    var badges: [String] {
        var out: [String] = []
        if catCount >= 1 { out.append("🐱 Người bạn của mèo") }
        if dogCount >= 1 { out.append("🐶 Người bạn của cún") }
        if critters.count >= 5 { out.append("🌟 Nhà sưu tầm nhí") }
        if critters.count >= 15 { out.append("👑 Bậc thầy phố mèo") }
        if catCount >= 3 && dogCount >= 3 { out.append("🤝 Hòa giải chó mèo") }
        return out
    }
}

enum CritterStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("critters", isDirectory: true)
    }
    private static var jsonURL: URL { dir.appendingPathComponent("collection.json") }

    static func load() -> CritterCollection {
        guard let data = try? Data(contentsOf: jsonURL) else {
            return CritterCollection() // no file yet — genuinely empty
        }
        if let coll = try? JSONDecoder().decode(CritterCollection.self, from: data) {
            return coll
        }
        // File exists but won't decode (corruption, or a future schema change).
        // Do NOT silently return empty — that would let the next add() atomically
        // overwrite and destroy the user's collection. Preserve it aside so the
        // photos + metadata are recoverable, then start a fresh book.
        let backup = dir.appendingPathComponent("collection.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: jsonURL, to: backup)
        return CritterCollection()
    }

    private static func save(_ coll: CritterCollection) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        excludeFromBackup()
        if let data = try? JSONEncoder().encode(coll) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }

    /// Persists the catch photo + metadata, bumps cosmetic collector XP,
    /// returns the new entry. All local.
    @discardableResult
    static func add(_ image: UIImage, species: Critter) -> CaughtCritter {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID()
        let file = "\(id.uuidString).jpg"
        if let jpeg = image.jpegData(compressionQuality: 0.82) {
            try? jpeg.write(to: dir.appendingPathComponent(file), options: .atomic)
        }
        let entry = CaughtCritter(
            id: id,
            species: species.rawValue,
            nickname: randomName(for: species),
            caughtAt: Date(),
            photoFile: file
        )
        var coll = load()
        coll.critters.insert(entry, at: 0)
        coll.collectorXP += 10
        save(coll)
        return entry
    }

    static func image(_ c: CaughtCritter) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(c.photoFile).path)
    }

    private static func excludeFromBackup() {
        var url = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // Cute Vietnamese pet names.
    private static let catNames = [
        "Mèo Mun", "Mèo Sữa", "Mèo Vàng", "Mèo Mướp", "Miu Miu",
        "Mèo Bơ", "Nhọ", "Cam Cam", "Mèo Khoang", "Bối Bối",
    ]
    private static let dogNames = [
        "Cún Bơ", "Cún Vàng", "Đốm", "Vện", "Milu",
        "Cà Phê", "Bông", "Lucky", "Mực", "Na Na",
    ]

    private static func randomName(for species: Critter) -> String {
        let pool = species == .cat ? catNames : dogNames
        return pool.randomElement() ?? species.label
    }
}
