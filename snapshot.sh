#!/bin/bash
set -e
set -x

if [ $# -ne 3 ]; then
    echo "Usage: $0 <network> <node_type> <mode>"
    echo "Available options:"
    echo "  Network: heimdall, bor, erigon, avail"
    echo "  Node type: mainnet, amoy"
    echo "  Mode: stateless, full, archive, pruned"
    echo "Example: $0 bor mainnet stateless"
    exit 1
fi

network=$1
node_type=$2
mode=$3

snapshot_list_url="https://snap.stakepool.work/snapshots-stakepool/list_snapshots.txt"

case $mode in
    stateless)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep stateless)
        ;;
    full)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep -v stateless | grep -v pruned | grep -v archive)
        ;;
    archive)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep archive)
        ;;
    pruned)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep pruned)
        ;;
    *)
        echo "❌ Unknown mode: $mode"
        exit 1
        ;;
esac

if [ -z "$relevant_snapshots" ]; then
    echo "❌ No snapshots found for $network - $node_type - $mode."
    exit 1
fi

latest_snapshot=$(echo "$relevant_snapshots" | sort -k1,1r -k2,2r | head -n 1)
snapshot_file=$(echo "$latest_snapshot" | awk '{print $4}')
url="https://snap.stakepool.work/snapshots-stakepool/$snapshot_file"

echo "Downloading and extracting the latest snapshot for $network - $node_type - $mode..."
echo "Snapshot URL: $url"

case "$snapshot_file" in
    *.tar.zst)
        wget -c --retry-connrefused --timeout=60 --read-timeout=120 --inet4-only "$url" -O - | zstdcat | tar -xf -
        ;;
    *.tar.lz4)
        wget -c --retry-connrefused --timeout=60 --read-timeout=120 --inet4-only "$url" -O - | lz4 -dc | tar -xf -
        ;;
    *)
        echo "❌ Unknown snapshot format: $snapshot_file"
        exit 1
        ;;
esac

echo "✅ Snapshot for $network - $node_type - $mode has been downloaded and extracted successfully!"
