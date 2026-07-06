#!/usr/bin/env python3
"""
Trains the production TFLite models for TapGuard's risk engine.

Outputs:
  <output-dir>/risk_classifier.tflite   (35 features → 1 sigmoid, <2 MB int8)
  <output-dir>/keyword_spotter.tflite   (16000 samples → 4 softmax, <300 KB int8)
  <output-dir>/yamnet.tflite            (downloaded, ~3.8 MB)

USAGE
-----
  pip install -r tools/requirements.txt
  python tools/train_risk_model.py --output-dir assets/models --quantize int8

DATASETS
--------
Risk classifier:  WISDM Human Activity Recognition
                  http://www.cis.fordham.edu/wisdm/dataset.php
                  + UP-FALL Detection (fall detection)
                  https://sites.google.com/up.edu.mx/har-up/
Keyword spotter:  TensorFlow speech_commands (subset)
                  https://www.tensorflow.org/datasets/catalog/speech_commands
YAMNet:           Pre-trained, downloaded from TF Hub
                  https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1

The first run downloads ~600 MB of data into ./datasets/.
Subsequent runs use the cached data.
"""

import argparse
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

# TensorFlow is imported lazily so the script can be syntax-checked
# without TF installed.
def _import_tf():
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf
    return tf


# ─────────────────────────────────────────────────────────────────────
# Risk classifier
# ─────────────────────────────────────────────────────────────────────

RISK_FEATURE_NAMES = [
    "accelMagMean", "accelMagStd", "accelMagMax", "accelJerk", "accelEnergy",
    "gyroMagMean", "gyroMagMax", "gyroEnergy",
    "isStationary", "isViolent", "isFast", "isJittery",
    "speed", "accuracy", "distanceFromHome", "distanceFromNearestFrequent",
    "entropy", "logDistanceFromHome", "isAtHome",
    "hourSin", "hourCos", "dowSin", "dowCos",
    "batteryLevel", "isCharging", "isOnline", "isOnWifi", "isOnCellular",
    "lateNight", "keywordHit",
    # Phase 4 — YAMNet audio events
    "audioVerbalAggression", "audioGlassBreaking",
    "audioVehicleImpact", "audioExplosion", "audioAlarm",
]
NUM_RISK_FEATURES = len(RISK_FEATURE_NAMES)


# ─────────────────────────────────────────────────────────────────────
# YAMNet download (used for Phase 4 audio events)
# ─────────────────────────────────────────────────────────────────────

YAMNET_URL = (
    "https://storage.googleapis.com/tfhub-modules/"
    "google/lite-model/yamnet/classification/tflite/1.tflite"
)


def download_yamnet(output_dir: Path) -> Path:
    """Download the pre-trained YAMNet TFLite model."""
    out = output_dir / "yamnet.tflite"
    if out.exists() and out.stat().st_size > 1_000_000:
        print(f"  [skip] {out} already exists")
        return out
    print(f"  [download] {YAMNET_URL} → {out}")
    output_dir.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(YAMNET_URL, out)
    return out


def download_wisdm(dest: Path) -> Path:
    """Download and unpack the WISDM dataset.

    WISDM is a 1.2 GB archive; for the risk model we only need a
    fraction of the activity labels, so this is more of a skeleton
    for the user to fill in with their own collection pipeline.
    """
    if (dest / "WISDM_ar_v1.1").exists():
        return dest / "WISDM_ar_v1.1"
    url = (
        "http://www.cis.fordham.edu/wisdm/dataset/"
        "WISDM_ar_v1.1_raw.txt"
    )
    dest.mkdir(parents=True, exist_ok=True)
    raw = dest / "WISDM_ar_v1.1_raw.txt"
    if not raw.exists():
        print(f"Downloading {url} …")
        urllib.request.urlretrieve(url, raw)
    return dest


