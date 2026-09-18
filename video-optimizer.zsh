#!/bin/zsh

# Video Optimizer v2.3.3
# macOS Finder Quick Action
#
# Target:
#   H.264 / libx264 / CRF 24 / preset medium / yuv420p
#   AAC 96 kbps when audio exists
#   MP4 + faststart
#
# Safety:
#   - embedded fingerprint prevents accidental re-encoding
#   - HDR / high-bit-depth sources are skipped
#   - odd dimensions are padded to even dimensions
#   - pre-flight compares source packet bytes vs encoded packet bytes
#   - sampling failure fails closed
#   - original is never overwritten or deleted

FINGERPRINT="VideoOptimizer:v2.3.3"
PROFILE_TAG="H264-CRF24-medium-AAC96"

SAMPLE_SECONDS=6
LOW_GAIN_PERCENT=5
AUTO_ENCODE_PERCENT=15

TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
TEMP_PREFIX="${TMP_ROOT}/video-optimizer-${UID}-$$"
LOG="${TEMP_PREFIX}.log"
LATEST_LOG="${TMP_ROOT}/video-optimizer-${UID}-latest.log"

cleanup() {
    local f
    for f in "${TEMP_PREFIX}"-sample-*.mp4(N); do
        /bin/rm -f -- "$f"
    done
}
trap cleanup EXIT INT TERM HUP

FIRST_LANGUAGE="$(
    /usr/bin/defaults read -g AppleLanguages 2>/dev/null |
    /usr/bin/awk -F'"' '/"/ {print $2; exit}'
)"

if [[ -z "$FIRST_LANGUAGE" ]]; then
    FIRST_LANGUAGE="$(
        /usr/bin/defaults read -g AppleLocale 2>/dev/null |
        /usr/bin/cut -d_ -f1
    )"
fi

if [[ "$FIRST_LANGUAGE" == ko* ]]; then
    UI_LANG="ko"
else
    UI_LANG="en"
fi

if [[ "$UI_LANG" == "ko" ]]; then
    TITLE="Video Optimizer"

    BTN_OK="확인"
    BTN_SKIP="건너뛰기"
    BTN_CONTINUE="계속 변환"
    BTN_KEEP="결과 유지"
    BTN_DELETE="결과 삭제"
    BTN_LOG="로그 보기"

    MSG_NO_INPUT="선택된 파일이 없습니다."
    MSG_NO_FFMPEG="ffmpeg 또는 ffprobe를 찾을 수 없습니다."

    MSG_ALREADY="이 영상은 Video Optimizer에서 이미 처리된 파일입니다."
    MSG_ALREADY_BODY="Video Optimizer가 이전에 처리한 결과 파일임을 확인했습니다.

불필요한 재인코딩과 추가 화질 저하를 방지하기 위해 다시 변환하지 않았습니다."

    MSG_HDR="HDR 또는 10-bit 영상이 감지되었습니다."
    MSG_HDR_BODY="현재 프로파일은 8-bit H.264 SDR(yuv420p)용입니다.

자동 변환하면 HDR 색상과 밝기가 손상될 수 있어 이 파일은 처리하지 않았습니다."

    MSG_SAMPLE_FAILED="사전 최적화 분석을 완료하지 못했습니다."
    MSG_SAMPLE_FAILED_BODY="예상 용량 변화를 신뢰할 수 없습니다.

분석 없이 전체 영상을 변환하시겠습니까?"

    MSG_LOW_EXPECTED="추가 최적화 효과가 매우 작을 것으로 예상됩니다."
    MSG_MODERATE_EXPECTED="추가 최적화 효과가 크지 않을 수 있습니다."
    MSG_EXPECTED_LARGER="변환하면 파일 용량이 오히려 커질 것으로 예상됩니다."

    MSG_LOSS_WARNING="다시 손실 압축하면 화질이 추가로 저하될 수 있습니다.

그래도 계속 변환하시겠습니까?"

    MSG_COMPLETE="영상 최적화가 완료되었습니다."
    MSG_FAILED="영상 최적화에 실패했습니다."

    MSG_ACTUAL_LARGER="변환된 파일의 용량이 원본보다 커졌습니다."
    MSG_ACTUAL_LARGER_BODY="원본 파일은 변경되지 않고 그대로 보관되어 있습니다.

이번 변환은 파일 용량이 증가했고 추가 손실 압축도 발생했으므로, 변환 결과 파일을 삭제하는 편이 좋습니다.

변환 결과 파일을 유지하시겠습니까?"

    MSG_LOW_ACTUAL="실제 용량 절감 효과가 매우 작습니다."
    MSG_LOW_ACTUAL_BODY="원본 파일은 변경되지 않고 그대로 보관되어 있습니다.

추가 손실 압축으로 인한 화질 저하에 비해 용량 절감 효과가 작습니다.

