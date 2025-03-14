#!/bin/bash
set -x  

if [ $# -ne 2 ]; then
    echo "Usage: $0 <network> <node_type>"
    echo "Available options:"
    echo "  Network: heimdall, bor, erigon"
    echo "  Node type: mainnet, amoy"
    echo "Example: $0 heimdall mainnet"
    exit 1
fi

network=$1
node_type=$2

case "$network-$node_type" in
    "heimdall-mainnet")
        url="https://snap.stakepool.work/snapshots-stakepool/heimdall-mainnet.tar.zst"
        ;;
    "bor-mainnet")
        url="https://snap.stakepool.work/snapshots-stakepool/bor-mainnet.tar.zst"
        ;;
    "heimdall-amoy")
        url="https://snap.stakepool.work/snapshots-stakepool/heimdall-amoy.tar.zst"
        ;;
    "bor-amoy")
        url="https://snap.stakepool.work/snapshots-stakepool/bor-amoy.tar.zst"
        ;;
    "erigon-amoy")
        url="https://snap.stakepool.work/snapshots-stakepool/erigon-amoy.tar.zst"
        ;;
    *)
        echo "Invalid combination of network and node type. Exiting."
        exit 1
        ;;
esac

echo "Downloading and extracting snapshot for $network - $node_type..."


wget -c --tries=5 --waitretry=10 --retry-connrefused --timeout=30 -O - "$url" | zstd -d | tar -xf -

if [ $? -eq 0 ]; then
    echo "✅ Snapshot for $network - $node_type has been downloaded and extracted successfully!"
else
    echo "❌ Failed to download or extract the snapshot. Please check the URL and try again."
    exit 1
fi
