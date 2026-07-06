#!/usr/bin/env python3
"""
Minimal model builder — produces valid .tflite files for the
TapGuard risk engine without the heavy WISDM dataset download.

Outputs:
  assets/models/risk_classifier.tflite   (35 -> 1, sigmoid)
  assets/models/keyword_spotter.tflite   (16000 -> 4, softmax)

YAMNet is downloaded separately (see tools/download_yamnet.py).

This script is meant for getting the on-device pipeline running
quickly. For production-quality weights run tools/train_risk_model.py.
"""
import os
import sys
from pathlib import Path

os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
import numpy as np
import tensorflow as tf

# Match the 35-dim RiskFeatures vector in feature_extractor.dart
NUM_RISK_FEATURES = 35
RISK_FEATURE_NAMES = [
    'accelMagMean', 'accelMagStd', 'accelMagMax', 'accelJerk', 'accelEnergy',
    'gyroMagMean', 'gyroMagMax', 'gyroEnergy',
    'isStationary', 'isViolent', 'isFast', 'isJittery',
    'speed', 'accuracy', 'distanceFromHome', 'distanceFromNearestFrequent',
    'entropy', 'logDistanceFromHome', 'isAtHome',
    'hourSin', 'hourCos', 'dowSin', 'dowCos',
    'batteryLevel', 'isCharging', 'isOnline', 'isOnWifi', 'isOnCellular',
    'lateNight', 'keywordHit',
    'audioVerbalAggression', 'audioGlassBreaking',
    'audioVehicleImpact', 'audioExplosion', 'audioAlarm',
]

def synthesize_risk(n=20000, seed=42):
    rng = np.random.default_rng(seed)
    X = np.zeros((n, NUM_RISK_FEATURES), dtype=np.float32)
    y = np.zeros((n,), dtype=np.float32)
    scenarios = ['normal', 'fall', 'vehicle_impact', 'audio_alarm', 'late_night_walk']
    probs = [0.85, 0.03, 0.02, 0.02, 0.08]

    for i in range(n):
        s = rng.choice(scenarios, p=probs)
        # accel/gyro baselines
        X[i, 0] = rng.normal(9.8, 0.3)
        X[i, 1] = max(0, rng.normal(0.2 if s == 'normal' else 1.5, 0.3))
        X[i, 2] = X[i, 0] + abs(rng.normal(0, 1.5)) + (15 if s == 'fall' else (12 if s == 'vehicle_impact' else 0))
        X[i, 3] = abs(rng.normal(0.4 if s == 'normal' else 4.0, 0.6))
        X[i, 4] = X[i, 0] ** 2
        X[i, 5] = abs(rng.normal(0, 0.5))
        X[i, 6] = abs(rng.normal(0, 2)) + (8 if s in ('fall', 'vehicle_impact') else 0)
        X[i, 7] = X[i, 5] ** 2 * 10

        # derived flags
        X[i, 8] = 1.0 if (X[i, 0] < 0.5 and X[i, 4] < 1) else 0.0
        X[i, 9] = 1.0 if (X[i, 2] > 25 and X[i, 3] > 3 and X[i, 6] > 8) else 0.0
        X[i, 10] = 1.0 if s == 'vehicle_impact' else (1.0 if rng.random() < 0.05 else 0.0)
        X[i, 11] = 1.0 if (X[i, 3] > 1.5 and X[i, 9] == 0) else 0.0

        # location
        X[i, 12] = max(0, rng.normal(1.2, 1.5))
        if s == 'vehicle_impact':
            X[i, 12] = max(0, rng.normal(15, 5))
        X[i, 13] = max(0, rng.normal(5, 2))
        X[i, 14] = max(0, rng.normal(200, 1500))
        if s in ('late_night_walk', 'fall'):
            X[i, 14] = max(0, rng.normal(8000, 2000))
        X[i, 15] = X[i, 14]
        X[i, 16] = max(0, min(1, rng.normal(0.1, 0.2)))
        if s in ('fall', 'vehicle_impact'):
            X[i, 16] = max(0, min(1, rng.normal(0.6, 0.2)))
        X[i, 17] = max(0, np.log1p(X[i, 14] / 1000))
        X[i, 18] = 1.0 if X[i, 14] < 100 else 0.0

        # time
        hour = rng.integers(0, 24)
        if s == 'late_night_walk':
            hour = int(rng.choice([22, 23, 0, 1, 2, 3, 4]))
        X[i, 19] = np.sin(2 * np.pi * hour / 24)
        X[i, 20] = np.cos(2 * np.pi * hour / 24)
        dow = rng.integers(0, 7)
        X[i, 21] = np.sin(2 * np.pi * dow / 7)
        X[i, 22] = np.cos(2 * np.pi * dow / 7)

        # context
        X[i, 23] = rng.uniform(0.2, 1.0)
        X[i, 24] = 1.0 if rng.random() < 0.3 else 0.0
        X[i, 25] = 1.0
        X[i, 26] = 1.0 if rng.random() < 0.5 else 0.0
        X[i, 27] = 1.0 - X[i, 26]
        X[i, 28] = 1.0 if (hour >= 22 or hour < 5) else 0.0
        X[i, 29] = 1.0 if rng.random() < 0.02 else 0.0

        # audio events
        if s == 'audio_alarm':
            X[i, 30] = rng.uniform(0.6, 0.95)
            X[i, 34] = rng.uniform(0.4, 0.9)
        elif s == 'vehicle_impact':
            X[i, 32] = rng.uniform(0.5, 0.9)

        # label
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
        if s == 'fall':
            score = max(score, 0.85)
        elif s == 'vehicle_impact':
            score = max(score, 0.80)
        elif s == 'audio_alarm':
            score = max(score, 0.75)
        elif s == 'late_night_walk':
            score = max(score, 0.20)
        audio_max = max(X[i, 30], X[i, 31], X[i, 32], X[i, 33], X[i, 34])
        if audio_max > 0.4:
            score = max(score, audio_max * 0.85)
        score = max(0.0, min(1.0, score + rng.normal(0, 0.05)))
        y[i] = score

    return X, y