변환 결과 파일을 유지하시겠습니까?"

    LABEL_EXPECTED="예상 용량 감소"
    LABEL_ESTIMATED_RESULT="예상 결과"
    LABEL_RESULT="결과"
    LABEL_ENCODING_TIME="인코딩 시간"
    LABEL_COMPLETED="완료"
    LABEL_FAILED="실패"
    LABEL_SKIPPED="건너뜀"
    LABEL_FILE="파일"
    LABEL_FILES="파일 수"
    LABEL_LOG="로그"
else
    TITLE="Video Optimizer"

    BTN_OK="OK"
    BTN_SKIP="Skip"
    BTN_CONTINUE="Continue"
    BTN_KEEP="Keep Result"
    BTN_DELETE="Delete Result"
    BTN_LOG="View Log"

    MSG_NO_INPUT="No files were selected."
    MSG_NO_FFMPEG="ffmpeg or ffprobe could not be found."

    MSG_ALREADY="This video has already been processed by Video Optimizer."
    MSG_ALREADY_BODY="Video Optimizer identified this as a previously processed output.

To avoid unnecessary re-encoding and additional quality loss, it was not converted again."

    MSG_HDR="HDR or 10-bit video was detected."
    MSG_HDR_BODY="The current profile is designed for 8-bit H.264 SDR (yuv420p).

Automatic conversion could damage HDR colour and brightness, so this file was not processed."

    MSG_SAMPLE_FAILED="Pre-flight optimisation analysis could not be completed."
    MSG_SAMPLE_FAILED_BODY="The expected size change cannot be estimated reliably.

Do you want to encode the full video without the estimate?"

    MSG_LOW_EXPECTED="Very little additional size reduction is expected."
    MSG_MODERATE_EXPECTED="The additional size reduction may be limited."
    MSG_EXPECTED_LARGER="The converted file is expected to be larger."

    MSG_LOSS_WARNING="Another lossy encode may cause additional quality loss.

Do you want to continue?"

    MSG_COMPLETE="Video optimisation completed."
    MSG_FAILED="Video optimisation failed."

    MSG_ACTUAL_LARGER="The converted file is larger than the original."
    MSG_ACTUAL_LARGER_BODY="The original file has been kept unchanged.

Because this conversion increased the file size and introduced an additional lossy encode, deleting the converted result is recommended.

Do you want to keep the converted result?"

    MSG_LOW_ACTUAL="There was very little actual size reduction."
    MSG_LOW_ACTUAL_BODY="The original file has been kept unchanged.

The size reduction is small compared with the additional generation loss introduced by re-encoding.

Do you want to keep the converted result?"

    LABEL_EXPECTED="Estimated reduction"
    LABEL_ESTIMATED_RESULT="Estimated result"
    LABEL_RESULT="Result"
    LABEL_ENCODING_TIME="Encoding time"
    LABEL_COMPLETED="Completed"
    LABEL_FAILED="Failed"
    LABEL_SKIPPED="Skipped"
    LABEL_FILE="File"
    LABEL_FILES="Files"
    LABEL_LOG="Log"
fi

show_info() {
    local message="$1"
    /usr/bin/osascript - "$TITLE" "$message" "$BTN_OK" <<'APPLESCRIPT'
on run argv
    set dlgTitle to item 1 of argv
    set dlgMessage to item 2 of argv
    set okButton to item 3 of argv
    display dialog dlgMessage with title dlgTitle buttons {okButton} default button okButton with icon note
end run
APPLESCRIPT
}

show_error() {
    local message="$1"
    /usr/bin/osascript - "$TITLE" "$message" "$BTN_OK" <<'APPLESCRIPT'
on run argv
    set dlgTitle to item 1 of argv
    set dlgMessage to item 2 of argv
    set okButton to item 3 of argv
    display dialog dlgMessage with title dlgTitle buttons {okButton} default button okButton with icon stop
end run
APPLESCRIPT
}

ask_skip_continue() {
    local message="$1"
    /usr/bin/osascript - "$TITLE" "$message" "$BTN_SKIP" "$BTN_CONTINUE" <<'APPLESCRIPT'
on run argv
    set dlgTitle to item 1 of argv
    set dlgMessage to item 2 of argv
    set skipButton to item 3 of argv
    set continueButton to item 4 of argv
    set r to display dialog dlgMessage with title dlgTitle buttons {skipButton, continueButton} default button skipButton with icon caution
    return button returned of r
end run
APPLESCRIPT
}

ask_delete_keep() {
    local message="$1"
    /usr/bin/osascript - "$TITLE" "$message" "$BTN_DELETE" "$BTN_KEEP" <<'APPLESCRIPT'
on run argv
    set dlgTitle to item 1 of argv
    set dlgMessage to item 2 of argv
    set deleteButton to item 3 of argv
    set keepButton to item 4 of argv
    set r to display dialog dlgMessage with title dlgTitle buttons {deleteButton, keepButton} default button deleteButton with icon caution
    return button returned of r
end run
APPLESCRIPT
}

