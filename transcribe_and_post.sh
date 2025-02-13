#!/bin/bash

# Configuration 以下のパスを自分の環境に合わせて変更してください
AUDIO_DIR="/Users/yoshiaki/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
TRANSCRIBE_DIR="/Users/yoshiaki/Documents/transcribes"
TEMP_DIR="/tmp/transcribe"  # 一時ファイル用ディレクトリ
# WhisperKit 用モデルファイルのパス（※環境に合わせて変更してください）
MODEL="/Users/yoshiaki/Projects/whisperkit/Models/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB"

# 日時文字列を見やすい形式に変換する関数（例："20230415 123456" → "2023年4月15日 12時34分56秒"）
format_datetime() {
    local dt=$1
    local year=${dt:0:4}
    local month=${dt:4:2}
    local day=${dt:6:2}
    local hour=${dt:9:2}
    local minute=${dt:11:2}
    local second=${dt:13:2}
    
    # 先頭の0を削除
    month=${month#0}
    day=${day#0}
    
    echo "${year}年${month}月${day}日 ${hour}時${minute}分${second}秒"
}

# 必要なディレクトリの作成
mkdir -p "$TEMP_DIR" "$TRANSCRIBE_DIR"

# 各音声ファイルについて処理
for audio_file in "$AUDIO_DIR"/*.m4a; do
    basename=$(basename "$audio_file" .m4a)
    # 出力先ファイル（Notes 登録用テキスト）※すでに処理済みならスキップ
    txt_file="$TRANSCRIBE_DIR/${basename}.txt"
    if [ -f "$txt_file" ]; then
        continue
    fi

    echo "Processing: $audio_file"
    
    # 1. ffmpeg で wav 形式（16kHz, モノラル）に変換
    wav_file="$TEMP_DIR/${basename}.wav"
    ffmpeg -i "$audio_file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_file" -y >/dev/null 2>&1
    
    # 2. 一時作業ディレクトリで whisperkit-cli を実行
    #    brew でインストール済みのグローバルな whisperkit-cli を利用するため、
    #    カレントディレクトリを一時ディレクトリに変更して実行します。
    pushd "$TEMP_DIR" >/dev/null
    whisperkit-cli transcribe --audio-path "$wav_file" --model-path "$MODEL" --language ja --report
    popd >/dev/null

    # whisperkit-cli の実行により、$TEMP_DIR に
    #    ${basename}.srt と ${basename}.json
    # が出力されるはずです。ここでは SRT ファイルを利用します。
    srt_file="$TEMP_DIR/${basename}.srt"
    if [ -f "$srt_file" ]; then
        # 3. SRT ファイルから不要な番号やタイムスタンプ行を削除し、
        #    さらに各行中のタグ（<|...|> で囲まれた部分）を削除する
        transcript=$(sed -E '/^[0-9]+$/d; /^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3} -->/d' "$srt_file" | \
                     sed -E 's/<\|[^|]+\|>//g' | \
                     sed -E '/^[[:space:]]*$/d')
        
        # 4. 改行コードを変換（LF -> CR） Notes アプリ用
        processed_transcript=$(echo "$transcript" | tr '\n' '\r')
        echo "$processed_transcript" > "$txt_file"
    else
        echo "SRT file not found for $basename" >&2
        rm "$wav_file"
        continue
    fi

    # 5. （オプション）ファイル名に日時情報が含まれている場合、読みやすい日時も追記
    datetime_part=$(echo "$basename" | grep -o "^[0-9]\{8\} [0-9]\{6\}")
    content=$(cat "$txt_file")
    if [ ! -z "$datetime_part" ]; then
        formatted_date=$(format_datetime "$datetime_part")
        content=$(echo -e "$content" $'\n\r\n\r\t' "録音日時:" "$formatted_date")
        echo "$content" > "$txt_file"
    fi

    # 6. AppleScript を利用して Notes アプリにメモを作成
    #    ※タイトルは最初の行、本文は残りの行として扱います
    title=$(echo "$content" | head -n 1 | sed 's/"/\\"/g')
    body=$(echo "$content" | tail -n +2 | sed 's/"/\\"/g')
    osascript <<EOF
tell application "Notes"
    tell account "iCloud"
        make new note with properties {name:"${title}", body:"${body}"}
    end tell
end tell
EOF
    echo "Note created: $title"
    
    # 7. 後処理：一時ファイル（wav, srt, json）を削除
    json_file="$TEMP_DIR/${basename}.json"
    
    rm "$wav_file"
    rm "$srt_file"
    rm "$json_file"
done

echo "All processing completed"
