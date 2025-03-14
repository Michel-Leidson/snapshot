#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <choice>"
    echo "Select the network and node type for the snapshot:"
    echo "1) Heimdall Mainnet"
    echo "2) Bor Mainnet"
    echo "3) Heimdall Amoy"
    echo "4) Bor Amoy"
    echo "5) Erigon Amoy"
    exit 1
fi

choice=$1

case $choice in
    1)
        network="heimdall"
        node_type="mainnet"
        url="https://snap.stakepool.work/snapshots-stakepool/heimdall-mainnet.tar.zst"
        ;;
    2)
        network="bor"
        node_type="mainnet"
        url="https://snap.stakepool.work/snapshots-stakepool/bor-mainnet.tar.zst"
        ;;
    3)
        network="heimdall"
        node_type="amoy"
        url="https://snap.stakepool.work/snapshots-stakepool/heimdall-amoy.tar.zst"
        ;;
    4)
        network="bor"
        node_type="amoy"
        url="https://snap.stakepool.work/snapshots-stakepool/bor-amoy.tar.zst"
        ;;
    5)
        network="erigon"
        node_type="amoy"
        url="https://snap.stakepool.work/snapshots-stakepool/erigon-amoy.tar.zst"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Downloading snapshot for $network - $node_type..."
curl -L "$url" | zstd -d | tar -xf - > /dev/null

echo "Snapshot for $network - $node_type has been downloaded and extracted successfully!"
