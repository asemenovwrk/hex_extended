import Foundation

#if canImport(MLXASR)
import MLXASR

/// On-device Qwen3-ASR transcription via MLX (`mlx-swift-asr`).
///
/// Mirrors the role of `ParakeetClient`: downloads model weights on demand,
/// loads them into memory (with Metal warmup), and transcribes audio fully
/// in-process. The MLX dependency is isolated to HexCore; the app talks to this
/// actor through a Foundation-only API.
public actor QwenClient {
	private var stt: Qwen3ASRSTT?
	private var currentVariant: QwenModel?
	private let logger = HexLog.qwen
	private let session: URLSession = {
		let cfg = URLSessionConfiguration.default
		cfg.timeoutIntervalForResource = 3600
		return URLSession(configuration: cfg)
	}()

	public init() {}

	// MARK: - Availability

	/// A model is available when its directory holds the weights, the injected
	/// tokenizer, and the config (the three things `Qwen3ASRSTT.load` needs).
	public func isModelAvailable(_ modelName: String) -> Bool {
		guard let variant = QwenModel(rawValue: modelName) else { return false }
		if currentVariant == variant, stt != nil { return true }
		guard let dir = try? modelDirectory(for: variant) else { return false }
		let fm = FileManager.default
		let required = [QwenModel.weightFileName, QwenModel.tokenizerFileName, "config.json"]
		return required.allSatisfy { name in
			let path = dir.appendingPathComponent(name).path
			guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int else { return false }
			return size > 0
		}
	}

	// MARK: - Download + load

	/// Ensures `modelName` is downloaded and loaded (with warmup), reporting an
	/// overall 0...1 fraction. Download spans 0.0–0.9, load+warmup 0.9–1.0.
	public func ensureLoaded(modelName: String, progress: @escaping (Double) -> Void) async throws {
		guard let variant = QwenModel(rawValue: modelName) else {
			throw QwenError.unknownVariant(modelName)
		}
		if currentVariant == variant, stt != nil { return }
		// Switching variants: drop the old model first to free GPU memory.
		if currentVariant != variant { unload() }

		let dir = try modelDirectory(for: variant)
		if !isModelAvailable(modelName) {
			try await download(variant: variant, into: dir) { frac in
				progress(frac * 0.9)
			}
		} else {
			progress(0.9)
		}

		logger.notice("Loading Qwen3-ASR \(variant.identifier, privacy: .public)")
		let t0 = Date()
		let model = try await Qwen3ASRSTT.loadWithWarmup(from: dir)
		self.stt = model
		self.currentVariant = variant
		progress(1.0)
		logger.notice("Qwen3-ASR loaded+warmed in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
	}

	// MARK: - Transcription

	/// Transcribes audio at `url`. `context` biases recognition toward the given
	/// terminology (fed from the active TranscriptionPrompt); `language` is an
	/// optional hint (nil = auto-detect).
	public func transcribe(_ url: URL, language: String?, context: String?) async throws -> String {
		guard let stt else { throw QwenError.notLoaded }
		let t0 = Date()
		logger.notice("Transcribing with Qwen3-ASR file=\(url.lastPathComponent, privacy: .public)")
		let result = try await stt.transcribe(
			file: url,
			language: language,
			context: (context?.isEmpty == false) ? context : nil
		)
		logger.info("Qwen3-ASR transcription finished in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s (rtf=\(String(format: "%.3f", result.rtf)))")
		return result.text
	}

	// MARK: - Unload / delete

	/// Drops the in-memory model and returns freed Metal buffers to the OS.
	/// Called when switching to another engine so a large model (the High tier is
	/// ~3.8GB) doesn't stay resident for the rest of the session.
	public func unload() {
		guard stt != nil || currentVariant != nil else { return }
		stt = nil
		currentVariant = nil
		Qwen3ASRSTT.flushMemoryPool()
		logger.notice("Qwen3-ASR unloaded")
	}

	public func deleteModel(_ modelName: String) throws {
		guard let variant = QwenModel(rawValue: modelName) else { return }
		let fm = FileManager.default
		let dir = try modelDirectory(for: variant)
		// Remove both the final dir and any leftover partial-download sibling.
		for target in [dir, dir.appendingPathExtension("partial")] where fm.fileExists(atPath: target.path) {
			try fm.removeItem(at: target)
		}
		if currentVariant == variant { unload() }
	}

	// MARK: - Private

	private func modelDirectory(for variant: QwenModel) throws -> URL {
		try URL.hexQwenModelsDirectory.appendingPathComponent(variant.identifier, isDirectory: true)
	}

	/// Downloads all model files into a temporary dir, injects the bundled
	/// tokenizer.json, then atomically moves it into `dir`.
	private func download(variant: QwenModel, into dir: URL, progress: @escaping (Double) -> Void) async throws {
		let fm = FileManager.default
		// Clean any partial leftover.
		if fm.fileExists(atPath: dir.path) { try? fm.removeItem(at: dir) }
		let tmp = dir.appendingPathExtension("partial")
		if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
		try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

		do {
			let base = "https://huggingface.co/\(variant.huggingFaceRepo)/resolve/main"

			// 1) Required metadata (fatal on error).
			for name in QwenModel.requiredMetadataFileNames {
				guard let url = URL(string: "\(base)/\(name)") else { throw QwenError.invalidURL("\(base)/\(name)") }
				let (data, response) = try await session.data(from: url)
				try validate(response, file: name)
				try data.write(to: tmp.appendingPathComponent(name))
			}
			// 2) Optional metadata (best-effort: skip on any non-2xx / failure).
			for name in QwenModel.optionalMetadataFileNames {
				guard let url = URL(string: "\(base)/\(name)") else { continue }
				if let (data, response) = try? await session.data(from: url),
				   let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) {
					try? data.write(to: tmp.appendingPathComponent(name))
				}
			}
			progress(0.05)

			// 3) Inject the bundled tokenizer.json (identical across all Qwen3-ASR sizes).
			try injectBundledTokenizer(into: tmp)

			// 4) Weights — chunked download with progress + integrity check (0.05 → 1.0).
			guard let weightURL = URL(string: "\(base)/\(QwenModel.weightFileName)") else {
				throw QwenError.invalidURL("\(base)/\(QwenModel.weightFileName)")
			}
			try await downloadWeights(
				from: weightURL,
				to: tmp.appendingPathComponent(QwenModel.weightFileName),
				fallbackTotal: variant.approximateWeightBytes
			) { frac in
				progress(0.05 + frac * 0.95)
			}

			// 5) Move into final location.
			try fm.moveItem(at: tmp, to: dir)
			progress(1.0)
			logger.notice("Downloaded Qwen3-ASR \(variant.identifier, privacy: .public) to \(dir.path, privacy: .public)")
		} catch {
			try? fm.removeItem(at: tmp)
			logger.error("Qwen3-ASR download failed for \(variant.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
			throw error
		}
	}

	/// Downloads a (potentially multi-GB) file via a chunked `URLSessionDownloadTask`,
	/// reporting fraction and rejecting truncated / HTTP-error results.
	private func downloadWeights(
		from url: URL,
		to destination: URL,
		fallbackTotal: Int64,
		progress: @escaping (Double) -> Void
	) async throws {
		// The delegate runs off-actor; it pushes fractions through a Sendable
		// AsyncStream which we consume here (on the actor), so the non-Sendable
		// `progress` closure is only ever called in this actor's isolation.
		let (stream, continuation) = AsyncStream<Double>.makeStream()
		let downloader = WeightDownloader(destination: destination, fallbackTotal: fallbackTotal) { frac in
			continuation.yield(frac)
		}
		let runTask = Task { () throws -> Int64 in
			defer { continuation.finish() }
			return try await downloader.run(url: url)
		}
		for await frac in stream { progress(frac) }
		_ = try await runTask.value
		progress(1.0)
	}

	private func injectBundledTokenizer(into dir: URL) throws {
		guard let src = Bundle.module.url(forResource: "qwen3-asr-tokenizer", withExtension: "json") else {
			throw QwenError.missingBundledTokenizer
		}
		try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(QwenModel.tokenizerFileName))
	}

	private func validate(_ response: URLResponse, file: String) throws {
		guard let http = response as? HTTPURLResponse else {
			throw QwenError.httpError(file: file, status: -1)
		}
		guard (200 ..< 300).contains(http.statusCode) else {
			throw QwenError.httpError(file: file, status: http.statusCode)
		}
	}
}

