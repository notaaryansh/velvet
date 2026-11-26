//
//  retry.swift
//
//  Created by Quirin Schweigert on 30.05.23.
//

import Foundation
import Logging

public func retry<T>(delay: DispatchTimeInterval, _ action: () async throws -> T) async rethrows -> T {
    do {
        return try await action()
    } catch {
        print("Error: \(error). Retrying...")
        try await Task.sleep(timeInterval: delay)
        return try await action()
    }
}

public func retry<T>(delay: ContinuousClock.Duration? = nil, _ action: () async throws -> T) async rethrows -> T {
    do {
        return try await action()
    } catch {
        print("Error: \(error). Retrying...")
        if let delay { try await Task.sleep(for: delay) }
        return try await action()
    }
}

public enum RetryError: Error { case maxTriesExceeded(errors: [Error]), retryCancelled(cause: Error?) }

public protocol RetryDelay: Sendable {
    func delay(forTriesCount: UInt64) -> ContinuousClock.Duration
}

public func retry<T>(
    minDelay: RetryDelay? = .none,
    maxTries: Int? = nil,
    logger: Logger? = nil,
    _ action: () async throws -> T
) async throws -> T {
    var tries: UInt64 = 0
    var lastAttemptTime: ContinuousClock.Instant?
    var errors: [Error] = []

    while !Task.isCancelled {
        tries += 1
        guard maxTries.map({ tries <= $0 }) ?? true else { throw RetryError.maxTriesExceeded(errors: errors) }

        if let minDelay, let lastAttemptTime {
            let now: ContinuousClock.Instant = .now
            let earliestRetryTime = lastAttemptTime.advanced(by: minDelay.delay(forTriesCount: tries))

            if earliestRetryTime > now {
                logger?.error("retry() retrying in \(now.duration(to: earliestRetryTime))")
                try await Task.sleep(until: earliestRetryTime)
            } else {
                logger?.error("retry() retrying without delay")
            }
        }

        lastAttemptTime = .now

        do {
            return try await action()
        } catch {
            if case RetryError.retryCancelled = error {
                throw error
            }

            errors.append(error)
            logger?.error("retry error: \(error), tries: \(tries)")
        }
    }

    logger?.info("retry cancelled")
    throw CancellationError()
}

public struct ExponentialRetryDelay: RetryDelay {
    public var maxDelaySeconds: UInt64 = 300
    public var jitterMillisecondsRange: ClosedRange<Int> = 0...5000

    public func delay(forTriesCount triesCount: UInt64) -> ContinuousClock.Duration {
        .milliseconds(
            min(1 << min(triesCount, 31), maxDelaySeconds) * 1000 +
                UInt64(Int.random(in: jitterMillisecondsRange)) * triesCount
        )
    }
}

public struct ConstantRetryDelay: RetryDelay {
    public var delay: ContinuousClock.Duration

    public func delay(forTriesCount triesCount: UInt64) -> ContinuousClock.Duration {
        delay
    }
}

public extension RetryDelay where Self == ExponentialRetryDelay  {
    static func exponential(maxDelaySeconds: UInt64 = 300, jitterMillisecondsRange: ClosedRange<Int> = 0...5000)
    -> ExponentialRetryDelay {
        ExponentialRetryDelay(maxDelaySeconds: maxDelaySeconds, jitterMillisecondsRange: jitterMillisecondsRange)
    }
}

public extension RetryDelay where Self == ConstantRetryDelay  {
    static func constant(_ delay: ContinuousClock.Duration) -> ConstantRetryDelay {
        .init(delay: delay)
    }
}

// MARK: - Convenience
/// Note: generated through Xcode 26 LLM integration via OpenAI GPT-5
public extension RetryError {
    /// Returns the underlying error if the provided error is a `RetryError.retryCancelled(cause:)`.
    /// If the cause itself is another `RetryError.retryCancelled`, it will be unwrapped recursively.
    /// For all other inputs, the original error is returned unchanged.
    static func unwrapping(_ error: Error) -> Error {
        var current: Error = error

        while case let RetryError.retryCancelled(cause: cause) = current, let cause {
            current = cause
        }

        return current
    }
}
