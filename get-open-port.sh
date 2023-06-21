range=$(cat /proc/sys/net/ipv4/ip_local_port_range)
start_port=$(echo $range | cut -d' ' -f1)
end_port=$(echo $range | cut -d' ' -f2)
port=$(comm -23 <(seq $start_port $end_port | sort) <(ss -Htan | awk '{print $4}' | cut -d':' -f2 | sort -u) | shuf | head -n 1)
echo "{\"port\": \"$port\"}"