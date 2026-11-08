import Darwin
import Foundation
import OSLog

struct SubsystemPowerMetrics: Sendable {
    let cpuWatts: Double?
    let gpuWatts: Double?
    let aneWatts: Double?
    let unavailableReason: String?
}

final class PowermetricsSubsystemPowerProvider: @unchecked Sendable {
    static let shared = PowermetricsSubsystemPowerProvider()
    static let autoAttemptDefaultsKey = "powermetrics.autoAttempt"

    private struct PrivilegedSession {
        let id: UUID
        let outputURL: URL
        let process: Process
        let startDate: Date
    }

    private let logger = Logger(subsystem: AppConstants.subsystem, category: "powermetrics")
    private let queue = DispatchQueue(label: "com.codex.MacoPowerMonitor.powermetrics")
    private let readerQueue = DispatchQueue(label: "com.codex.MacoPowerMonitor.powermetrics.reader", qos: .utility)
    private let interactiveLaunchLock = NSLock()
    private var cachedMetrics = SubsystemPowerMetrics(cpuWatts: nil, gpuWatts: nil, aneWatts: nil, unavailableReason: nil)
    private var lastSampleDate: Date?
    private var lastAutomaticRefreshDate: Date?
    private var isAutomaticRefreshInFlight = false
    private var privilegedSession: PrivilegedSession?
    private let automaticRefreshInterval: TimeInterval = 120
    private let privilegedSampleStaleInterval: TimeInterval = 15

    func currentMetrics() -> SubsystemPowerMetrics {
        queue.sync {
            let now = Date()
            if privilegedSession != nil {
                if let lastSampleDate,
                   now.timeIntervalSince(lastSampleDate) <= privilegedSampleStaleInterval {
                    return cachedMetrics
                }
                let reason = lastSampleDate == nil
                    ? "管理员持续采样正在启动"
                    : "管理员持续采样暂未返回新数据"
                return unavailableMetrics(reason: reason)
            }

            guard UserDefaults.standard.bool(forKey: Self.autoAttemptDefaultsKey) else {
                return unavailableMetrics(reason: "在设置中启动管理员持续采样")
            }

            if let lastSampleDate,
               now.timeIntervalSince(lastSampleDate) <= automaticRefreshInterval * 2 {
                return cachedMetrics
            }

            return unavailableMetrics(reason: isAutomaticRefreshInFlight
                ? "分项功耗后台采样正在进行"
                : "分项功耗需要管理员权限（powermetrics）")
        }
    }

