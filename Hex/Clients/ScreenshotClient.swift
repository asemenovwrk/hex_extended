import AppKit
import CoreGraphics
import Dependencies
import Foundation
import HexCore
import ScreenCaptureKit

private let screenshotLogger = HexLog.transcription

// MARK: - Client Interface

struct ScreenshotClient: Sendable {
	/// Capture a JPEG of the currently frontmost window (excluding Hex's own windows).
	/// - Parameter maxDimension: Upper bound for the larger side of the output image in pixels.
	///   Smaller values reduce token cost for vision models at the expense of fidelity.
	/// - Returns: JPEG `Data`, or `nil` if no suitable window is found or capture fails.
	var captureFrontmostWindow: @Sendable (_ maxDimension: Int) async -> Data?

	/// Check whether Screen Recording permission has been granted.
	var hasPermission: @Sendable () -> Bool

	/// Trigger the system Screen Recording permission prompt.
	var requestPermission: @Sendable () -> Void

	init(
		captureFrontmostWindow: @escaping @Sendable (Int) async -> Data? = { _ in nil },
		hasPermission: @escaping @Sendable () -> Bool = { false },
		requestPermission: @escaping @Sendable () -> Void = {}
	) {
		self.captureFrontmostWindow = captureFrontmostWindow
		self.hasPermission = hasPermission
		self.requestPermission = requestPermission
	}
}

extension ScreenshotClient: DependencyKey {
	static var liveValue: Self {
		Self(
			captureFrontmostWindow: { maxDimension in
				await ScreenshotClientLive.captureFrontmostWindow(maxDimension: CGFloat(maxDimension))
			},
			hasPermission: { CGPreflightScreenCaptureAccess() },
			requestPermission: { _ = CGRequestScreenCaptureAccess() }
		)
	}

	static var testValue: Self {
		Self()
	}
}

extension DependencyValues {
	var screenshot: ScreenshotClient {
		get { self[ScreenshotClient.self] }
		set { self[ScreenshotClient.self] = newValue }
	}
}

// MARK: - Live Implementation

private enum ScreenshotClientLive {
	private static let jpegQuality: CGFloat = 0.85

	static func captureFrontmostWindow(maxDimension: CGFloat) async -> Data? {
		// Find the frontmost non-Hex app.
		guard let frontApp = await MainActor.run(body: { frontmostOtherApp() }) else {
			screenshotLogger.notice("Screenshot: no frontmost app found")
			return nil
		}
		let pid = frontApp.processIdentifier

		do {
			let content = try await SCShareableContent.excludingDesktopWindows(
				false,
				onScreenWindowsOnly: true
			)

			// Pick the topmost on-screen window owned by the target PID, ignoring tiny menus/tooltips.
			guard let window = content.windows.first(where: { window in
				guard window.owningApplication?.processID == pid else { return false }
				guard window.isOnScreen else { return false }
				// Skip very small windows (menus, tooltips, accessory popups).
				let frame = window.frame
				return frame.width >= 200 && frame.height >= 200
			}) else {
				screenshotLogger.notice("Screenshot: no suitable window for PID \(pid)")
				return nil
			}

			let filter = SCContentFilter(desktopIndependentWindow: window)
			let config = SCStreamConfiguration()

			// Use native resolution of the window for best text quality, capped at maxDimension.
			let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
			let rawWidth = window.frame.width * scale
			let rawHeight = window.frame.height * scale
			let largest = max(rawWidth, rawHeight)
			let downscale = largest > maxDimension ? (maxDimension / largest) : 1.0
			config.width = Int(rawWidth * downscale)
			config.height = Int(rawHeight * downscale)
			config.showsCursor = false
			config.capturesAudio = false

			let cgImage = try await SCScreenshotManager.captureImage(
				contentFilter: filter,
				configuration: config
			)

			guard let jpeg = jpegData(from: cgImage, quality: jpegQuality) else {
				screenshotLogger.error("Screenshot: JPEG encoding failed")
				return nil
			}

			screenshotLogger.info("Screenshot captured: \(cgImage.width)x\(cgImage.height), \(jpeg.count) bytes")
			return jpeg
		} catch {
			screenshotLogger.error("Screenshot capture failed: \(error.localizedDescription)")
			return nil
		}
	}

	@MainActor
	private static func frontmostOtherApp() -> NSRunningApplication? {
		let ourBundleID = Bundle.main.bundleIdentifier
		if let front = NSWorkspace.shared.frontmostApplication,
		   front.bundleIdentifier != ourBundleID {
			return front
		}
		// If Hex itself is frontmost (unlikely for menu-bar mode, but possible),
		// fall back to the most recently active non-Hex app.
		return NSWorkspace.shared.runningApplications.first { app in
			app.activationPolicy == .regular
				&& app.bundleIdentifier != ourBundleID
				&& !app.isTerminated
		}
	}

	private static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
		let bitmap = NSBitmapImageRep(cgImage: cgImage)
		return bitmap.representation(
			using: .jpeg,
			properties: [.compressionFactor: quality]
		)
	}
}
