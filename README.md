# macos-video-optimizer

[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A macOS Finder Quick Action that compresses videos to H.264 MP4 with FFmpeg. A pre-flight sample estimates whether encoding is worthwhile before the workflow processes the full video.

### Features

- Samples the video at three points and estimates size reduction using the target encoding settings.
- Warns before encoding when expected savings are small, negative, or unavailable.
- Preserves the original and never overwrites an existing output.
- Checks the actual size after encoding and lets you delete or keep a result with little or no savings.
- Detects its own outputs by an embedded fingerprint to prevent repeat lossy encoding, including after files are renamed.
- Skips likely HDR and high-bit-depth video rather than converting it silently to 8-bit SDR.
- Creates per-run logs and offers **View Log** in the final dialog.

## Requirements

- macOS with Automator
- FFmpeg and `ffprobe`
- zsh

The script checks the standard Homebrew paths for Apple Silicon and Intel, then falls back to `PATH`.

## Installation

Install FFmpeg (for example, with `brew install ffmpeg`), then follow [the Finder Quick Action setup](docs/automator-setup.md).

## Usage

In Finder, right-click a video and choose **Quick Actions → Optimize Video**. The output is saved beside the original as `filename_optimised.mp4`; if that name exists, a numbered name is used.

The output profile is H.264 (`libx264`), CRF 24, medium preset, `yuv420p`, AAC at 96 kbps when audio is present, and MP4 faststart. Odd dimensions are padded to even dimensions.

## Safety and behavior

The pre-flight analysis samples approximately 10%, 50%, and 90% of the video. Estimated savings of 15% or more proceed automatically; smaller or negative savings default to Skip. If sampling fails, the workflow asks before continuing. These estimates are a heuristic and may differ from the full encode.

After encoding, results that are less than 5% smaller or larger than the source prompt whether to **Delete Result** or **Keep Result**. The original remains unchanged. HEVC sources may grow when converted to H.264 and may incur another lossy generation; the pre-flight check is intended to identify this risk.

Likely HDR or high-bit-depth sources, including common 10-bit / 12-bit, BT.2020, PQ, and HLG signals, are skipped. The workflow uses the first video and first audio stream; subtitles and data streams are not preserved.

## Logs

The final dialog can open the current run's log in TextEdit. The latest completed run is also available at:

```bash
cat "${TMPDIR%/}/video-optimizer-$(id -u)-latest.log"
```

## Limitations

This workflow targets ordinary 8-bit SDR video and simple Finder-based compatibility, not archival or mastering use. Sampled size estimates are not exact predictions of full-file results.

## License

macos-video-optimizer is released under the MIT License. See [LICENSE](LICENSE).
