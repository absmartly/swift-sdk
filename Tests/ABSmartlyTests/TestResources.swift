import Foundation

enum TestResources {
    #if canImport(FoundationNetworking)
    private static let resourcesDir: String = {
        let thisFile = #filePath
        let testsDir = (thisFile as NSString).deletingLastPathComponent
        return testsDir + "/Resources"
    }()

    static func path(forResource name: String, ofType ext: String, subdirectory: String? = nil) -> String {
        return resourcesDir + "/" + (subdirectory.map { $0 + "/" } ?? "") + name + "." + ext
    }
    #else
    static func path(forResource name: String, ofType ext: String, subdirectory: String? = nil) -> String {
        let directory = "Resources" + (subdirectory.map { "/" + $0 } ?? "")
        return Bundle.module.path(forResource: name, ofType: ext, inDirectory: directory)!
    }
    #endif
}
