import Foundation

enum TestResources {
    #if canImport(FoundationNetworking)
    private static let resourcesDir: String = {
        let thisFile = #filePath
        let testsDir = (thisFile as NSString).deletingLastPathComponent
        return testsDir + "/Resources"
    }()

    static func path(forResource name: String, ofType ext: String) -> String {
        return resourcesDir + "/" + name + "." + ext
    }
    #else
    static func path(forResource name: String, ofType ext: String) -> String {
        return Bundle.module.path(forResource: name, ofType: ext, inDirectory: "Resources")!
    }
    #endif
}
