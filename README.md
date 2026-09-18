# macOS Video Optimizer

A Finder Quick Action for macOS that uses FFmpeg to compress videos with **H.264 (libx264), CRF 24, preset medium, yuv420p, AAC 96 kbps, and faststart** — while trying to avoid unnecessary lossy re-encoding.

The workflow is designed for one-click use from Finder:

`Right-click video → Quick Actions → Optimize Video`

## Why this exists

Blindly re-encoding every video can waste time, increase file size, or reduce quality for little benefit. This workflow performs a short pre-flight analysis before the full encode.

It:

- detects files previously processed by Video Optimizer using embedded metadata
- samples the video at approximately 10%, 50%, and 90%
- encodes those samples with the actual CRF 24 target settings
- compares source video packet bytes with encoded video packet bytes
- estimates whether a full encode is likely to save meaningful space
- warns before re-encoding when the expected gain is small or negative
- keeps the original file unchanged
- never overwrites an existing output
- performs a post-encode size check
- keeps per-run logs and exposes them from the final dialog
- skips HDR / high-bit-depth video rather than silently converting it to SDR

## Requirements

- macOS
- Automator
- Homebrew FFmpeg with `ffprobe`
- zsh

Install FFmpeg:

```bash
brew install ffmpeg
```

The script checks the standard Homebrew locations:

- Apple Silicon: `/opt/homebrew/bin/ffmpeg`
- Intel: `/usr/local/bin/ffmpeg`

## Installation

See [docs/automator-setup.md](docs/automator-setup.md) for the full Finder Quick Action setup.

In short:

1. Open **Automator**.
2. Create a **Quick Action**.
3. Set:
   - Workflow receives current: **files or folders**
   - in: **Finder.app**
4. Add **Run Shell Script**.
5. Set:
   - Shell: `/bin/zsh`
   - Pass input: **as arguments**
6. Paste the contents of [video-optimizer.zsh](video-optimizer.zsh).
7. Save as **Optimize Video**.

## Encoding profile

```text
Video: H.264 / libx264
Preset: medium
CRF: 24
Pixel format: yuv420p
Audio: AAC 96 kbps
Container: MP4
Faststart: enabled
```

Odd video dimensions are padded to even dimensions so libx264 + yuv420p can encode safely.

## Pre-flight decision logic

The workflow measures three short samples using the same video encoding profile as the final output.

| Estimated result | Default behaviour |
|---|---|
| 15% or more smaller | Encode automatically |
| 5–15% smaller | Warn, default to Skip |
| Less than 5% smaller | Warn, default to Skip |
| Larger than source | Warn that output is expected to grow, default to Skip |
| Sample analysis unavailable | Fail closed: ask before continuing |

The estimate is a heuristic, not an exact prediction. Its purpose is to decide whether a full lossy encode is likely to be worthwhile.

## Post-encode safeguard

After encoding, the actual file sizes are compared.

If the result is less than 5% smaller — or is larger than the original — the workflow asks whether to **Delete Result** or **Keep Result**.

The original is never deleted or overwritten.

## Fingerprint protection

Outputs contain a metadata marker such as:

```text
VideoOptimizer:v2.3.3;profile=H264-CRF24-medium-AAC96
```

This lets the workflow recognise its own outputs even after they are renamed, preventing accidental repeated lossy encoding.

Legacy files matching the `*_optimised.mp4` naming pattern are also skipped as a secondary safeguard.

## HDR / high-bit-depth safety

The current profile is intentionally targeted at ordinary 8-bit SDR video.

The workflow skips inputs that appear to be HDR or high-bit-depth, including common signals such as:

- 10-bit / 12-bit pixel formats
- BT.2020 primaries
- PQ / SMPTE ST 2084
- HLG / ARIB STD-B67

This is deliberate: converting HDR video to 8-bit SDR correctly requires explicit colour-management or tone-mapping decisions.

## HEVC note

HEVC is often more bitrate-efficient than H.264. Converting a well-compressed HEVC source to H.264 CRF 24 can therefore **increase file size** while also introducing another lossy generation.

The pre-flight sampler is intended to catch this before the full encode and warn the user.

## Logs

Each run writes a unique log under the current macOS temporary directory.

The final dialog includes **View Log**, which opens the exact log for that run in TextEdit.

A convenience copy of the latest completed run is also maintained:

```bash
cat "${TMPDIR%/}/video-optimizer-$(id -u)-latest.log"
```

## Current version

**v2.3.3**

This version has been manually tested with:

- H.264 source videos where recompression produces substantial savings
- already compressed sources where recompression provides little or no benefit
- HEVC sources where H.264 conversion can increase size
- renamed Video Optimizer outputs detected through the metadata fingerprint
- audio and no-audio paths
- filenames containing spaces and Unicode
- odd video dimensions
- Finder Quick Action execution via Automator

## Limitations

- HDR / high-bit-depth conversion is intentionally not supported.
- Only the first video and first audio stream are used.
- Subtitle and data streams are not preserved.
- Pre-flight size estimates are based on sampled regions and can differ from the final full-file result.
- The workflow optimises for simple Finder-based compatibility, not archival or mastering workflows.

## License

MIT. See [LICENSE](LICENSE).
