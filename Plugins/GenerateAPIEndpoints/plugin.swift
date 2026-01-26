import Foundation
import PackagePlugin

@main
struct GenerateAPIEndpoints: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "GenerateAPIEndpointsExec")
        // Use path.string for cross-platform compatibility
        let toolUrl = URL(fileURLWithPath: tool.path.string)
        let process = Process()
        process.executableURL = toolUrl
        try process.run()
        process.waitUntilExit()
    }
}
