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
		cfg.timeoutIntervalForResource = 3600 // large weights
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
		if currentVariant != variant {
			stt = nil
			currentVariant = nil
		}

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

	// MARK: - Delete

	public func deleteModel(_ modelName: String) throws {
		guard let variant = QwenModel(rawValue: modelName) else { return }
		let dir = try modelDirectory(for: variant)
		if FileManager.default.fileExists(atPath: dir.path) {
			try FileManager.default.removeItem(at: dir)
		}
		if currentVariant == variant {
			stt = nil
			currentVariant = nil
		}
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

			// 1) Small metadata files (best-effort weighting: ~5% of the bar).
			for name in QwenModel.metadataFileNames {
				guard let url = URL(string: "\(base)/\(name)") else { continue }
				let (data, response) = try await session.data(from: url)
				try validate(response, file: name)
				try data.write(to: tmp.appendingPathComponent(name))
			}
			progress(0.05)

			// 2) Inject the bundled tokenizer.json (identical across all Qwen3-ASR sizes).
			try injectBundledTokenizer(into: tmp)

			// 3) Weights — streamed with progress (0.05 → 1.0).
			guard let weightURL = URL(string: "\(base)/\(QwenModel.weightFileName)") else {
				throw QwenError.invalidURL("\(base)/\(QwenModel.weightFileName)")
			}
			try await downloadStreaming(
				from: weightURL,
				to: tmp.appendingPathComponent(QwenModel.weightFileName),
				fallbackTotal: variant.approximateWeightBytes
			) { frac in
				progress(0.05 + frac * 0.95)
			}

			// 4) Move into final location.
			try fm.moveItem(at: tmp, to: dir)
			progress(1.0)
			logger.notice("Downloaded Qwen3-ASR \(variant.identifier, privacy: .public) to \(dir.path, privacy: .public)")
		} catch {
			try? fm.removeItem(at: tmp)
			logger.error("Qwen3-ASR download failed for \(variant.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
			throw error
		}
	}

	/// Streams a download to `destination`, reporting fraction via Content-Length
	/// (falling back to `fallbackTotal` when the server omits it).
	private func downloadStreaming(
		from url: URL,
		to destination: URL,
		fallbackTotal: Int64,
		progress: @escaping (Double) -> Void
	) async throws {
		let (bytes, response) = try await session.bytes(from: url)
		try validate(response, file: destination.lastPathComponent)
		let expected = response.expectedContentLength > 0 ? response.expectedContentLength : fallbackTotal

		FileManager.default.createFile(atPath: destination.path, contents: nil)
		let handle = try FileHandle(forWritingTo: destination)
		defer { try? handle.close() }

		var buffer = Data()
		buffer.reserveCapacity(1 << 20)
		var received: Int64 = 0
		var lastReported = 0.0
		for try await byte in bytes {
			buffer.append(byte)
			if buffer.count >= (1 << 20) {
				try handle.write(contentsOf: buffer)
				received += Int64(buffer.count)
				buffer.removeAll(keepingCapacity: true)
				let frac = expected > 0 ? min(1.0, Double(received) / Double(expected)) : 0.0
				if frac - lastReported >= 0.01 { lastReported = frac; progress(frac) }
			}
		}
		if !buffer.isEmpty {
			try handle.write(contentsOf: buffer)
			received += Int64(buffer.count)
		}
		progress(1.0)
	}

	private func injectBundledTokenizer(into dir: URL) throws {
		guard let src = Bundle.module.url(forResource: "qwen3-asr-tokenizer", withExtension: "json") else {
			throw QwenError.missingBundledTokenizer
		}
		try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(QwenModel.tokenizerFileName))
	}

	private func validate(_ response: URLResponse, file: String) throws {
		guard let http = response as? HTTPURLResponse else { return }
		guard (200 ..< 300).contains(http.statusCode) else {
			throw QwenError.httpError(file: file, status: http.statusCode)
		}
	}
}

public enum QwenError: LocalizedError {
	case unknownVariant(String)
	case notLoaded
	case invalidURL(String)
	case httpError(file: String, status: Int)
	case missingBundledTokenizer

	public var errorDescription: String? {
		switch self {
		case .unknownVariant(let name): "Unknown Qwen3-ASR model: \(name)"
		case .notLoaded: "Qwen3-ASR model is not loaded."
		case .invalidURL(let s): "Invalid download URL: \(s)"
		case .httpError(let file, let status): "Failed to download \(file) (HTTP \(status))."
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
	public func deleteModel(_ modelName: String) throws {}
}

#endif