/// URLSession download delegate that streams to a file with chunked I/O, exposes
/// thread-safe progress, validates the HTTP status, and moves the result into
/// place. `@unchecked Sendable`: all mutable state is guarded by `lock`.
private final class WeightDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
	private let lock = NSLock()
	private var _expectedTotal: Int64 = 0
	private var continuation: CheckedContinuation<Int64, Error>?
	private var finished = false
	private let destination: URL
	private let fallbackTotal: Int64
	private let onProgress: @Sendable (Double) -> Void

	init(destination: URL, fallbackTotal: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
		self.destination = destination
		self.fallbackTotal = fallbackTotal
		self.onProgress = onProgress
	}

	func run(url: URL) async throws -> Int64 {
		let cfg = URLSessionConfiguration.default
		cfg.timeoutIntervalForResource = 3600
		let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
		defer { session.finishTasksAndInvalidate() }
		return try await withCheckedThrowingContinuation { cont in
			lock.lock(); continuation = cont; lock.unlock()
			session.downloadTask(with: url).resume()
		}
	}

	private func finish(_ result: Result<Int64, Error>) {
		lock.lock()
		guard !finished, let cont = continuation else { lock.unlock(); return }
		finished = true
		continuation = nil
		lock.unlock()
		cont.resume(with: result)
	}

	func urlSession(
		_ session: URLSession,
		downloadTask: URLSessionDownloadTask,
		didWriteData bytesWritten: Int64,
		totalBytesWritten: Int64,
		totalBytesExpectedToWrite: Int64
	) {
		lock.lock()
		if totalBytesExpectedToWrite > 0 { _expectedTotal = totalBytesExpectedToWrite }
		let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : fallbackTotal
		lock.unlock()
		let frac = total > 0 ? min(1.0, Double(totalBytesWritten) / Double(total)) : 0
		onProgress(frac)
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		// A 404/error still "finishes downloading" (an error body) — reject by status.
		if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
			finish(.failure(QwenError.httpError(file: destination.lastPathComponent, status: http.statusCode)))
			return
		}
		// `location` is removed once this returns, so move it synchronously now.
		let fm = FileManager.default
		do {
			try? fm.removeItem(at: destination)
			try fm.moveItem(at: location, to: destination)
			let size = Int64((try? fm.attributesOfItem(atPath: destination.path))?[.size] as? Int ?? 0)
			lock.lock(); let expected = _expectedTotal; lock.unlock()
			if expected > 0, size < expected {
				finish(.failure(QwenError.incompleteDownload(file: destination.lastPathComponent, got: size, expected: expected)))
			} else {
				finish(.success(size))
			}
		} catch {
			finish(.failure(error))
		}
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		// Success is resumed in didFinishDownloadingTo; this catches transport errors
		// (e.g. a dropped connection mid-download → truncation).
		if let error { finish(.failure(error)) }
	}
}

