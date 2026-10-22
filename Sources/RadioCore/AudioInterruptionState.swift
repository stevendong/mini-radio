/// Remembers playback intent across an OS audio interruption without overriding
/// a later pause, stop, route-disconnect, or station selection by the user.
public struct AudioInterruptionState: Sendable {
    private var interrupted = false
    private var resumeRequested = false
    public init() {}

    public mutating func begin(wasPlaying: Bool) {
        // Some audio systems send more than one begin event for an interruption.
        guard !interrupted else { return }
        interrupted = true
        resumeRequested = wasPlaying
    }

    public mutating func userChangedPlayback() { resumeRequested = false }

    public mutating func end(systemAllowsResume: Bool) -> Bool {
        let result = interrupted && resumeRequested && systemAllowsResume
        interrupted = false; resumeRequested = false
        return result
    }
}