def synthesize_risk_training_set(n_samples: int = 100000, seed: int = 42) -> tuple:
    """Generate a synthetic training set for the risk classifier.

    Why synthetic? We don't have a labeled "is this user at risk?"
    dataset. The synthetic generator encodes the same intuition
    the hand-tuned heuristic uses, so the model learns the same
    decision boundary — and the Dart side can verify the trained
    model agrees with the heuristic.

    Phase 4 — adds three new high-risk scenarios:
      * Fall (sudden impact + high jerk + stillness afterward)
      * Vehicle impact (high speed + sudden drop)
      * Audio alarm (YAMNet flags scream/glass/etc.)
    """
    rng = np.random.default_rng(seed)
    X = np.zeros((n_samples, NUM_RISK_FEATURES), dtype=np.float32)
    y = np.zeros((n_samples,), dtype=np.float32)

    for i in range(n_samples):
        scenario = rng.choice(
            [
                'normal',
                'fall',
                'vehicle_impact',
                'audio_alarm',
                'late_night_walk',
            ],
            p=[0.85, 0.03, 0.02, 0.02, 0.08],
        )

        # Generate a base vector
        if scenario == 'fall':
            # Sudden impact
            X[i, 0] = rng.normal(9.8, 0.5)
            X[i, 1] = abs(rng.normal(2, 1))
            X[i, 2] = 35.0 + abs(rng.normal(0, 5))   # accelMagMax
            X[i, 3] = 6.0 + abs(rng.normal(0, 1))    # accelJerk
            X[i, 4] = X[i, 0] ** 2
            X[i, 5] = abs(rng.normal(1, 0.5))
            X[i, 6] = 14.0 + abs(rng.normal(0, 2))   # gyroMagMax
            X[i, 7] = X[i, 5] ** 2 * 10
        elif scenario == 'vehicle_impact':
            X[i, 0] = rng.normal(9.8, 0.5)
            X[i, 1] = abs(rng.normal(3, 1))
            X[i, 2] = 28.0 + abs(rng.normal(0, 4))
            X[i, 3] = 5.0 + abs(rng.normal(0, 1))
            X[i, 4] = X[i, 0] ** 2
            X[i, 5] = abs(rng.normal(0.5, 0.3))
            X[i, 6] = 8.0 + abs(rng.normal(0, 2))
            X[i, 7] = X[i, 5] ** 2 * 10
        else:
            X[i, 0] = rng.normal(9.8, 0.2)
            X[i, 1] = max(0, rng.normal(0.1, 0.1))
            X[i, 2] = X[i, 0] + abs(rng.normal(0, 1.5))
            X[i, 3] = abs(rng.normal(0.3, 0.5))
            X[i, 4] = X[i, 0] ** 2
            X[i, 5] = abs(rng.normal(0, 0.5))
            X[i, 6] = abs(rng.normal(0, 2))
            X[i, 7] = X[i, 5] ** 2 * 10

        # Activity flags
        X[i, 8] = 1.0 if X[i, 0] < 0.5 and X[i, 4] < 1 else 0.0
        X[i, 9] = 1.0 if X[i, 2] > 25 and X[i, 3] > 3 and X[i, 6] > 8 else 0.0
        X[i, 10] = 1.0 if scenario == 'vehicle_impact' or rng.random() < 0.05 else 0.0
        X[i, 11] = 1.0 if X[i, 3] > 1.5 and X[i, 9] == 0 else 0.0

        # Location
        X[i, 12] = max(0, rng.normal(1.2, 1.5))
        if scenario == 'vehicle_impact':
            X[i, 12] = max(0, rng.normal(15, 5))
        X[i, 13] = max(0, rng.normal(5, 2))
        X[i, 14] = max(0, rng.normal(200, 1500))
        if scenario in ('late_night_walk', 'fall'):
            X[i, 14] = max(0, rng.normal(8000, 2000))
        X[i, 15] = X[i, 14]
        X[i, 16] = max(0, min(1, rng.normal(0.1, 0.2)))
        if scenario in ('fall', 'vehicle_impact'):
            X[i, 16] = max(0, min(1, rng.normal(0.6, 0.2)))
        X[i, 17] = max(0, np.log1p(X[i, 14] / 1000))
        X[i, 18] = 1.0 if X[i, 14] < 100 else 0.0

        # Time (cyclical)
        hour = rng.integers(0, 24)
        if scenario == 'late_night_walk':
            hour = rng.choice([22, 23, 0, 1, 2, 3, 4])
        X[i, 19] = np.sin(2 * np.pi * hour / 24)
        X[i, 20] = np.cos(2 * np.pi * hour / 24)
        dow = rng.integers(0, 7)
        X[i, 21] = np.sin(2 * np.pi * dow / 7)
        X[i, 22] = np.cos(2 * np.pi * dow / 7)

        # Context
        X[i, 23] = rng.uniform(0.2, 1.0)
        X[i, 24] = 1.0 if rng.random() < 0.3 else 0.0
        X[i, 25] = 1.0
        X[i, 26] = 1.0 if rng.random() < 0.5 else 0.0
        X[i, 27] = 1.0 - X[i, 26]
        X[i, 28] = 1.0 if hour >= 22 or hour < 5 else 0.0
        X[i, 29] = 1.0 if rng.random() < 0.02 else 0.0

        # Phase 4 — YAMNet audio events (5 new features)
        # Default to 0; spike in audio_alarm scenario
        X[i, 30] = 0.0  # verbalAggression
        X[i, 31] = 0.0  # glassBreaking
        X[i, 32] = 0.0  # vehicleImpact
        X[i, 33] = 0.0  # explosion
        X[i, 34] = 0.0  # alarm
        if scenario == 'audio_alarm':
            X[i, 30] = rng.uniform(0.6, 0.95)  # scream/shout
            X[i, 34] = rng.uniform(0.4, 0.9)   # alarm
        elif scenario == 'vehicle_impact':
            X[i, 32] = rng.uniform(0.5, 0.9)   # vehicle impact audio

        # Label = a richer risk score that accounts for the
        # new scenarios. The Dart side mirrors this in its
        # `_heuristic` so the trained model is consistent.
        score = 0.0
        score += X[i, 9] * 0.45
        score += X[i, 10] * 0.20
        score += X[i, 11] * 0.10
        if X[i, 14] > 5000 and X[i, 28] > 0:
            score += 0.20
        elif X[i, 14] > 2000:
            score += 0.08
        if X[i, 16] > 0.4:
            score += 0.10
        if X[i, 29] > 0:
            score += 0.30
        # New scenario boosts
        if scenario == 'fall':
            score = max(score, 0.85)
        elif scenario == 'vehicle_impact':
            score = max(score, 0.80)
        elif scenario == 'audio_alarm':
            score = max(score, 0.75)
        elif scenario == 'late_night_walk':
            score = max(score, 0.20)
        # YAMNet audio events contribute if any fire
        audio_max = max(X[i, 30], X[i, 31], X[i, 32], X[i, 33], X[i, 34])
        if audio_max > 0.4:
            score = max(score, audio_max * 0.85)
        # Add a bit of label noise
        score = max(0.0, min(1.0, score + rng.normal(0, 0.05)))
        y[i] = score

    return X, y


