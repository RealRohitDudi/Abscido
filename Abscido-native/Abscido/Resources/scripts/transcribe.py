#!/usr/bin/env python3
"""
Abscido — MLX-Whisper transcription script.

Runs local speech-to-text using Apple Silicon's Neural Engine + GPU
via the mlx-whisper package. Outputs word-level timestamps as JSON.

Usage:
    python3 transcribe.py <wav_path> <language> [model_name]

Arguments:
    wav_path    - Path to 16kHz mono WAV audio file
    language    - ISO 639-1 language code (e.g., 'en', 'es', 'fr')
    model_name  - HuggingFace model repo (default: mlx-community/whisper-large-v3-mlx)

Environment:
    ABSCIDO_CACHE_DIR - Directory for model cache (default: ~/.cache/abscido/models)

Output:
    stdout: Single JSON line with Whisper result (text, segments, words)
    stderr: JSON lines with progress updates: {"progress": 0.45}

Exit codes:
    0 - Success
    1 - Error (JSON error object written to stdout)
"""

import json
import os
import sys
import time


def write_progress(progress: float) -> None:
    """Write progress update to stderr as JSON line."""
    msg = json.dumps({"progress": round(progress, 4)})
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def write_error(message: str) -> None:
    """Write error to stdout as JSON and exit with code 1."""
    json.dump({"error": message}, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    sys.exit(1)


def ensure_model_cached(model_name: str, cache_dir: str) -> str:
    """Check if model is cached, return the path. Model downloads automatically on first use."""
    os.makedirs(cache_dir, exist_ok=True)
    # mlx-whisper handles downloading via huggingface_hub
    # We just ensure the cache directory exists
    return model_name


def main():
    if len(sys.argv) < 3:
        write_error(
            "Usage: transcribe.py <wav_path> <language> [model_name]"
        )

    wav_path = sys.argv[1]
    language = sys.argv[2]
    model_name = (
        sys.argv[3]
        if len(sys.argv) > 3
        else "mlx-community/whisper-large-v3-mlx"
    )

    # Validate input file
    if not os.path.isfile(wav_path):
        write_error(f"Audio file not found: {wav_path}")

    # Set up cache directory
    cache_dir = os.environ.get(
        "ABSCIDO_CACHE_DIR",
        os.path.expanduser("~/.cache/abscido/models"),
    )

    write_progress(0.0)

    # Import mlx_whisper (may take a moment on first load)
    try:
        import mlx_whisper
    except ImportError:
        write_error(
            "mlx-whisper is not installed. "
            "Install with: pip install mlx-whisper"
        )

    write_progress(0.05)

    # Ensure model is available
    model_path = ensure_model_cached(model_name, cache_dir)
    write_progress(0.1)

    # Run transcription
    try:
        write_progress(0.15)

        result = mlx_whisper.transcribe(
            wav_path,
            path_or_hf_repo=model_path,
            word_timestamps=True,
            language=language,
            verbose=False,
        )

        write_progress(0.9)

        # Clean up result for JSON serialization
        output = {
            "text": result.get("text", ""),
            "language": result.get("language", language),
            "segments": [],
        }

        for segment in result.get("segments", []):
            seg_data = {
                "id": segment.get("id", 0),
                "start": segment.get("start", 0.0),
                "end": segment.get("end", 0.0),
                "text": segment.get("text", ""),
            }

            # Extract word-level timestamps
            words = segment.get("words", [])
            if words:
                seg_data["words"] = [
                    {
                        "word": w.get("word", ""),
                        "start": w.get("start", 0.0),
                        "end": w.get("end", 0.0),
                        "probability": w.get("probability", 1.0),
                    }
                    for w in words
                ]

            output["segments"].append(seg_data)

        write_progress(0.95)

        # Write result to stdout
        json.dump(output, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        sys.stdout.flush()

        write_progress(1.0)

    except Exception as e:
        write_error(f"Transcription failed: {str(e)}")


if __name__ == "__main__":
    main()