    func prewarmAutomaticMetricsIfNeeded() {
        let now = Date()
        let shouldRefresh = queue.sync { () -> Bool in
            guard privilegedSession == nil,
                  UserDefaults.standard.bool(forKey: Self.autoAttemptDefaultsKey),
                  !isAutomaticRefreshInFlight,
                  lastAutomaticRefreshDate.map({ now.timeIntervalSince($0) >= automaticRefreshInterval }) ?? true else {
                return false
            }
            isAutomaticRefreshInFlight = true
            lastAutomaticRefreshDate = now
            return true
        }
        guard shouldRefresh else { return }

        readerQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.fetchMetrics() }
            self.queue.sync {
                self.isAutomaticRefreshInFlight = false
                switch result {
                case let .success(metrics):
                    self.cachedMetrics = metrics
                    self.lastSampleDate = Date()
                case let .failure(error):
                    self.logger.error("powermetrics probe failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func refreshInteractively() throws -> SubsystemPowerMetrics {
        interactiveLaunchLock.lock()
        defer { interactiveLaunchLock.unlock() }

        let existingSession = queue.sync {
            privilegedSession.map { _ in
                (sampleDate: lastSampleDate, metrics: cachedMetrics)
            }
        }
        if let existingSession {
            if let sampleDate = existingSession.sampleDate,
               Date().timeIntervalSince(sampleDate) <= privilegedSampleStaleInterval {
                return existingSession.metrics
            }
            throw NSError(
                domain: "PowermetricsSubsystemPowerProvider",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "管理员持续采样仍在运行，但暂未返回新数据"]
            )
        }

        let sessionID = UUID()
        let launch = try launchPrivilegedSampler()
        let session = PrivilegedSession(
            id: sessionID,
            outputURL: launch.outputURL,
            process: launch.process,
            startDate: Date()
        )
        queue.sync {
            privilegedSession = session
            lastSampleDate = nil
        }
        readerQueue.async { [weak self] in
            self?.pollPrivilegedSamples(session)
        }

        // The authorization prompt itself lives inside this process, so the
        // user may need a while to type their password before the first sample.
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if !launch.process.isRunning {
                queue.sync {
                    guard privilegedSession?.id == sessionID else { return }
                    privilegedSession = nil
                    lastSampleDate = nil
                }
                throw launch.earlyExitError()
            }
            if let metrics = queue.sync(execute: { () -> SubsystemPowerMetrics? in
                guard privilegedSession?.id == sessionID, lastSampleDate != nil else { return nil }
                return cachedMetrics
            }) {
                return metrics
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw NSError(
            domain: "PowermetricsSubsystemPowerProvider",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "管理员持续采样已启动，但首个样本尚未返回"]
        )
    }

    private func launchPrivilegedSampler() throws -> (process: Process, outputURL: URL, earlyExitError: () -> NSError) {
        let appProcessID = ProcessInfo.processInfo.processIdentifier
        let outputPath = "/var/run/maco-power-monitor.metrics.plist"
        // The osascript process must stay alive for the whole session: macOS
        // tears down the privileged shell session (SIGKILL to the group) when a
        // completed `do shell script ... with administrator privileges` returns,
        // which used to kill the nohup'd sampler instantly.
        let samplerScript = """
        output_file=\(outputPath)
        next_file="$output_file.next"
        /bin/rm -rf /var/run/maco-power-monitor.* "$output_file" "$next_file"
        while /bin/kill -0 \(appProcessID) 2>/dev/null; do
            if /usr/bin/powermetrics --samplers cpu_power,gpu_power,ane_power -n 1 -f plist -o "$next_file"; then
                /bin/chmod 644 "$next_file"
                /bin/mv -f "$next_file" "$output_file"
            else
                /bin/rm -f "$next_file"
                break
            fi
        done
        /bin/rm -f "$output_file" "$next_file"
        """
        let encodedCommand = Data(samplerScript.utf8).base64EncodedString()
        let appleScript = """
        do shell script "/bin/echo '\(encodedCommand)' | /usr/bin/base64 -D | /bin/sh" with administrator privileges
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = Pipe()
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let earlyExitError = {
            let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let message = stderr.contains("User canceled")
                ? "已取消管理员授权"
                : "管理员持续采样进程已退出：\(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            return NSError(
                domain: "PowermetricsSubsystemPowerProvider",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return (process, URL(fileURLWithPath: outputPath), earlyExitError)
    }

    private func pollPrivilegedSamples(_ session: PrivilegedSession) {
        var lastModificationDate: Date?

        while isCurrentSession(session.id), session.process.isRunning {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: session.outputURL.path)
                let modificationDate = attributes[.modificationDate] as? Date
                // Ignore leftovers from earlier runs; this session's script
                // deletes the fixed output file before sampling begins.
                if let modificationDate,
                   modificationDate >= session.startDate,
                   modificationDate != lastModificationDate {
                    let data = try Data(contentsOf: session.outputURL)
                    guard let sample = data.split(separator: 0).last, !sample.isEmpty else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let metrics = try parseMetrics(from: Data(sample))
                    queue.sync {
                        guard privilegedSession?.id == session.id else { return }
                        cachedMetrics = metrics
                        lastSampleDate = Date()
                    }
                    lastModificationDate = modificationDate
                }
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                // The first atomic snapshot does not exist until powermetrics completes a sample.
            } catch {
                logger.error("Failed to read privileged powermetrics sample: \(error.localizedDescription, privacy: .public)")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        queue.sync {
            guard privilegedSession?.id == session.id else { return }
            privilegedSession = nil
            lastSampleDate = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        queue.sync { privilegedSession?.id == sessionID }
    }

    private func fetchMetrics() throws -> SubsystemPowerMetrics {
        let data = try CommandRunner.run(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/powermetrics", "--samplers", "cpu_power,gpu_power,ane_power", "-n", "1", "-f", "plist"],
            timeout: 15
        )
        guard let first = data.split(separator: 0).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try parseMetrics(from: Data(first))
    }

    private func parseMetrics(from data: Data) throws -> SubsystemPowerMetrics {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return SubsystemPowerMetrics(
            cpuWatts: extractWatts(from: plist, matching: ["cpu"]),
            gpuWatts: extractWatts(from: plist, matching: ["gpu"]),
            aneWatts: extractWatts(from: plist, matching: ["ane"]),
            unavailableReason: nil
        )
    }

    func extractWatts(from object: Any, matching keywords: [String]) -> Double? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let loweredKey = key.lowercased()
                // Exclude "Combined Power (CPU+GPU+ANE)" so CPU/GPU/ANE never match the aggregate key.
                if keywords.allSatisfy(loweredKey.contains), loweredKey.contains("power"),
                   !loweredKey.contains("combined") {
                    // powermetrics plist reports subsystem power in milliwatts; convert to watts.
                    if let number = value as? Double { return number / 1000 }
                    if let number = value as? Int { return Double(number) / 1000 }
                }
                if let nested = extractWatts(from: value, matching: keywords) { return nested }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let nested = extractWatts(from: value, matching: keywords) { return nested }
            }
        }
        return nil
    }

    private func unavailableMetrics(reason: String) -> SubsystemPowerMetrics {
        SubsystemPowerMetrics(cpuWatts: nil, gpuWatts: nil, aneWatts: nil, unavailableReason: reason)
    }
}