public enum QwenError: LocalizedError {
	case unknownVariant(String)
	case notLoaded
	case invalidURL(String)
	case httpError(file: String, status: Int)
	case incompleteDownload(file: String, got: Int64, expected: Int64)
	case missingBundledTokenizer

	public var errorDescription: String? {
		switch self {
		case .unknownVariant(let name): "Unknown Qwen3-ASR model: \(name)"
		case .notLoaded: "Qwen3-ASR model is not loaded."
		case .invalidURL(let s): "Invalid download URL: \(s)"
		case .httpError(let file, let status): "Failed to download \(file) (HTTP \(status))."
		case .incompleteDownload(let file, let got, let expected): "Incomplete download of \(file): got \(got) of \(expected) bytes."
		case .missingBundledTokenizer: "Bundled Qwen3-ASR tokenizer.json is missing from the app."
		}
	}
}

#else

/// Stub used when the MLX engine is not linked (mirrors ParakeetClient's stub).
public actor QwenClient {
	public init() {}
	public func isModelAvailable(_ modelName: String) -> Bool { false }
	public func ensureLoaded(modelName: String, progress: @escaping (Double) -> Void) async throws {
		throw NSError(domain: "Qwen", code: -2, userInfo: [NSLocalizedDescriptionKey: "Qwen3-ASR (MLX) support not linked."])
	}
	public func transcribe(_ url: URL, language: String?, context: String?) async throws -> String {
		throw NSError(domain: "Qwen", code: -3, userInfo: [NSLocalizedDescriptionKey: "Qwen3-ASR not available"])
	}
	public func unload() {}
	public func deleteModel(_ modelName: String) throws {}
}

#endif