show_result_with_log() {
    local message="$1"
    local icon_type="${2:-note}"
    local selected_button

    selected_button="$(
        /usr/bin/osascript - "$TITLE" "$message" "$BTN_LOG" "$BTN_OK" "$icon_type" <<'APPLESCRIPT'
on run argv
    set dlgTitle to item 1 of argv
    set dlgMessage to item 2 of argv
    set logButton to item 3 of argv
    set okButton to item 4 of argv
    set iconType to item 5 of argv

    if iconType is "stop" then
        set r to display dialog dlgMessage with title dlgTitle buttons {logButton, okButton} default button okButton with icon stop
    else if iconType is "caution" then
        set r to display dialog dlgMessage with title dlgTitle buttons {logButton, okButton} default button okButton with icon caution
    else
        set r to display dialog dlgMessage with title dlgTitle buttons {logButton, okButton} default button okButton with icon note
    end if

    return button returned of r
end run
APPLESCRIPT
    )"

    if [[ "$selected_button" == "$BTN_LOG" ]]; then
        if [[ -f "$LOG" ]]; then
            /usr/bin/open -a TextEdit "$LOG"
        elif [[ -f "$LATEST_LOG" ]]; then
            /usr/bin/open -a TextEdit "$LATEST_LOG"
        fi
    fi
}

human_size() {
    local bytes="${1:-0}"

    if (( bytes >= 1073741824 )); then
        /usr/bin/awk -v b="$bytes" 'BEGIN {printf "%.2f GB", b/1073741824}'
    elif (( bytes >= 1048576 )); then
        /usr/bin/awk -v b="$bytes" 'BEGIN {printf "%.1f MB", b/1048576}'
    elif (( bytes >= 1024 )); then
        /usr/bin/awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}'
    else
        printf "%d B" "$bytes"
    fi
}

human_time() {
    local seconds="${1:-0}"

    if (( seconds >= 3600 )); then
        printf "%dh %dm %ds" \
            $(( seconds / 3600 )) \
            $(( (seconds % 3600) / 60 )) \
            $(( seconds % 60 ))
    elif (( seconds >= 60 )); then
        printf "%dm %ds" \
            $(( seconds / 60 )) \
            $(( seconds % 60 ))
    else
        printf "%ds" "$seconds"
    fi
}

format_estimated_change() {
    local value="${1:-0}"
    local magnitude

    if (( value < 0 )); then
        magnitude=$(( -value ))
        if [[ "$UI_LANG" == "ko" ]]; then
            printf "%s: 약 %d%% 증가" "$LABEL_ESTIMATED_RESULT" "$magnitude"
        else
            printf "%s: approximately %d%% larger" "$LABEL_ESTIMATED_RESULT" "$magnitude"
        fi
    elif (( value == 0 )); then
        if [[ "$UI_LANG" == "ko" ]]; then
            printf "%s: 의미 있는 용량 변화 없음" "$LABEL_ESTIMATED_RESULT"
        else
            printf "%s: no meaningful size change" "$LABEL_ESTIMATED_RESULT"
        fi
    else
        if [[ "$UI_LANG" == "ko" ]]; then
            printf "%s: 약 %d%% 감소" "$LABEL_EXPECTED" "$value"
        else
            printf "%s: approximately %d%%" "$LABEL_EXPECTED" "$value"
        fi
    fi
}

format_actual_change() {
    local value="${1:-0}"
    local magnitude

    if (( value < 0 )); then
        magnitude=$(( -value ))
        if [[ "$UI_LANG" == "ko" ]]; then
            printf "%s: %d%% 증가" "$LABEL_RESULT" "$magnitude"
        else
            printf "%s: %d%% larger" "$LABEL_RESULT" "$magnitude"
        fi
    elif (( value == 0 )); then
        if [[ "$UI_LANG" == "ko" ]]; then
            printf "%s: 용량 변화 없음" "$LABEL_RESULT"
        else
            printf "%s: no size change" "$LABEL_RESULT"
        fi
    else
        if [[ "$UI_LANG" == "ko" ]]; then
            printf "%s: %d%% 감소" "$LABEL_RESULT" "$value"
        else
            printf "%s: %d%% smaller" "$LABEL_RESULT" "$value"
        fi
    fi
}

packet_bytes() {
    local media_file="$1"

    "$FFPROBE" \
        -v error \
        -select_streams v:0 \
        -show_entries packet=size \
        -of csv=p=0 \
        "$media_file" 2>/dev/null |
    /usr/bin/awk '
        /^[0-9]+$/ { total += $1 }
        END { printf "%.0f", total }
    '
}

{
    echo "============================================================"
    echo "Video Optimizer v2.3.3"
    echo "Started: $(date)"
    echo "Arguments: $#"
    echo "First language: ${FIRST_LANGUAGE}"
    echo "UI language: ${UI_LANG}"
    echo "Fingerprint: ${FINGERPRINT}"
    echo "PID: $$"
    echo "Log: ${LOG}"
    echo "============================================================"
} > "$LOG"

