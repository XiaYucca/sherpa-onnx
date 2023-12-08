#!/usr/bin/env python3
#
# Copyright (c)  2023 by manyeyes
# Copyright (c)  2023  Xiaomi Corporation

"""
This file demonstrates how to use sherpa-onnx Python API to transcribe
file(s) with a non-streaming model.

(1) For paraformer

    ./python-api-examples/offline-decode-files.py  \
      --tokens=/path/to/tokens.txt \
      --paraformer=/path/to/paraformer.onnx \
      --num-threads=2 \
      --decoding-method=greedy_search \
      --debug=false \
      --sample-rate=16000 \
      --feature-dim=80 \
      /path/to/0.wav \
      /path/to/1.wav

(2) For transducer models from icefall

    ./python-api-examples/offline-decode-files.py  \
      --tokens=/path/to/tokens.txt \
      --encoder=/path/to/encoder.onnx \
      --decoder=/path/to/decoder.onnx \
      --joiner=/path/to/joiner.onnx \
      --num-threads=2 \
      --decoding-method=greedy_search \
      --debug=false \
      --sample-rate=16000 \
      --feature-dim=80 \
      /path/to/0.wav \
      /path/to/1.wav

(3) For CTC models from NeMo

python3 ./python-api-examples/offline-decode-files.py \
  --tokens=./sherpa-onnx-nemo-ctc-en-citrinet-512/tokens.txt \
  --nemo-ctc=./sherpa-onnx-nemo-ctc-en-citrinet-512/model.onnx \
  --num-threads=2 \
  --decoding-method=greedy_search \
  --debug=false \
  ./sherpa-onnx-nemo-ctc-en-citrinet-512/test_wavs/0.wav \
  ./sherpa-onnx-nemo-ctc-en-citrinet-512/test_wavs/1.wav \
  ./sherpa-onnx-nemo-ctc-en-citrinet-512/test_wavs/8k.wav

(4) For Whisper models

python3 ./python-api-examples/offline-decode-files.py \
  --whisper-encoder=./sherpa-onnx-whisper-base.en/base.en-encoder.int8.onnx \
  --whisper-decoder=./sherpa-onnx-whisper-base.en/base.en-decoder.int8.onnx \
  --tokens=./sherpa-onnx-whisper-base.en/base.en-tokens.txt \
  --whisper-task=transcribe \
  --num-threads=1 \
  ./sherpa-onnx-whisper-base.en/test_wavs/0.wav \
  ./sherpa-onnx-whisper-base.en/test_wavs/1.wav \
  ./sherpa-onnx-whisper-base.en/test_wavs/8k.wav

(5) For CTC models from WeNet

python3 ./python-api-examples/offline-decode-files.py \
  --wenet-ctc=./sherpa-onnx-zh-wenet-wenetspeech/model.onnx \
  --tokens=./sherpa-onnx-zh-wenet-wenetspeech/tokens.txt \
  ./sherpa-onnx-zh-wenet-wenetspeech/test_wavs/0.wav \
  ./sherpa-onnx-zh-wenet-wenetspeech/test_wavs/1.wav \
  ./sherpa-onnx-zh-wenet-wenetspeech/test_wavs/8k.wav

(6) For tdnn models of the yesno recipe from icefall

python3 ./python-api-examples/offline-decode-files.py \
  --sample-rate=8000 \
  --feature-dim=23 \
  --tdnn-model=./sherpa-onnx-tdnn-yesno/model-epoch-14-avg-2.onnx \
  --tokens=./sherpa-onnx-tdnn-yesno/tokens.txt \
  ./sherpa-onnx-tdnn-yesno/test_wavs/0_0_0_1_0_0_0_1.wav \
  ./sherpa-onnx-tdnn-yesno/test_wavs/0_0_1_0_0_0_1_0.wav \
  ./sherpa-onnx-tdnn-yesno/test_wavs/0_0_1_0_0_1_1_1.wav

Please refer to
https://k2-fsa.github.io/sherpa/onnx/index.html
to install sherpa-onnx and to download non-streaming pre-trained models
used in this file.
"""
import argparse
import time
import wave
from pathlib import Path
from typing import List, Tuple

import numpy as np
import sherpa_onnx