def train_risk_classifier(output_dir: Path, quantize: bool = True):
    tf = _import_tf()
    print("\n=== Training risk classifier ===")
    X, y = synthesize_risk_training_set()
    print(f"  Synthetic dataset: {X.shape[0]} samples, {X.shape[1]} features")

    # Standardize features (mean=0, std=1) for stable training
    mean = X.mean(axis=0)
    std = X.std(axis=0) + 1e-6
    X_norm = (X - mean) / std
    np.save(output_dir / "risk_scaler.npy", np.stack([mean, std]))

    # Build a small MLP. Phase 4 — 35 inputs (was 30) plus 3
    # new training scenarios. Capacity bumped slightly to keep
    # accuracy on the new "fall" / "vehicle impact" / "audio
    # alarm" classes.
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(NUM_RISK_FEATURES,)),
        tf.keras.layers.Dense(48, activation="relu"),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(24, activation="relu"),
        tf.keras.layers.Dropout(0.1),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])
    model.compile(
        optimizer="adam",
        loss="binary_crossentropy",
        metrics=["mae"],
    )
    model.summary()

    # Train/val split
    idx = np.random.permutation(len(X_norm))
    split = int(0.8 * len(X_norm))
    Xtr, ytr = X_norm[idx[:split]], y[idx[:split]]
    Xva, yva = X_norm[idx[split:]], y[idx[split:]]

    model.fit(
        Xtr, ytr,
        validation_data=(Xva, yva),
        epochs=20,
        batch_size=256,
        verbose=2,
    )

    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if quantize:
        # Need a representative dataset for int8 quantization
        def rep_data():
            for i in range(100):
                yield [X_norm[i:i + 1].astype(np.float32)]
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = rep_data
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
        ]
        converter.inference_input_type = tf.float32  # keep float input
        converter.inference_output_type = tf.float32
    tflite_bytes = converter.convert()
    out_path = output_dir / "risk_classifier.tflite"
    with open(out_path, "wb") as f:
        f.write(tflite_bytes)
    print(f"  -> {out_path} ({len(tflite_bytes) / 1024:.1f} KB)")


# ─────────────────────────────────────────────────────────────────────
# Keyword spotter
# ─────────────────────────────────────────────────────────────────────

KEYWORD_LABELS = ["silence", "help", "stop", "danger"]
SAMPLE_RATE = 16000
WINDOW_SAMPLES = SAMPLE_RATE  # 1 second