if [[ -x "/opt/homebrew/bin/ffmpeg" ]]; then
    FFMPEG="/opt/homebrew/bin/ffmpeg"
    FFPROBE="/opt/homebrew/bin/ffprobe"
elif [[ -x "/usr/local/bin/ffmpeg" ]]; then
    FFMPEG="/usr/local/bin/ffmpeg"
    FFPROBE="/usr/local/bin/ffprobe"
else
    FFMPEG="$(command -v ffmpeg 2>/dev/null)"
    FFPROBE="$(command -v ffprobe 2>/dev/null)"
fi

if [[ ! -x "$FFMPEG" || ! -x "$FFPROBE" ]]; then
    echo "ERROR: ffmpeg or ffprobe not found" >> "$LOG"
    /bin/cp -f "$LOG" "$LATEST_LOG" 2>/dev/null
    show_error "$MSG_NO_FFMPEG"
    exit 1
fi

if (( $# == 0 )); then
    echo "ERROR: no input files" >> "$LOG"
    /bin/cp -f "$LOG" "$LATEST_LOG" 2>/dev/null
    show_error "$MSG_NO_INPUT"
    exit 1
fi

batch_start=$(date +%s)

success_count=0
failed_count=0
skipped_count=0

fingerprint_skip_count=0
legacy_filename_skip_count=0
hdr_skip_count=0
user_skip_count=0

total_original_bytes=0
total_output_bytes=0
total_encode_seconds=0

for input in "$@"; do
    echo >> "$LOG"
    echo "------------------------------------------------------------" >> "$LOG"
    echo "INPUT: $input" >> "$LOG"

    if [[ ! -f "$input" ]]; then
        echo "RESULT: INVALID_INPUT" >> "$LOG"
        (( skipped_count++ ))
        continue
    fi

    dir="${input:h}"
    filename="${input:t}"
    stem="${filename:r}"

    if [[ ! -w "$dir" ]]; then
        echo "RESULT: OUTPUT_DIRECTORY_NOT_WRITABLE" >> "$LOG"
        (( failed_count++ ))
        continue
    fi

    existing_comment="$(
        "$FFPROBE" \
            -v error \
            -show_entries format_tags=comment \
            -of default=noprint_wrappers=1:nokey=1 \
            "$input" 2>/dev/null
    )"

    echo "EXISTING COMMENT: ${existing_comment:-none}" >> "$LOG"

    if [[ "$existing_comment" == *"VideoOptimizer:"* ]]; then
        echo "DECISION: SKIP_FINGERPRINT" >> "$LOG"
        (( skipped_count++ ))
        (( fingerprint_skip_count++ ))
        continue
    fi

    if [[ "$stem" == *_optimised || "$stem" == *_optimised_<-> ]]; then
        echo "DECISION: SKIP_OUTPUT_FILENAME" >> "$LOG"
        (( skipped_count++ ))
        (( legacy_filename_skip_count++ ))
        continue
    fi

    duration="$(
        "$FFPROBE" \
            -v error \
            -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 \
            "$input" 2>/dev/null
    )"

    video_meta="$(
        "$FFPROBE" \
            -v error \
            -select_streams v:0 \
            -show_entries stream=codec_name,width,height,pix_fmt,color_space,color_primaries,color_transfer \
            -of default=noprint_wrappers=1 \
            "$input" 2>/dev/null
    )"

    video_codec="$(echo "$video_meta" | /usr/bin/awk -F= '/^codec_name=/{print $2; exit}')"
    width="$(echo "$video_meta" | /usr/bin/awk -F= '/^width=/{print $2; exit}')"
    height="$(echo "$video_meta" | /usr/bin/awk -F= '/^height=/{print $2; exit}')"
    pixel_format="$(echo "$video_meta" | /usr/bin/awk -F= '/^pix_fmt=/{print $2; exit}')"
    color_space="$(echo "$video_meta" | /usr/bin/awk -F= '/^color_space=/{print $2; exit}')"
    color_primaries="$(echo "$video_meta" | /usr/bin/awk -F= '/^color_primaries=/{print $2; exit}')"
    color_transfer="$(echo "$video_meta" | /usr/bin/awk -F= '/^color_transfer=/{print $2; exit}')"

    audio_codec="$(
        "$FFPROBE" \
            -v error \
            -select_streams a:0 \
            -show_entries stream=codec_name \
            -of default=noprint_wrappers=1:nokey=1 \
            "$input" 2>/dev/null
    )"

    audio_bitrate="$(
        "$FFPROBE" \
            -v error \
            -select_streams a:0 \
            -show_entries stream=bit_rate \
            -of default=noprint_wrappers=1:nokey=1 \
            "$input" 2>/dev/null
    )"

    if [[ -z "$video_codec" || -z "$duration" || "$duration" == "N/A" ]]; then
        echo "RESULT: NO_VALID_VIDEO_STREAM" >> "$LOG"
        (( skipped_count++ ))
        continue
    fi

    duration_int="$(
        /usr/bin/awk -v d="$duration" 'BEGIN {printf "%d", d}'
    )"

    original_bytes="$(
        /usr/bin/stat -L -f%z "$input" 2>/dev/null
    )"
    [[ -z "$original_bytes" ]] && original_bytes=0

    echo "VIDEO CODEC: ${video_codec:-unknown}" >> "$LOG"
    echo "RESOLUTION: ${width:-?}x${height:-?}" >> "$LOG"
    echo "PIXEL FORMAT: ${pixel_format:-unknown}" >> "$LOG"
    echo "COLOR SPACE: ${color_space:-unknown}" >> "$LOG"
    echo "COLOR PRIMARIES: ${color_primaries:-unknown}" >> "$LOG"
    echo "COLOR TRANSFER: ${color_transfer:-unknown}" >> "$LOG"
    echo "DURATION: ${duration}s" >> "$LOG"
    echo "AUDIO CODEC: ${audio_codec:-none}" >> "$LOG"
    echo "AUDIO BITRATE: ${audio_bitrate:-unknown}" >> "$LOG"
    echo "ORIGINAL BYTES: ${original_bytes}" >> "$LOG"

    hdr_or_high_bit=false

    if [[ "$pixel_format" == *10* ||
          "$pixel_format" == *12* ||
          "$color_transfer" == "smpte2084" ||
          "$color_transfer" == "arib-std-b67" ||
          "$color_primaries" == "bt2020" ]]; then
        hdr_or_high_bit=true
    fi

    if [[ "$hdr_or_high_bit" == true ]]; then
        echo "DECISION: SKIP_HDR_OR_HIGH_BIT_DEPTH" >> "$LOG"
        (( skipped_count++ ))
        (( hdr_skip_count++ ))
        continue
    fi

    sample_duration="$SAMPLE_SECONDS"
    if (( duration_int < 24 )); then
        sample_duration=3
    fi
    if (( duration_int < 10 )); then
        sample_duration=2
    fi

    pos1="$(
        /usr/bin/awk -v d="$duration" -v s="$sample_duration" '
        BEGIN {
            p=d*0.10-(s/2)
            if (p<0) p=0
            if (p+s>d) p=d-s
            if (p<0) p=0
            printf "%.6f", p
        }'
    )"

    pos2="$(
        /usr/bin/awk -v d="$duration" -v s="$sample_duration" '
        BEGIN {
            p=d*0.50-(s/2)
            if (p<0) p=0
            if (p+s>d) p=d-s
            if (p<0) p=0
            printf "%.6f", p
        }'
    )"

    pos3="$(
        /usr/bin/awk -v d="$duration" -v s="$sample_duration" '
        BEGIN {
            p=d*0.90-(s/2)
            if (p<0) p=0
            if (p+s>d) p=d-s
            if (p<0) p=0
            printf "%.6f", p
        }'
    )"

    end1="$(/usr/bin/awk -v p="$pos1" -v s="$sample_duration" 'BEGIN {printf "%.6f", p+s}')"
    end2="$(/usr/bin/awk -v p="$pos2" -v s="$sample_duration" 'BEGIN {printf "%.6f", p+s}')"
    end3="$(/usr/bin/awk -v p="$pos3" -v s="$sample_duration" 'BEGIN {printf "%.6f", p+s}')"

    echo "SAMPLE DURATION: ${sample_duration}s" >> "$LOG"
    echo "SAMPLE 1: ${pos1}-${end1}" >> "$LOG"
    echo "SAMPLE 2: ${pos2}-${end2}" >> "$LOG"
    echo "SAMPLE 3: ${pos3}-${end3}" >> "$LOG"

    source_sums="$(
        "$FFPROBE" \
            -v error \
            -select_streams v:0 \
            -show_entries packet=pts_time,size \
            -of compact=p=0:nk=0 \
            "$input" 2>/dev/null |
        /usr/bin/awk \
            -F'|' \
            -v p1="$pos1" -v e1="$end1" \
            -v p2="$pos2" -v e2="$end2" \
            -v p3="$pos3" -v e3="$end3" '
        {
            t=""
            s=""
            for (i=1; i<=NF; i++) {
                split($i,a,"=")
                if (a[1]=="pts_time") t=a[2]
                else if (a[1]=="size") s=a[2]
            }
            if (t=="" || s=="") next
            if (t+0 >= p1 && t+0 < e1) sum1 += s
            if (t+0 >= p2 && t+0 < e2) sum2 += s
            if (t+0 >= p3 && t+0 < e3) sum3 += s
        }
        END {
            printf "%.0f %.0f %.0f", sum1, sum2, sum3
        }'
    )"

    source1=0
    source2=0
    source3=0
    read source1 source2 source3 <<< "$source_sums"

    [[ "$source1" != <-> ]] && source1=0
    [[ "$source2" != <-> ]] && source2=0
    [[ "$source3" != <-> ]] && source3=0

    echo "SOURCE SAMPLE BYTES:" >> "$LOG"
    echo "  sample1=${source1}" >> "$LOG"
    echo "  sample2=${source2}" >> "$LOG"
    echo "  sample3=${source3}" >> "$LOG"

    sample_input_bits=0
    sample_output_bits=0
    valid_samples=0
    sample_index=0

    for sample_start in "$pos1" "$pos2" "$pos3"; do
        (( sample_index++ ))
        sample_file="${TEMP_PREFIX}-sample-${sample_index}.mp4"
        /bin/rm -f -- "$sample_file"

        case "$sample_index" in
            1) source_sample_bytes="$source1" ;;
            2) source_sample_bytes="$source2" ;;
            3) source_sample_bytes="$source3" ;;
        esac

        "$FFMPEG" \
            -nostdin \
            -hide_banner \
            -loglevel error \
            -ss "$sample_start" \
            -i "$input" \
            -t "$sample_duration" \
            -map '0:v:0' \
            -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
            -an \
            -c:v libx264 \
            -preset medium \
            -crf 24 \
            -pix_fmt yuv420p \
            "$sample_file" >> "$LOG" 2>&1

        sample_exit=$?

        if [[ $sample_exit -eq 0 &&
              -f "$sample_file" &&
              $source_sample_bytes -gt 0 ]]; then

            encoded_sample_bytes="$(packet_bytes "$sample_file")"
            [[ -z "$encoded_sample_bytes" ]] && encoded_sample_bytes=0

            if (( encoded_sample_bytes > 0 )); then
                (( sample_input_bits += source_sample_bytes * 8 ))
                (( sample_output_bits += encoded_sample_bytes * 8 ))
                (( valid_samples++ ))

                echo "SAMPLE ${sample_index}:" >> "$LOG"
                echo "  start=${sample_start}" >> "$LOG"
                echo "  source_packet_bytes=${source_sample_bytes}" >> "$LOG"
                echo "  encoded_packet_bytes=${encoded_sample_bytes}" >> "$LOG"
            else
                echo "SAMPLE ${sample_index}: ENCODED_PACKET_MEASUREMENT_FAILED" >> "$LOG"
            fi
        else
            echo "SAMPLE ${sample_index}: FAILED" >> "$LOG"
        fi

        /bin/rm -f -- "$sample_file"
    done

    sample_available=true

    if (( valid_samples == 0 ||
          sample_input_bits <= 0 ||
          sample_output_bits <= 0 )); then
        sample_available=false
        echo "PRE-FLIGHT: SAMPLE_ANALYSIS_UNAVAILABLE" >> "$LOG"
    else
        sample_total_seconds=$(( valid_samples * sample_duration ))

        estimated_audio_input_bits=0
        estimated_audio_output_bits=0

        if [[ -n "$audio_codec" ]]; then
            if [[ "$audio_bitrate" == <-> ]]; then
                estimated_audio_input_bits=$(( audio_bitrate * sample_total_seconds ))
            else
                estimated_audio_input_bits=$(( 96000 * sample_total_seconds ))
            fi

            estimated_audio_output_bits=$(( 96000 * sample_total_seconds ))
        fi

        estimated_input_bits=$(( sample_input_bits + estimated_audio_input_bits ))
        estimated_output_bits=$(( sample_output_bits + estimated_audio_output_bits ))

        estimated_reduction="$(
            /usr/bin/awk \
                -v before="$estimated_input_bits" \
                -v after="$estimated_output_bits" '
            BEGIN {
                if (before <= 0) print 0
                else printf "%.0f", ((before-after)/before)*100
            }'
        )"

        echo "PRE-FLIGHT:" >> "$LOG"
        echo "  valid_samples=${valid_samples}" >> "$LOG"
        echo "  video_input_bits=${sample_input_bits}" >> "$LOG"
        echo "  video_output_bits=${sample_output_bits}" >> "$LOG"
        echo "  audio_input_bits=${estimated_audio_input_bits}" >> "$LOG"
        echo "  audio_output_bits=${estimated_audio_output_bits}" >> "$LOG"
        echo "  estimated_input_bits=${estimated_input_bits}" >> "$LOG"
        echo "  estimated_output_bits=${estimated_output_bits}" >> "$LOG"
        echo "  estimated_reduction=${estimated_reduction}%" >> "$LOG"
    fi

    proceed=true

    if [[ "$sample_available" != true ]]; then
        decision_message="${LABEL_FILE}: ${filename}