def get_args():
    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    parser.add_argument(
        "--tokens",
        type=str,
        help="Path to tokens.txt",
    )

    parser.add_argument(
        "--hotwords-file",
        type=str,
        default="",
        help="""
        The file containing hotwords, one words/phrases per line, and for each
        phrase the bpe/cjkchar are separated by a space. For example:

        ▁HE LL O ▁WORLD
        你 好 世 界
        """,
    )

    parser.add_argument(
        "--hotwords-score",
        type=float,
        default=1.5,
        help="""
        The hotword score of each token for biasing word/phrase. Used only if
        --hotwords-file is given.
        """,
    )

    parser.add_argument(
        "--encoder",
        default="",
        type=str,
        help="Path to the encoder model",
    )

    parser.add_argument(
        "--decoder",
        default="",
        type=str,
        help="Path to the decoder model",
    )

    parser.add_argument(
        "--joiner",
        default="",
        type=str,
        help="Path to the joiner model",
    )

    parser.add_argument(
        "--paraformer",
        default="",
        type=str,
        help="Path to the model.onnx from Paraformer",
    )

    parser.add_argument(
        "--nemo-ctc",
        default="",
        type=str,
        help="Path to the model.onnx from NeMo CTC",
    )

    parser.add_argument(
        "--wenet-ctc",
        default="",
        type=str,
        help="Path to the model.onnx from WeNet CTC",
    )

    parser.add_argument(
        "--tdnn-model",
        default="",
        type=str,
        help="Path to the model.onnx for the tdnn model of the yesno recipe",
    )

    parser.add_argument(
        "--num-threads",
        type=int,
        default=1,
        help="Number of threads for neural network computation",
    )

    parser.add_argument(
        "--whisper-encoder",
        default="",
        type=str,
        help="Path to whisper encoder model",
    )

    parser.add_argument(
        "--whisper-decoder",
        default="",
        type=str,
        help="Path to whisper decoder model",
    )

    parser.add_argument(
        "--whisper-language",
        default="",
        type=str,
        help="""It specifies the spoken language in the input audio file.
        Example values: en, fr, de, zh, jp.
        Available languages for multilingual models can be found at
        https://github.com/openai/whisper/blob/main/whisper/tokenizer.py#L10
        If not specified, we infer the language from the input audio file.
        """,
    )

    parser.add_argument(
        "--whisper-task",
        default="transcribe",
        choices=["transcribe", "translate"],
        type=str,
        help="""For multilingual models, if you specify translate, the output
        will be in English.
        """,
    )

    parser.add_argument(
        "--whisper-tail-paddings",
        default=-1,
        type=int,
        help="""Number of tail padding frames.
        We have removed the 30-second constraint from whisper, so you need to
        choose the amount of tail padding frames by yourself.
        Use -1 to use a default value for tail padding.
        """,
    )

    parser.add_argument(
        "--decoding-method",
        type=str,
        default="greedy_search",
        help="Valid values are greedy_search and modified_beam_search",
    )
    parser.add_argument(
        "--debug",
        type=bool,
        default=False,
        help="True to show debug messages",
    )

    parser.add_argument(
        "--sample-rate",
        type=int,
        default=16000,
        help="""Sample rate of the feature extractor. Must match the one
        expected  by the model. Note: The input sound files can have a
        different sample rate from this argument.""",
    )

    parser.add_argument(
        "--feature-dim",
        type=int,
        default=80,
        help="Feature dimension. Must match the one expected by the model",
    )

    parser.add_argument(
        "sound_files",
        type=str,
        nargs="+",
        help="The input sound file(s) to decode. Each file must be of WAVE"
        "format with a single channel, and each sample has 16-bit, "
        "i.e., int16_t. "
        "The sample rate of the file can be arbitrary and does not need to "
        "be 16 kHz",
    )

    return parser.parse_args()


def assert_file_exists(filename: str):
    assert Path(filename).is_file(), (
        f"{filename} does not exist!\n"
        "Please refer to "
        "https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html to download it"
    )


def read_wave(wave_filename: str) -> Tuple[np.ndarray, int]:
    """
    Args:
      wave_filename:
        Path to a wave file. It should be single channel and each sample should
        be 16-bit. Its sample rate does not need to be 16kHz.
    Returns:
      Return a tuple containing:
       - A 1-D array of dtype np.float32 containing the samples, which are
       normalized to the range [-1, 1].
       - sample rate of the wave file
    """

    with wave.open(wave_filename) as f:
        assert f.getnchannels() == 1, f.getnchannels()
        assert f.getsampwidth() == 2, f.getsampwidth()  # it is in bytes
        num_samples = f.getnframes()
        samples = f.readframes(num_samples)
        samples_int16 = np.frombuffer(samples, dtype=np.int16)
        samples_float32 = samples_int16.astype(np.float32)

        samples_float32 = samples_float32 / 32768
        return samples_float32, f.getframerate()


