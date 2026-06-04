import AppKit
import CoreGraphics
import CoreImage
import Dependencies
import Foundation
import HexCore
import ScreenCaptureKit

private let screenshotLogger = HexLog.transcription

// MARK: - Client Interface

struct ScreenshotClient: Sendable {
	/// Capture a JPEG of the currently frontmost window (excluding Hex's own windows).
	/// - Parameters:
	///   - maxDimension: Upper bound for the larger side of the output image in pixels.
	///     Used when `scaleFactor` is nil (cloud providers).
	///   - scaleFactor: When non-nil (local providers), the native window image is scaled
	///     by this factor (0–1) instead of capped at `maxDimension`. 1.0 = full resolution.
	///   - sharpen: Apply a light unsharp mask after downscaling to keep text legible.
	/// - Returns: JPEG `Data`, or `nil` if no suitable window is found or capture fails.
	var captureFrontmostWindow: @Sendable (_ maxDimension: Int, _ scaleFactor: Double?, _ sharpen: Bool) async -> Data?

	/// Check whether Screen Recording permission has been granted.
	var hasPermission: @Sendable () -> Bool

	/// Trigger the system Screen Recording permission prompt.
	var requestPermission: @Sendable () -> Void

	/// Debug helper: persist the exact JPEG that was sent to the model. Returns the file URL.
	var saveDebugScreenshot: @Sendable (_ jpeg: Data) -> URL?

	init(
		captureFrontmostWindow: @escaping @Sendable (Int, Double?, Bool) async -> Data? = { _, _, _ in nil },
		hasPermission: @escaping @Sendable () -> Bool = { false },
		requestPermission: @escaping @Sendable () -> Void = {},
		saveDebugScreenshot: @escaping @Sendable (Data) -> URL? = { _ in nil }
	) {
		self.captureFrontmostWindow = captureFrontmostWindow
		self.hasPermission = hasPermission
		self.requestPermission = requestPermission
		self.saveDebugScreenshot = saveDebugScreenshot
	}

	/// Location of the last debug screenshot (used by the "Show in Finder" button).
	static var debugScreenshotURL: URL? {
		guard let base = try? FileManager.default.url(
			for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
		) else { return nil }
		return base.appendingPathComponent("DebugScreenshots/last-sent.jpg")
	}
}

extension ScreenshotClient: DependencyKey {
	static var liveValue: Self {
		Self(
			captureFrontmostWindow: { maxDimension, scaleFactor, sharpen in
				await ScreenshotClientLive.captureFrontmostWindow(maxDimension: CGFloat(maxDimension), scaleFactor: scaleFactor.map { CGFloat($0) }, sharpen: sharpen)
			},
			hasPermission: { CGPreflightScreenCaptureAccess() },
			requestPermission: { _ = CGRequestScreenCaptureAccess() },
			saveDebugScreenshot: { jpeg in ScreenshotClientLive.saveDebug(jpeg) }
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

	static func captureFrontmostWindow(maxDimension: CGFloat, scaleFactor: CGFloat? = nil, sharpen: Bool = false) async -> Data? {
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

			// Capture at the window's native pixel resolution. ScreenCaptureKit ignores
			// reduced SCStreamConfiguration sizes for desktop-independent window filters
			// (it returns the native size regardless), so we downscale the result ourselves.
			let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
			config.width = Int(window.frame.width * scale)
			config.height = Int(window.frame.height * scale)
			config.showsCursor = false
			config.capturesAudio = false

			let cgImage = try await SCScreenshotManager.captureImage(
				contentFilter: filter,
				configuration: config
			)

			// Local providers scale by a multiplier of native; cloud providers cap the
			// longest side at maxDimension.
			let cap: CGFloat
			if let scaleFactor {
				let clamped = min(max(scaleFactor, 0.05), 1.0)
				cap = CGFloat(max(cgImage.width, cgImage.height)) * clamped
			} else {
				cap = maxDimension
			}
			var resized = downscale(cgImage, maxDimension: cap)
			// Optional unsharp mask to keep text legible after downscaling.
			if sharpen, resized.width < cgImage.width {
				resized = sharpened(resized)
			}

			guard let jpeg = jpegData(from: resized, quality: jpegQuality) else {
				screenshotLogger.error("Screenshot: JPEG encoding failed")
				return nil
			}

			screenshotLogger.info("Screenshot captured: native \(cgImage.width)x\(cgImage.height) -> sent \(resized.width)x\(resized.height), \(jpeg.count) bytes")
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

	/// Write the sent JPEG to the app container for debugging. Overwrites the previous one.
	static func saveDebug(_ jpeg: Data) -> URL? {
		guard let url = ScreenshotClient.debugScreenshotURL else { return nil }
		do {
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try jpeg.write(to: url, options: .atomic)
			return url
		} catch {
			screenshotLogger.error("Debug screenshot save failed: \(error.localizedDescription)")
			return nil
		}
	}

	/// Downscale a CGImage so its longest side is at most `maxDimension`, preserving
	/// aspect ratio. Returns the original image when it already fits (or on failure).
	/// Pure function — covered by ScreenshotResizeTests.
	static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
		let width = CGFloat(image.width)
		let height = CGFloat(image.height)
		let largest = max(width, height)
		guard maxDimension > 0, largest > maxDimension else { return image }

		let factor = maxDimension / largest
		let newWidth = max(1, Int((width * factor).rounded()))
		let newHeight = max(1, Int((height * factor).rounded()))

		// Force sRGB + premultiplied RGBA so the context is valid regardless of the
		// source image's color space (which may be grayscale, P3, etc.).
		let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(
			data: nil,
			width: newWidth,
			height: newHeight,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			return image
		}
		context.interpolationQuality = .high
		context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
		return context.makeImage() ?? image
	}

	/// Apply a light unsharp mask so text edges survive downscaling. Returns the original
	/// image on failure.
	static func sharpened(_ image: CGImage) -> CGImage {
		let input = CIImage(cgImage: image)
		guard let filter = CIFilter(name: "CIUnsharpMask", parameters: [
			kCIInputImageKey: input,
			kCIInputRadiusKey: 1.6,
			kCIInputIntensityKey: 0.8
		]), let output = filter.outputImage else { return image }
		let context = CIContext(options: nil)
		guard let result = context.createCGImage(output, from: input.extent) else { return image }
		return result
	}
}
