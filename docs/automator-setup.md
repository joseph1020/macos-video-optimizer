# Automator setup

This project is intended to run as a Finder **Quick Action** on macOS.

## 1. Install FFmpeg

With Homebrew:

```bash
brew install ffmpeg
```

Verify:

```bash
which ffmpeg
which ffprobe
ffmpeg -version
```

Typical Homebrew paths are:

- Apple Silicon: `/opt/homebrew/bin/ffmpeg`
- Intel: `/usr/local/bin/ffmpeg`

## 2. Create the Quick Action

1. Open **Automator**.
2. Choose **Quick Action** as the document type.
3. At the top of the workflow set:
   - **Workflow receives current:** `files or folders`
   - **in:** `Finder.app`
4. Add the **Run Shell Script** action.
5. Configure it as:
   - **Shell:** `/bin/zsh`
   - **Pass input:** `as arguments`
6. Paste the complete contents of `video-optimizer.zsh` into the action.
7. Save the workflow as **Optimize Video**.

## 3. Use it from Finder

Select a video in Finder, then:

`Right-click → Quick Actions → Optimize Video`

The output is written beside the original as:

```text
filename_optimised.mp4
```

If that file already exists, the script uses:

```text
filename_optimised_2.mp4
filename_optimised_3.mp4
...
```

The original file is never overwritten or deleted.

## 4. How the pre-flight works

Before a full encode, the script samples approximately 10%, 50%, and 90% of the source video.

For each sample it:

1. measures the source video packet payload for that exact time range
2. encodes the same range using H.264 / CRF 24 / preset medium
3. measures the encoded video packet payload
4. combines the video estimate with the first audio stream's bitrate when available

The result is used as a heuristic:

- **15% or more smaller:** full encode starts automatically
- **5–15% smaller:** warning, default action is Skip
- **under 5% smaller:** warning, default action is Skip
- **expected to be larger:** warning, default action is Skip
- **sample analysis failure:** the script fails closed and asks before continuing

This is intentionally not an exact file-size predictor.

## 5. Post-encode safeguard

After a full encode, the script compares the actual source and output file sizes.

If the converted file is less than 5% smaller, or is larger than the original, it asks whether to:

- **Delete Result**
- **Keep Result**

The original remains unchanged either way.

## 6. Fingerprint protection

Outputs contain a format-level comment tag:

```text
VideoOptimizer:v2.3.3;profile=H264-CRF24-medium-AAC96
```

If that fingerprint is found later, the file is skipped even if its filename has been changed.

A legacy filename check for `*_optimised.mp4` and `*_optimised_N.mp4` is also retained.

## 7. Logs

Each run writes a unique log under the user's macOS temporary directory.

The final dialog includes **View Log**, which opens that exact run's log in TextEdit.

The latest completed run is also copied to:

```bash
"${TMPDIR%/}/video-optimizer-$(id -u)-latest.log"
```

Read it from Terminal with:

```bash
cat "${TMPDIR%/}/video-optimizer-$(id -u)-latest.log"
```

## 8. HDR / high-bit-depth video

The current output profile is 8-bit SDR H.264.

To avoid silently damaging HDR colour or brightness, the script skips likely HDR / high-bit-depth sources, including common indicators such as:

- 10-bit or 12-bit pixel formats
- BT.2020 colour primaries
- SMPTE ST 2084 / PQ transfer characteristics
- HLG / ARIB STD-B67

A future HDR-specific workflow should make an explicit preservation or tone-mapping decision rather than silently converting to SDR.

## 9. HEVC sources

HEVC can be substantially more bitrate-efficient than H.264.

A well-compressed HEVC input may therefore become larger when transcoded to H.264 CRF 24. The pre-flight analysis is designed to detect this and warn before the full encode.

## Troubleshooting

### Quick Action does nothing

Check that Automator is configured with:

- Shell: `/bin/zsh`
- Pass input: **as arguments**

Then confirm FFmpeg is installed.

### Find the latest log

```bash
cat "${TMPDIR%/}/video-optimizer-$(id -u)-latest.log"
```

### FFmpeg is installed but Automator cannot find it

The script explicitly checks both standard Homebrew paths before falling back to `command -v`.

### Output is skipped as already processed

Inspect the metadata:

```bash
ffprobe -v error \
  -show_entries format_tags=comment \
  -of default=noprint_wrappers=1:nokey=1 \
  "your-video.mp4"
```

If it contains `VideoOptimizer:`, the protection is working as intended.
