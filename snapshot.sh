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


available_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
required_with_buffer=$((snapshot_size_gb * 15 / 10)) 

echo "================================================"
echo "⚠️  SPACE ANALYSIS"
echo "================================================"
echo "Compressed snapshot size: ${snapshot_size_gb}GB"
echo "Your free space: ${available_gb}GB"
echo "Recommended free space: ${required_with_buffer}GB (1.5x compressed size)"
echo ""


if [ "$available_gb" -lt "$snapshot_size_gb" ]; then
    echo "❌❌❌ CRITICAL: NOT ENOUGH SPACE!"
    echo "❌ You need at least ${snapshot_size_gb}GB for compressed file."
    echo "❌ Consider using 'pruned' or 'stateless' mode."
    exit 1
    
elif [ "$available_gb" -lt "$required_with_buffer" ]; then
    echo "‼️  WARNING: YOU ARE AT THE LIMIT!"
    echo "‼️  With ${available_gb}GB free for ${snapshot_size_gb}GB compressed file."
    echo "‼️  Decompressed size may be 1.2x to 1.5x larger!"
    echo "‼️  Risk of failure if decompressed > ${available_gb}GB"
    
else
    echo "✅ SPACE OK: Sufficient space available."
    echo "✅ ${available_gb}GB free for ${snapshot_size_gb}GB compressed file."
fi

echo "================================================"
echo ""
read -p "Continue anyway? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled by user."
    exit 1
fi

echo "🚀 Starting simultaneous download+extraction..."
echo "Snapshot URL: $url"
echo "Estimated time: $((snapshot_size_gb / 50))-$(($snapshot_size_gb / 20)) hours at 20-50MB/s"
echo "Monitor with 'df -h .' in another terminal."


(
  
    warning_limit=$((snapshot_size_gb / 8)) 
    if [ "$warning_limit" -lt 50 ]; then
        warning_limit=50  
    fi
    
    emergency_limit=$((snapshot_size_gb / 20)) 
    if [ "$emergency_limit" -lt 20 ]; then
        emergency_limit=20  
    fi
    
    echo "Space monitor: Warning at ${warning_limit}GB, Emergency at ${emergency_limit}GB"
    
    while true; do
        free_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
        
        
        if [ "$free_gb" -lt "$warning_limit" ]; then
            echo ""
            echo "🚨 WARNING: Only ${free_gb}GB remaining!"
            echo "🚨 Recommended to pause and check progress."
        fi
        
        if [ "$free_gb" -lt "$emergency_limit" ]; then
            echo ""
            echo "💀 EMERGENCY: ONLY ${free_gb}GB REMAINING!"
            echo "💀 System may crash or corrupt data!"
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
        echo "📦 Using zstd for decompression..."
        
        wget -c --retry-connrefused --timeout=60 \
             --read-timeout=300 --inet4-only \
             --show-progress \
             "$url" -O - | \
        zstdcat --memory=512M --quiet 2>/dev/null | \
        tar -xf - --warning=no-ignore-newer 2>/dev/null
        
        ;;
        
    *.tar.lz4)
        echo "📦 Using lz4 for decompression..."
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
echo "✅ Time elapsed: $SECONDS seconds ($(($SECONDS / 3600))h $((($SECONDS % 3600) / 60))m)"
echo "================================================"
