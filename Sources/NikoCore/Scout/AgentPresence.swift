import Darwin
import Foundation

/// Which agents are running right now, judged from the process table and the
/// list of open apps. Names only: nothing about a process is read beyond what
/// it is called.
public enum AgentPresence {
    /// Short names (`p_comm`, at most 16 characters) of this user's processes.
    public static func runningProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 16
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &processes, &size, nil, 0) == 0 else { return [] }
        var names: Set<String> = []
        for index in 0..<(size / MemoryLayout<kinfo_proc>.stride) {
            let name = withUnsafeBytes(of: processes[index].kp_proc.p_comm) { raw -> String in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }

    /// Ids of the agents that are running, in registry order.
    /// `apps` are the bundle ids of the open applications.
    public static func running(apps: Set<String>, processes: Set<String>, registry: [AgentDescriptor] = AgentRegistry.all) -> [String] {
        registry.filter { agent in
            guard agent.stability != .planned else { return false }
            if agent.apps.contains(where: apps.contains) { return true }
            // `p_comm` is cut at 16 characters.
            return agent.processes.contains { processes.contains(String($0.prefix(16))) }
        }.map(\.id)
    }
}
