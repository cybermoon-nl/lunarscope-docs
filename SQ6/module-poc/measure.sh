#!/usr/bin/env bash
# Performance measurement for the SQ5 module-interface PoC

AGENT="./target/release/lunarscope-agent"
CONFIG="config.toml"
RUNS=10

echo "╔══════════════════════════════════════╗"
echo "║  SQ5 PoC – performance measurement  ║"
echo "╚══════════════════════════════════════╝"
echo ""

SIZE=$(du -sh "$AGENT" | cut -f1)
echo "  Binary size : $SIZE"

echo "  Timing ($RUNS runs)..."
TOTAL=0
for i in $(seq 1 $RUNS); do
    START=$(date +%s%3N)
    "$AGENT" "$CONFIG" > /dev/null 2>&1
    END=$(date +%s%3N)
    TOTAL=$((TOTAL + END - START))
done
AVG=$(echo "scale=1; $TOTAL / $RUNS" | bc)
echo "  Average wall time : ${AVG} ms"

PEAK=$(python3 -c "
import subprocess, time, re
proc = subprocess.Popen(['$AGENT', '$CONFIG'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
max_rss = 0
while proc.poll() is None:
    try:
        with open(f'/proc/{proc.pid}/status') as f:
            for line in f:
                if 'VmPeak' in line:
                    val = int(re.search(r'\d+', line).group())
                    if val > max_rss: max_rss = val
    except: pass
    time.sleep(0.0001)
proc.wait()
print(max_rss)
" 2>/dev/null)

if [ -n "$PEAK" ] && [ "$PEAK" -gt 0 ]; then
    MB=$(echo "scale=1; $PEAK / 1024" | bc)
    echo "  Peak memory (VmPeak) : ${PEAK} kB  (${MB} MB)"
fi
echo ""
echo "  Done."
