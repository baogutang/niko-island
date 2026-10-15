import XCTest
@testable import NikoCore

/// The version check (off by default) and the install path behind
/// "Install and restart", against stand-ins for GitHub.
final class UpdatesTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String] = []) -> Data {
        let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/baogutang/niko-island/releases/download/\#(tag)/\#($0)"}"# }
        return Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://github.com/baogutang/niko-island/releases/tag/\#(tag)","assets":[\#(list.joined(separator: ","))]}"#.utf8)
    }

    func testOnlyAPublishedReleaseWithAPlainVersionIsOffered() throws {
        let info = try XCTUnwrap(UpdateCheck.parse(release("v9.1.0", assets: ["Niko-Island-9.1.0-apple-silicon.zip", "Niko-Island-9.1.0-intel.dmg", "SHA256SUMS"])))
        XCTAssertEqual(info.version, "9.1.0")
        XCTAssertEqual(info.package(label: "apple-silicon")?.lastPathComponent, "Niko-Island-9.1.0-apple-silicon.zip")
        XCTAssertNil(info.package(label: "intel"), "only the disk image was published for Intel here")
        XCTAssertEqual(info.diskImage(label: "intel")?.lastPathComponent, "Niko-Island-9.1.0-intel.dmg")
        XCTAssertNotNil(info.checksums)
        XCTAssertNil(UpdateCheck.parse(release("v9.1.0", draft: true)))
        XCTAssertNil(UpdateCheck.parse(release("v9.1.0", prerelease: true)))
        XCTAssertNil(UpdateCheck.parse(release("nightly")))
        XCTAssertNil(UpdateCheck.parse(Data("not json".utf8)))
        // A download that would leave GitHub is not taken.
        let elsewhere = Data(#"{"tag_name":"v9.1.0","html_url":"https://github.com/x","assets":[{"name":"SHA256SUMS","browser_download_url":"https://example.com/SHA256SUMS"}]}"#.utf8)
        XCTAssertNil(try XCTUnwrap(UpdateCheck.parse(elsewhere)).checksums)
    }

    func testVersionsCompareAsNumbers() {
        XCTAssertEqual(UpdateCheck.normalized("v0.10.0"), "0.10.0")
        XCTAssertNil(UpdateCheck.normalized("v1.0.0-beta"))
        XCTAssertNil(UpdateCheck.normalized("1..2"))
        XCTAssertTrue(UpdateCheck.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0", than: "0.99.99"))
        XCTAssertFalse(UpdateCheck.isNewer("0.9.0", than: "0.9.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.9", than: "0.9.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.8.2", than: "0.9.0"))
    }

    func testChecksumsAreReadFromTheListing() {
        let digest = String(repeating: "ab", count: 32)
        let listing = "\(String(repeating: "0", count: 64))  Niko-Island-9.1.0-intel.zip\n\(digest) *Niko-Island-9.1.0-apple-silicon.zip\n"
        XCTAssertEqual(UpdateCheck.checksum(for: "Niko-Island-9.1.0-apple-silicon.zip", in: listing), digest)
        XCTAssertNil(UpdateCheck.checksum(for: "Niko-Island-9.1.0-apple-silicon.dmg", in: listing))
        XCTAssertNil(UpdateCheck.checksum(for: "x.zip", in: "nothex  x.zip"))
    }

    // MARK: Preparing an install

    /// A small app bundle with our identity, signed ad hoc, zipped the way a release is.
    private func package(in scratch: Scratch, version: String, identifier: String = NikoVersion.bundleIdentifier) throws -> URL {
        let app = scratch.file("build/\(NikoVersion.displayName).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                    "CFBundleExecutable": "niko-island", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/niko-island")
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: executable.path)
        XCTAssertEqual(runProcess("/usr/bin/codesign", ["--force", "--sign", "-", app.path]).status, 0)
        let zip = scratch.file("build/Niko-Island-\(version)-\(ReleaseInfo.architectureLabel).zip")
        XCTAssertEqual(runProcess("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]).status, 0)
        try FileManager.default.removeItem(at: app)
        return zip
    }

    private func updater(zip: URL, listing: String, downloads: Stored<[String]> = Stored([])) -> Updater {
        Updater(transport: { request in
            downloads.value.append(request.url?.lastPathComponent ?? "")
            return (Data(listing.utf8), 200)
        }, download: { request, destination in
            downloads.value.append(request.url?.lastPathComponent ?? "")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: zip, to: destination)
            return 200
        })
    }

    private func info(_ version: String, zip: URL) -> ReleaseInfo {
        let base = "https://github.com/baogutang/niko-island/releases/download/v\(version)/"
        return ReleaseInfo(version: version, page: URL(string: "https://github.com/baogutang/niko-island/releases")!,
                           assets: [zip.lastPathComponent: URL(string: base + zip.lastPathComponent)!,
                                    "SHA256SUMS": URL(string: base + "SHA256SUMS")!])
    }

    func testAPackageIsUsedOnlyWhenItsChecksumAndBundleAgree() async throws {
        let scratch = Scratch()
        let zip = try package(in: scratch, version: "9.1.0")
        let digest = try XCTUnwrap(UpdateCheck.sha256(of: zip))
        let downloads = Stored<[String]>([])
        let good = updater(zip: zip, listing: "\(digest)  \(zip.lastPathComponent)\n", downloads: downloads)
        let app = try await good.prepare(info("9.1.0", zip: zip), in: scratch.file("work"))
        XCTAssertEqual(app.lastPathComponent, "\(NikoVersion.displayName).app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertEqual(downloads.value, ["SHA256SUMS", zip.lastPathComponent], "the listing first, then the package")

        let tampered = updater(zip: zip, listing: "\(String(repeating: "0", count: 64))  \(zip.lastPathComponent)\n")
        await assertFails(.checksumMismatch) { _ = try await tampered.prepare(self.info("9.1.0", zip: zip), in: scratch.file("work2")) }

        // The release says 9.2.0 but the bundle inside is 9.1.0: not what was offered.
        let renamed = scratch.file("build/Niko-Island-9.2.0-\(ReleaseInfo.architectureLabel).zip")
        try FileManager.default.copyItem(at: zip, to: renamed)
        let mislabelled = updater(zip: renamed, listing: "\(digest)  \(renamed.lastPathComponent)\n")
        await assertFails(.notOurApp) { _ = try await mislabelled.prepare(self.info("9.2.0", zip: renamed), in: scratch.file("work3")) }

        let stranger = try package(in: scratch, version: "9.1.0", identifier: "com.example.other")
        let strangerDigest = try XCTUnwrap(UpdateCheck.sha256(of: stranger))
        let other = updater(zip: stranger, listing: "\(strangerDigest)  \(stranger.lastPathComponent)\n")
        await assertFails(.notOurApp) { _ = try await other.prepare(self.info("9.1.0", zip: stranger), in: scratch.file("work4")) }

        let empty = ReleaseInfo(version: "9.1.0", page: URL(string: "https://github.com")!, assets: [:])
        await assertFails(.noPackage) { _ = try await good.prepare(empty, in: scratch.file("work5")) }
    }

    func testReplacingKeepsTheOldAppUntilTheNewOneIsInPlace() throws {
        let scratch = Scratch()
        let current = scratch.file("Applications/Niko Island.app")
        let fresh = scratch.file("work/Niko Island.app")
        for app in [current, fresh] {
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        }
        scratch.write("Applications/Niko Island.app/Contents/Info.plist", "old")
        scratch.write("work/Niko Island.app/Contents/Info.plist", "new")
        let bin = scratch.file("Trash")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let trash: (URL) throws -> URL? = { url in
            let target = bin.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        try Updater.replace(current, with: fresh, trash: trash)
        XCTAssertEqual(scratch.read("Applications/Niko Island.app/Contents/Info.plist"), "new")
        XCTAssertEqual(scratch.read("Trash/Niko Island.app/Contents/Info.plist"), "old", "the old app is in the Trash, not gone")

        // The new one cannot move in: the old one comes back from the Trash.
        try FileManager.default.removeItem(at: bin.appendingPathComponent("Niko Island.app"))
        let missing = scratch.file("work/Gone.app")
        try FileManager.default.createDirectory(at: missing.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        scratch.write("work/Gone.app/Contents/Info.plist", "x")
        XCTAssertThrowsError(try Updater.replace(current, with: missing, trash: { url in
            _ = try trash(url)
            try FileManager.default.removeItem(at: missing)   // gone before it could be moved
            return bin.appendingPathComponent(url.lastPathComponent)
        }))
        XCTAssertEqual(scratch.read("Applications/Niko Island.app/Contents/Info.plist"), "new", "put back where it was")

        XCTAssertThrowsError(try Updater.replace(scratch.file("Applications/Nothing.app"), with: fresh, trash: trash))
        XCTAssertThrowsError(try Updater.replace(scratch.file("notes.txt"), with: fresh, trash: trash))
    }

    private func assertFails(_ expected: Updater.Failure, _ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? Updater.Failure, expected, line: line)
        }
    }
}

final class Stored<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