${MSG_SAMPLE_FAILED}

${MSG_SAMPLE_FAILED_BODY}"

        choice="$(ask_skip_continue "$decision_message")"
        [[ "$choice" != "$BTN_CONTINUE" ]] && proceed=false

    elif (( estimated_reduction < 0 )); then
        estimate_text="$(format_estimated_change "$estimated_reduction")"

        decision_message="${LABEL_FILE}: ${filename}

${MSG_EXPECTED_LARGER}

${estimate_text}

${MSG_LOSS_WARNING}"

        choice="$(ask_skip_continue "$decision_message")"
        [[ "$choice" != "$BTN_CONTINUE" ]] && proceed=false

    elif (( estimated_reduction < LOW_GAIN_PERCENT )); then
        estimate_text="$(format_estimated_change "$estimated_reduction")"

        decision_message="${LABEL_FILE}: ${filename}

${MSG_LOW_EXPECTED}

${estimate_text}

${MSG_LOSS_WARNING}"

        choice="$(ask_skip_continue "$decision_message")"
        [[ "$choice" != "$BTN_CONTINUE" ]] && proceed=false

    elif (( estimated_reduction < AUTO_ENCODE_PERCENT )); then
        estimate_text="$(format_estimated_change "$estimated_reduction")"

        decision_message="${LABEL_FILE}: ${filename}