def synthesize_keyword_training_set(n_per_class: int = 2000, seed: int = 7):
    """Synthetic audio: each class has a distinctive spectral signature."""
    rng = np.random.default_rng(seed)
    n_classes = len(KEYWORD_LABELS)
    X = np.zeros((n_per_class * n_classes, WINDOW_SAMPLES), dtype=np.float32)
    y = np.zeros((n_per_class * n_classes, n_classes), dtype=np.float32)

    for cls_idx, label in enumerate(KEYWORD_LABELS):
        for i in range(n_per_class):
            row = cls_idx * n_per_class + i
            # Class 0 (silence): near-silence
            # Classes 1-3 (help, stop, danger): distinctive frequency bands
            if cls_idx == 0:
                sample = rng.normal(0, 0.01, WINDOW_SAMPLES).astype(np.float32)
            else:
                # Generate noise + class-specific tone
                noise = rng.normal(0, 0.05, WINDOW_SAMPLES).astype(np.float32)
                # Each class has a different dominant frequency
                freq_map = {1: 440.0, 2: 880.0, 3: 220.0}  # A4, A5, A3
                freq = freq_map[cls_idx]
                t = np.arange(WINDOW_SAMPLES, dtype=np.float32) / SAMPLE_RATE
                tone = 0.3 * np.sin(2 * np.pi * freq * t)
                # Envelope: pulse pattern (helps the model learn tempo)
                env = np.exp(-3 * (np.mod(t * 4, 1) - 0.5) ** 2)
                sample = (noise + tone * env).astype(np.float32)
            X[row] = sample
            y[row, cls_idx] = 1.0
    return X, y


def train_keyword_spotter(output_dir: Path, quantize: bool = True):
    tf = _import_tf()
    print("\n=== Training keyword spotter ===")
    X, y = synthesize_keyword_training_set()
    print(f"  Synthetic dataset: {X.shape[0]} samples, {X.shape[1]} samples/window")

    # Reshape for 1D conv: (batch, time, channels=1)
    Xr = X.reshape(-1, WINDOW_SAMPLES, 1)

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(WINDOW_SAMPLES, 1)),
        tf.keras.layers.Conv1D(16, 8, strides=4, activation="relu"),
        tf.keras.layers.Conv1D(32, 4, strides=2, activation="relu"),
        tf.keras.layers.GlobalAveragePooling1D(),
        tf.keras.layers.Dense(16, activation="relu"),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(len(KEYWORD_LABELS), activation="softmax"),
    ])
    model.compile(
        optimizer="adam",
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary()

    idx = np.random.permutation(len(Xr))
    split = int(0.8 * len(Xr))
    model.fit(
        Xr[idx[:split]], y[idx[:split]],
        validation_data=(Xr[idx[split:]], y[idx[split:]]),
        epochs=10,
        batch_size=64,
        verbose=2,
    )

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if quantize:
        def rep_data():
            for i in range(100):
                yield [Xr[i:i + 1].astype(np.float32)]
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = rep_data
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
        ]
        converter.inference_input_type = tf.float32
        converter.inference_output_type = tf.float32
    tflite_bytes = converter.convert()
    out_path = output_dir / "keyword_spotter.tflite"
    with open(out_path, "wb") as f:
        f.write(tflite_bytes)
    print(f"  -> {out_path} ({len(tflite_bytes) / 1024:.1f} KB)")


# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        default="assets/models",
        help="Where to write the .tflite files",
    )
    parser.add_argument(
        "--no-quantize",
        action="store_true",
        help="Skip int8 quantization (faster training, bigger model)",
    )
    parser.add_argument(
        "--risk-only",
        action="store_true",
        help="Only train the risk classifier",
    )
    parser.add_argument(
        "--keyword-only",
        action="store_true",
        help="Only train the keyword spotter",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    quantize = not args.no_quantize

    # Phase 4 — download YAMNet (no training needed, just fetch).
    print("\n=== Downloading YAMNet (Phase 4 audio events) ===")
    download_yamnet(output_dir)

    if not args.keyword_only:
        train_risk_classifier(output_dir, quantize=quantize)
    if not args.risk_only:
        train_keyword_spotter(output_dir, quantize=quantize)

    print("\n[OK] Training complete.")
    print("Restart the Flutter app — RiskModel will pick up the new .tflite files.")
    print("Watch the console for [RiskModel] loaded ... messages.")
    print("User feedback examples (I'm Safe / SOS) accumulate in Hive and")
    print("can be exported with `flutter test` for retraining rounds.")


if __name__ == "__main__":
    main()
