#!/bin/bash

# Configuration 以下のパスを自分の環境に合わせて変更してください
AUDIO_DIR="/Users/yoshiaki/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
TRANSCRIBE_DIR="/Users/yoshiaki/Documents/transcribes"
TEMP_DIR="/tmp/transcribe"  # 一時ファイル用ディレクトリ
# WhisperKit 用モデルファイルのパス（※環境に合わせて変更してください）
MODEL="/Users/yoshiaki/Projects/whisperkit/Models/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB"

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
mkdir -p "$TRANSCRIBE_DIR"

# 音声ファイルの処理
for audio_file in "$AUDIO_DIR"/*.m4a; do
    basename=$(basename "$audio_file" .m4a)
    txt_file="$TRANSCRIBE_DIR/${basename}.txt"
    
    # すでに文字起こし済みならスキップ
    if [ -f "${txt_file}" ]; then
        continue
    fi

    echo "Processing: $audio_file"
    
    # ffmpeg で wav 形式に変換（16kHz, モノラル）
    wav_file="$TEMP_DIR/$basename.wav"
    ffmpeg -i "$audio_file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_file" -y >/dev/null 2>&1
    
    # WhisperKit CLI で文字起こし
    # ここで sed によってログ出力部分（例: "Building…", "Build of product…", "[…]" で始まる行）を削除
    transcript=$(whisperkit-cli transcribe --audio-path "$wav_file" --model-path "$MODEL" --language ja 2>&1 | \
        sed -E '/^(Building|Build of product|\[)/d')
    
    # 不要な空行があれば削除（必要に応じて）
    transcript=$(echo "$transcript" | sed '/^\s*$/d')
    
    # キャプチャした文字起こし結果をテキストファイルに保存
    echo "$transcript" > "$txt_file"
    
    # 一時wavファイルを削除
    rm "$wav_file"

    # Notes アプリ用に改行コードを変換（LF -> CR）
    if [ -f "${txt_file}" ]; then
        tr '\n' '\r' < "${txt_file}" > "${txt_file}.tmp" && mv "${txt_file}.tmp" "${txt_file}"
    fi

    # ファイル名に含まれる日時情報を抽出してフォーマット（例: 20230415 123456）
    if [ -f "${txt_file}" ]; then
        datetime_part=$(echo "$basename" | grep -o "^[0-9]\{8\} [0-9]\{6\}")
        content=$(cat "$txt_file")
        if [ ! -z "$datetime_part" ]; then
            formatted_date=$(format_datetime "$datetime_part")
            # 録音日時の情報を末尾に追記
            content=$(echo -e "$content" $'\n\r\n\r\t' "録音日時:" "$formatted_date")
            echo "$content" > "$txt_file"
        fi

        # タイトル（先頭行）と本文（2行目以降）を作成して Notes アプリへ送信
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