def train_risk(output_dir):
    print('\n=== Training risk classifier ===')
    X, y = synthesize_risk()
    print(f'  {X.shape[0]} samples, {X.shape[1]} features')
    # NOTE: train on raw feature values (NOT standardized). The Dart
    # inference path in risk_model.dart passes features.toList() as-is,
    # so the model must accept raw inputs without a server-side scaler.
    Xn = X

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(NUM_RISK_FEATURES,)),
        tf.keras.layers.Dense(48, activation='relu'),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(24, activation='relu'),
        tf.keras.layers.Dropout(0.1),
        tf.keras.layers.Dense(1, activation='sigmoid'),
    ])
    model.compile(optimizer='adam', loss='binary_crossentropy', metrics=['mae'])
    model.summary()

    idx = np.random.permutation(len(Xn))
    split = int(0.8 * len(Xn))
    model.fit(
        Xn[idx[:split]], y[idx[:split]],
        validation_data=(Xn[idx[split:]], y[idx[split:]]),
        epochs=10, batch_size=256, verbose=1,
    )

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_bytes = converter.convert()
    out = output_dir / 'risk_classifier.tflite'
    out.write_bytes(tflite_bytes)
    print(f'  -> {out} ({len(tflite_bytes) / 1024:.1f} KB)')


KEYWORD_LABELS = ['silence', 'help', 'stop', 'danger']
SR = 16000


def synthesize_keyword(n_per=400, seed=7):
    rng = np.random.default_rng(seed)
    X = np.zeros((n_per * len(KEYWORD_LABELS), SR), dtype=np.float32)
    y = np.zeros((n_per * len(KEYWORD_LABELS), len(KEYWORD_LABELS)), dtype=np.float32)
    freqs = [0, 440, 880, 220]
    for cls in range(len(KEYWORD_LABELS)):
        for i in range(n_per):
            row = cls * n_per + i
            if cls == 0:
                X[row] = rng.normal(0, 0.01, SR).astype(np.float32)
            else:
                noise = rng.normal(0, 0.05, SR).astype(np.float32)
                t = np.arange(SR, dtype=np.float32) / SR
                tone = 0.3 * np.sin(2 * np.pi * freqs[cls] * t)
                env = np.exp(-3 * (np.mod(t * 4, 1) - 0.5) ** 2)
                X[row] = (noise + tone * env).astype(np.float32)
            y[row, cls] = 1.0
    return X, y


def train_keyword(output_dir):
    print('\n=== Training keyword spotter ===')
    X, y = synthesize_keyword()
    Xr = X.reshape(-1, SR, 1)
    print(f'  {Xr.shape[0]} samples, {Xr.shape[1]} samples/window')

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(SR, 1)),
        tf.keras.layers.Conv1D(16, 8, strides=4, activation='relu'),
        tf.keras.layers.Conv1D(32, 4, strides=2, activation='relu'),
        tf.keras.layers.GlobalAveragePooling1D(),
        tf.keras.layers.Dense(16, activation='relu'),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(len(KEYWORD_LABELS), activation='softmax'),
    ])
    model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
    model.summary()

    idx = np.random.permutation(len(Xr))
    split = int(0.8 * len(Xr))
    model.fit(
        Xr[idx[:split]], y[idx[:split]],
        validation_data=(Xr[idx[split:]], y[idx[split:]]),
        epochs=8, batch_size=64, verbose=1,
    )

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # Float32 fallback (see comment in train_risk).
    tflite_bytes = converter.convert()
    out = output_dir / 'keyword_spotter.tflite'
    out.write_bytes(tflite_bytes)
    print(f'  -> {out} ({len(tflite_bytes) / 1024:.1f} KB)')


def main():
    output_dir = Path(sys.argv[1] if len(sys.argv) > 1 else 'assets/models')
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f'Output dir: {output_dir.resolve()}')

    train_risk(output_dir)
    train_keyword(output_dir)

    print('\n[OK] Models written. Restart the Flutter app — RiskModel will pick them up.')
    print('Watch the console for "[RiskModel] loaded ..." messages.')


if __name__ == '__main__':
    main()
