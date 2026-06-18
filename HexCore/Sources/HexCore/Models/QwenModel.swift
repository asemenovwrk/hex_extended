import Foundation

/// Qwen3-ASR transcription models (MLX, on-device via Apple Silicon GPU).
///
/// These run through `mlx-swift-asr` and are downloaded from the `mlx-community`
/// Hugging Face repositories. Three curated tiers trade size/speed for accuracy.
/// Selection elsewhere in the app is by exact `rawValue` match (mirrors
/// `ParakeetModel`), so the rawValues are distinctive and end in `-mlx`.
public enum QwenModel: String, CaseIterable, Sendable {
	/// 0.6B, 8-bit — fast, small (~0.6GB). Good RU; English terms benefit from context.
	case low = "qwen3-asr-0.6b-8bit-mlx"
	/// 1.7B, 8-bit — balanced (~1.8GB).
	case medium = "qwen3-asr-1.7b-8bit-mlx"
	/// 1.7B, bf16 — maximum quality (~3.8GB), unquantized.
	case high = "qwen3-asr-1.7b-bf16-mlx"

	/// The identifier used throughout the app (matches the on-disk folder name).
	public var identifier: String { rawValue }

	/// The Hugging Face repository the MLX weights are downloaded from.
	public var huggingFaceRepo: String {
		switch self {
		case .low: "mlx-community/Qwen3-ASR-0.6B-8bit"
		case .medium: "mlx-community/Qwen3-ASR-1.7B-8bit"
		case .high: "mlx-community/Qwen3-ASR-1.7B-bf16"
		}
	}

	/// Short capability label for UI copy. All tiers are multilingual (RU+EN incl.).
	public var capabilityLabel: String { "Multilingual" }

	/// Approximate on-disk size of `model.safetensors`, used only as a fallback
	/// denominator for download progress when the server omits Content-Length.
	public var approximateWeightBytes: Int64 {
		switch self {
		case .low: 1_000_000_000      // ~0.96GB
		case .medium: 1_900_000_000   // ~1.8GB
		case .high: 4_100_000_000     // ~3.8GB
		}
	}

	/// Metadata files the model loader genuinely needs (download fails if any are
	/// missing). `tokenizer.json` is intentionally absent — the mlx-community repos
	/// ship only `vocab.json`+`merges.txt`, so we inject a bundled `tokenizer.json`
	/// (identical across all Qwen3-ASR sizes) after download.
	public static let requiredMetadataFileNames: [String] = [
		"config.json",
		"vocab.json",
		"merges.txt",
		"tokenizer_config.json",
	]

	/// Best-effort metadata: downloaded if present, skipped on 404 (some repos /
	/// future variants may omit these — e.g. `index.json` only exists for sharded
	/// weights).
	public static let optionalMetadataFileNames: [String] = [
		"generation_config.json",
		"preprocessor_config.json",
		"chat_template.json",
		"model.safetensors.index.json",
	]

	public static let weightFileName = "model.safetensors"
	public static let tokenizerFileName = "tokenizer.json"
}
