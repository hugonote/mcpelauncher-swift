import Darwin

public enum ProcessGroupIsolation {
    public static func isolateCurrentProcess() -> Bool {
        let processID = getpid()
        if getpgrp() == processID {
            return true
        }

        guard setpgid(0, 0) == 0 else {
            return false
        }
        return getpgrp() == processID
    }
}