${MSG_MODERATE_EXPECTED}

${estimate_text}

${MSG_LOSS_WARNING}"

        choice="$(ask_skip_continue "$decision_message")"
        [[ "$choice" != "$BTN_CONTINUE" ]] && proceed=false
    fi

    if [[ "$proceed" != true ]]; then
        echo "DECISION: USER_SKIP" >> "$LOG"
        (( skipped_count++ ))
        (( user_skip_count++ ))
        continue
    fi

    echo "DECISION: FULL_ENCODE" >> "$LOG"

    output="${dir}/${stem}_optimised.mp4"

    if [[ -e "$output" ]]; then
        counter=2
        while [[ -e "${dir}/${stem}_optimised_${counter}.mp4" ]]; do
            (( counter++ ))
        done
        output="${dir}/${stem}_optimised_${counter}.mp4"
    fi

    echo "OUTPUT: $output" >> "$LOG"

    file_start=$(date +%s)

    if [[ -n "$audio_codec" ]]; then
        "$FFMPEG" \
            -nostdin \
            -hide_banner \
            -loglevel warning \
            -i "$input" \
            -map '0:v:0' \
            -map '0:a:0?' \
            -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
            -map_metadata 0 \
            -c:v libx264 \
            -preset medium \
            -crf 24 \
            -pix_fmt yuv420p \
            -c:a aac \
            -b:a 96k \
            -metadata comment="${FINGERPRINT};profile=${PROFILE_TAG}" \
            -movflags +faststart \
            "$output" >> "$LOG" 2>&1
    else
        "$FFMPEG" \
            -nostdin \
            -hide_banner \
            -loglevel warning \
            -i "$input" \
            -map '0:v:0' \
            -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
            -map_metadata 0 \
            -c:v libx264 \
            -preset medium \
            -crf 24 \
            -pix_fmt yuv420p \
            -an \
            -metadata comment="${FINGERPRINT};profile=${PROFILE_TAG}" \
            -movflags +faststart \
            "$output" >> "$LOG" 2>&1
    fi

    exit_code=$?
    file_end=$(date +%s)
    file_elapsed=$(( file_end - file_start ))
    (( total_encode_seconds += file_elapsed ))

    if [[ $exit_code -ne 0 || ! -f "$output" ]]; then
        echo "RESULT: FAILED" >> "$LOG"
        echo "ENCODE TIME: ${file_elapsed}s" >> "$LOG"

        [[ -f "$output" ]] && /bin/rm -f -- "$output"

        (( failed_count++ ))
        continue
    fi

    output_bytes="$(/usr/bin/stat -f%z "$output" 2>/dev/null)"
    [[ -z "$output_bytes" ]] && output_bytes=0

    actual_reduction="$(
        /usr/bin/awk \
            -v before="$original_bytes" \
            -v after="$output_bytes" '
        BEGIN {
            if (before <= 0) print 0
            else printf "%.0f", ((before-after)/before)*100
        }'
    )"

    echo "RESULT: SUCCESS" >> "$LOG"
    echo "ENCODE TIME: ${file_elapsed}s" >> "$LOG"
    echo "ORIGINAL BYTES: ${original_bytes}" >> "$LOG"
    echo "OUTPUT BYTES: ${output_bytes}" >> "$LOG"
    echo "ACTUAL REDUCTION: ${actual_reduction}%" >> "$LOG"

    if (( actual_reduction < LOW_GAIN_PERCENT )); then
        original_text="$(human_size "$original_bytes")"
        output_text="$(human_size "$output_bytes")"
        actual_text="$(format_actual_change "$actual_reduction")"

        if (( actual_reduction < 0 )); then
            post_message="${LABEL_FILE}: ${filename}

