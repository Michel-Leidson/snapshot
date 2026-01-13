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
snapshot_size=$(echo "$latest_snapshot" | awk '{print $3}')
snapshot_size_gb=$((snapshot_size / 1000000000))

url="https://snap.stakepool.work/snapshots-stakepool/$snapshot_file"

echo "================================================"
echo "⚠️  SPACE WARNING"
echo "================================================"
echo "Compressed size: ${snapshot_size_gb}GB"
echo "Your free space: $(df -BG . | awk 'NR==2 {print $4}')"
echo ""
echo "‼️  WITH 900GB FREE, YOU ARE AT THE LIMIT!"
echo "‼️  Decompressed size may be LARGER than 816GB!"
echo "================================================"
echo ""
read -p "Continue anyway? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled by user."
    exit 1
fi

echo "🚀 Starting simultaneous download+extraction (silent mode)..."
echo "Snapshot URL: $url"
echo "This may take several hours. Monitor with 'df -h .' in another terminal."

(
    while true; do
        free_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
        
        
        if [ "$free_gb" -lt 100 ]; then
            echo ""
            echo "🚨🚨🚨 DANGER: Only ${free_gb}GB remaining!"
            echo "🚨 Process may fail at any moment!"
            echo "🚨 Recommended to stop (Ctrl+C) and free space!"
        fi
        
       
        if [ "$free_gb" -lt 20 ]; then
            echo ""
            echo "💀💀💀 EMERGENCY: ONLY ${free_gb}GB REMAINING!"
            echo "💀 System may crash or data may be corrupted!"
            echo "💀 FORCE STOPPING in 10 seconds..."
            sleep 10
            pkill -f "wget.*$snapshot_file" 2>/dev/null || true
            exit 1
        fi
        sleep 30
    done
) &
monitor_pid=$!


trap "echo 'Interrupted by user. Stopping...'; kill $monitor_pid 2>/dev/null; exit 1" INT TERM


case "$snapshot_file" in
    *.tar.zst)
        echo "📦 Using zstd for decompression (silent)..."
        
       
        wget -c --retry-connrefused --timeout=60 \
             --read-timeout=300 --inet4-only \
             --show-progress \
             "$url" -O - | \
        zstdcat --memory=512M --quiet 2>/dev/null | \
        tar -xf - --warning=no-ignore-newer 2>/dev/null
        
        ;;
        
    *.tar.lz4)
        echo "📦 Using lz4 for decompression (silent)..."
        wget -c --retry-connrefused --timeout=60 \
             --read-timeout=120 --inet4-only \
             --show-progress \
             "$url" -O - | \
        lz4 -dc 2>/dev/null | \
        tar -xf - 2>/dev/null
        ;;
        
    *)
        echo "❌ Unknown snapshot format: $snapshot_file"
        kill $monitor_pid 2>/dev/null
        exit 1
        ;;
esac

kill $monitor_pid 2>/dev/null
echo ""
echo "================================================"
echo "✅ SUCCESS! Snapshot extracted completely!"
echo "✅ Final free space: $(df -BG . | awk 'NR==2 {print $4}')"
echo "================================================"