def main():
    args = get_args()
    assert_file_exists(args.tokens)
    assert args.num_threads > 0, args.num_threads

    if args.encoder:
        assert len(args.paraformer) == 0, args.paraformer
        assert len(args.nemo_ctc) == 0, args.nemo_ctc
        assert len(args.wenet_ctc) == 0, args.wenet_ctc
        assert len(args.whisper_encoder) == 0, args.whisper_encoder
        assert len(args.whisper_decoder) == 0, args.whisper_decoder
        assert len(args.tdnn_model) == 0, args.tdnn_model

        assert_file_exists(args.encoder)
        assert_file_exists(args.decoder)
        assert_file_exists(args.joiner)

        recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=args.encoder,
            decoder=args.decoder,
            joiner=args.joiner,
            tokens=args.tokens,
            num_threads=args.num_threads,
            sample_rate=args.sample_rate,
            feature_dim=args.feature_dim,
            decoding_method=args.decoding_method,
            hotwords_file=args.hotwords_file,
            hotwords_score=args.hotwords_score,
            debug=args.debug,
        )
    elif args.paraformer:
        assert len(args.nemo_ctc) == 0, args.nemo_ctc
        assert len(args.wenet_ctc) == 0, args.wenet_ctc
        assert len(args.whisper_encoder) == 0, args.whisper_encoder
        assert len(args.whisper_decoder) == 0, args.whisper_decoder
        assert len(args.tdnn_model) == 0, args.tdnn_model

        assert_file_exists(args.paraformer)

        recognizer = sherpa_onnx.OfflineRecognizer.from_paraformer(
            paraformer=args.paraformer,
            tokens=args.tokens,
            num_threads=args.num_threads,
            sample_rate=args.sample_rate,
            feature_dim=args.feature_dim,
            decoding_method=args.decoding_method,
            debug=args.debug,
        )
    elif args.nemo_ctc:
        assert len(args.wenet_ctc) == 0, args.wenet_ctc
        assert len(args.whisper_encoder) == 0, args.whisper_encoder
        assert len(args.whisper_decoder) == 0, args.whisper_decoder
        assert len(args.tdnn_model) == 0, args.tdnn_model

        assert_file_exists(args.nemo_ctc)

        recognizer = sherpa_onnx.OfflineRecognizer.from_nemo_ctc(
            model=args.nemo_ctc,
            tokens=args.tokens,
            num_threads=args.num_threads,
            sample_rate=args.sample_rate,
            feature_dim=args.feature_dim,
            decoding_method=args.decoding_method,
            debug=args.debug,
        )
    elif args.wenet_ctc:
        assert len(args.whisper_encoder) == 0, args.whisper_encoder
        assert len(args.whisper_decoder) == 0, args.whisper_decoder
        assert len(args.tdnn_model) == 0, args.tdnn_model

        assert_file_exists(args.wenet_ctc)

        recognizer = sherpa_onnx.OfflineRecognizer.from_wenet_ctc(
            model=args.wenet_ctc,
            tokens=args.tokens,
            num_threads=args.num_threads,
            sample_rate=args.sample_rate,
            feature_dim=args.feature_dim,
            decoding_method=args.decoding_method,
            debug=args.debug,
        )
    elif args.whisper_encoder:
        assert len(args.tdnn_model) == 0, args.tdnn_model
        assert_file_exists(args.whisper_encoder)
        assert_file_exists(args.whisper_decoder)

        recognizer = sherpa_onnx.OfflineRecognizer.from_whisper(
            encoder=args.whisper_encoder,
            decoder=args.whisper_decoder,
            tokens=args.tokens,
            num_threads=args.num_threads,
            decoding_method=args.decoding_method,
            debug=args.debug,
            language=args.whisper_language,
            task=args.whisper_task,
            tail_paddings=args.whisper_tail_paddings,
        )
    elif args.tdnn_model:
        assert_file_exists(args.tdnn_model)

        recognizer = sherpa_onnx.OfflineRecognizer.from_tdnn_ctc(
            model=args.tdnn_model,
            tokens=args.tokens,
            sample_rate=args.sample_rate,
            feature_dim=args.feature_dim,
            num_threads=args.num_threads,
            decoding_method=args.decoding_method,
            debug=args.debug,
        )
    else:
        print("Please specify at least one model")
        return

    print("Started!")
    start_time = time.time()

    streams = []
    total_duration = 0
    for wave_filename in args.sound_files:
        assert_file_exists(wave_filename)
        samples, sample_rate = read_wave(wave_filename)
        duration = len(samples) / sample_rate
        total_duration += duration
        s = recognizer.create_stream()
        s.accept_waveform(sample_rate, samples)

        streams.append(s)

    recognizer.decode_streams(streams)
    results = [s.result.text for s in streams]
    end_time = time.time()
    print("Done!")

    for wave_filename, result in zip(args.sound_files, results):
        print(f"{wave_filename}\n{result}")
        print("-" * 10)

    elapsed_seconds = end_time - start_time
    rtf = elapsed_seconds / total_duration
    print(f"num_threads: {args.num_threads}")
    print(f"decoding_method: {args.decoding_method}")
    print(f"Wave duration: {total_duration:.3f} s")
    print(f"Elapsed time: {elapsed_seconds:.3f} s")
    print(
        f"Real time factor (RTF): {elapsed_seconds:.3f}/{total_duration:.3f} = {rtf:.3f}"
    )


if __name__ == "__main__":
    main()