${MSG_ACTUAL_LARGER}

${original_text} → ${output_text}
${actual_text}

${MSG_ACTUAL_LARGER_BODY}"
        else
            post_message="${LABEL_FILE}: ${filename}

${MSG_LOW_ACTUAL}

${original_text} → ${output_text}
${actual_text}

${MSG_LOW_ACTUAL_BODY}"
        fi

        keep_choice="$(ask_delete_keep "$post_message")"

        if [[ "$keep_choice" != "$BTN_KEEP" ]]; then
            /bin/rm -f -- "$output"
            echo "POST-CHECK: OUTPUT_DELETED_BY_USER" >> "$LOG"
            (( skipped_count++ ))
            continue
        fi

        echo "POST-CHECK: LOW_GAIN_OUTPUT_KEPT" >> "$LOG"
    fi

    (( success_count++ ))
    (( total_original_bytes += original_bytes ))
    (( total_output_bytes += output_bytes ))
done

batch_end=$(date +%s)
batch_elapsed=$(( batch_end - batch_start ))
encode_time_text="$(human_time "$total_encode_seconds")"

{
    echo
    echo "============================================================"
    echo "Completed: $(date)"
    echo "SUCCESS: $success_count"
    echo "FAILED: $failed_count"
    echo "SKIPPED: $skipped_count"
    echo "FINGERPRINT SKIPPED: $fingerprint_skip_count"
    echo "LEGACY FILENAME SKIPPED: $legacy_filename_skip_count"
    echo "HDR/HIGH-BIT SKIPPED: $hdr_skip_count"
    echo "USER SKIPPED: $user_skip_count"
    echo "FULL ENCODE TIME: ${total_encode_seconds}s"
    echo "WALL TIME: ${batch_elapsed}s"
    echo "============================================================"
} >> "$LOG"

