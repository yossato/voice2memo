#!/bin/bash

# Configuration 以下のパスを自分の環境に合わせて変更してください
AUDIO_DIR="/Users/USER/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
TRANSCRIBE_DIR="/Users/USER/..."
TEMP_DIR="/tmp/transcribe"  # 一時ファイル用ディレクトリ
# OpenAI whisper モデルファイルのパス
MODEL=/.../whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin

# 日時文字列を変換する関数
format_datetime() {
    local dt=$1
    local year=${dt:0:4}
    local month=${dt:4:2}
    local day=${dt:6:2}
    local hour=${dt:9:2}
    local minute=${dt:11:2}
    local second=${dt:13:2}
    
    # 月の先頭の0を削除
    month=${month#0}
    # 日の先頭の0を削除
    day=${day#0}
    
    echo "${year}年${month}月${day}日 ${hour}時${minute}分${second}秒"
}

# 一時ディレクトリの作成
mkdir -p "$TEMP_DIR"

# 音声ファイルの処理
for audio_file in "$AUDIO_DIR"/*.m4a; do
    basename=$(basename "$audio_file" .m4a)

    output_file="$TRANSCRIBE_DIR/${basename}"
    txt_file="$TRANSCRIBE_DIR/${basename}".txt
    
    if [ -f "${txt_file}" ]; then
        continue
    fi

    echo "Processing: $audio_file"
    
    wav_file="$TEMP_DIR/$basename.wav"
    ffmpeg -i "$audio_file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_file"
    
    whisper-cli "$wav_file" -of "$output_file" --model $MODEL --language ja -otxt

    rm "$wav_file"

    # translate newline to \r for Notes app.
    if [ -f "${txt_file}" ]; then
        tr '\n' '\r' < "${txt_file}" > "${txt_file}.tmp" && mv "${txt_file}.tmp" "${txt_file}"
    fi

    if [ -f "${txt_file}" ]; then
        datetime_part=$(echo "$basename" | grep -o "^[0-9]\{8\} [0-9]\{6\}")
        content=$(cat "$txt_file")
        if [ ! -z "$datetime_part" ]; then
            formatted_date=$(format_datetime "$datetime_part")
            content=$(echo -e "$content" $'\n\r\n\r\t' "録音日時:" "$formatted_date" )
        fi

        title=$(echo "$content" | head -n 1 | sed 's/"/\\"/g')
        body=$(echo "$content" | tail -n +2 | tr '\n' '\r' | sed 's/"/\\"/g')
        osascript <<EOF
tell application "Notes"
    tell account "iCloud"
        make new note with properties {name:"${title}", body:"${body}"}
    end tell
end tell
EOF
        
        echo "Note created: $title"
    fi
done

echo "All processing completed"
