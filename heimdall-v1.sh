#!/bin/bash

# Argumentos
SNAP_NAME="$1"
CHAIN="$2"

if [ -z "$SNAP_NAME" ] || [ -z "$CHAIN" ]; then
  echo "[✗] Uso: $0 <snapshot-name> <chain-name>"
  echo "Exemplo: $0 heimdall-v1 mainnet"
  exit 1
fi

DOWNLOAD_URL="https://snap.stakepool.work/snapshots-stakepool/${SNAP_NAME}-download-list.txt"
ORIGINAL_LIST="${SNAP_NAME}-download-list.txt"
WORK_LIST="tmp-download-list.txt"
trap 'rm -f "$WORK_LIST" missing.txt' EXIT
MAX_RETRIES=5
RETRY=1

echo "[*] Downloading file list..."
if ! curl -fsSL "$DOWNLOAD_URL" -o "$ORIGINAL_LIST"; then
  echo "[✗] Failed to download the file list from: $DOWNLOAD_URL"
  exit 1
fi

cp "$ORIGINAL_LIST" "$WORK_LIST"

download_batch() {
  echo "[*] Starting parallel download with aria2c..."
  cat "$WORK_LIST" | xargs -P64 -I{} bash -c '
    url="{}"
    filepath="${url#https://snap.stakepool.work/snapshots-stakepool/data/}"
    dir="data/$(dirname "$filepath")"
    mkdir -p "$dir"
    aria2c -s16 -x16 --file-allocation=none --timeout=30 --max-tries=3 -d "$dir" -o "$(basename "$filepath")" "$url" 
  '
}

recheck_missing() {
  echo "[*] Verifying missing files after attempt $RETRY..."
  > missing.txt
  while read url; do
    filepath="${url#https://snap.stakepool.work/snapshots-stakepool/data/}"
    if [ ! -f "data/$filepath" ]; then
      echo "$url" >> missing.txt
    fi
  done < "$WORK_LIST"

  if [ -s missing.txt ]; then
    echo "[!] Still missing $(wc -l < missing.txt) files."
    mv missing.txt "$WORK_LIST"
    return 1
  else
    echo "[✓] All files downloaded successfully!"
    rm -f "$WORK_LIST" missing.txt
    return 0
  fi
}

while [ $RETRY -le $MAX_RETRIES ]; do
  echo
  echo "=============================="
  echo "[*] Attempt $RETRY of $MAX_RETRIES"
  echo "=============================="

  download_batch

  if recheck_missing; then
    echo "[✓] Completed successfully after $RETRY attempt(s)."
    exit 0
  fi

  ((RETRY++))
done

echo "[✗] Some files are still missing after $MAX_RETRIES attempts."
echo "You can manually check: $WORK_LIST"
exit 1