/bin/cp -f "$LOG" "$LATEST_LOG" 2>/dev/null

if (( success_count > 0 )); then
    original_text="$(human_size "$total_original_bytes")"
    output_text="$(human_size "$total_output_bytes")"

    total_reduction="$(
        /usr/bin/awk \
            -v before="$total_original_bytes" \
            -v after="$total_output_bytes" '
        BEGIN {
            if (before <= 0) print 0
            else printf "%.0f", ((before-after)/before)*100
        }'
    )"

    result_text="$(format_actual_change "$total_reduction")"

    final_message="${MSG_COMPLETE}

${original_text} → ${output_text}
${result_text}

${LABEL_ENCODING_TIME}: ${encode_time_text}

${LABEL_COMPLETED}: ${success_count}"

    if (( skipped_count > 0 )); then
        final_message="${final_message}
${LABEL_SKIPPED}: ${skipped_count}"
    fi

    if (( failed_count > 0 )); then
        final_message="${final_message}
${LABEL_FAILED}: ${failed_count}"
    fi

    show_result_with_log "$final_message" "note"

elif (( fingerprint_skip_count > 0 &&
        fingerprint_skip_count == skipped_count &&
        failed_count == 0 )); then

    final_message="${MSG_ALREADY}

${MSG_ALREADY_BODY}

${LABEL_FILES}: ${fingerprint_skip_count}"

    show_result_with_log "$final_message" "note"

elif (( legacy_filename_skip_count > 0 &&
        legacy_filename_skip_count == skipped_count &&
        failed_count == 0 )); then

    if [[ "$UI_LANG" == "ko" ]]; then
        final_message="Video Optimizer 출력 파일 형식과 일치하는 파일명입니다.

이전 버전에서 생성된 결과 파일일 가능성이 있어 재변환하지 않았습니다.

${LABEL_FILES}: ${legacy_filename_skip_count}"
    else
        final_message="The filename matches the Video Optimizer output pattern.

It may be an output created by an earlier version, so it was not re-encoded.

${LABEL_FILES}: ${legacy_filename_skip_count}"
    fi

    show_result_with_log "$final_message" "note"

elif (( hdr_skip_count > 0 &&
        hdr_skip_count == skipped_count &&
        failed_count == 0 )); then

    final_message="${MSG_HDR}

${MSG_HDR_BODY}

${LABEL_FILES}: ${hdr_skip_count}"

    show_result_with_log "$final_message" "caution"

elif (( failed_count > 0 )); then
    final_message="${MSG_FAILED}

${LABEL_FAILED}: ${failed_count}

${LABEL_LOG}:
${LOG}"

    show_result_with_log "$final_message" "stop"

elif (( skipped_count > 0 )); then
    if [[ "$UI_LANG" == "ko" ]]; then
        final_message="변환을 진행하지 않았습니다.

${LABEL_SKIPPED}: ${skipped_count}"
    else
        final_message="No conversion was performed.

${LABEL_SKIPPED}: ${skipped_count}"
    fi

    show_result_with_log "$final_message" "note"
fi

exit 0
