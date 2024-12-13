ip netns del A || true > /dev/null
ip netns del B || true > /dev/null
ip netns add A
ip netns add B
# For VLANs
ip -n A link add eth0 type veth peer name eth0 netns B
ip -n A link set eth0 up
ip -n B link set eth0 up
# For neighbours
ip -n A link add eth1 type veth peer name eth1 netns B
ip -n A link set eth1 up
ip -n B link set eth1 up

echo "[$(date)] Creating batch"

LOOPBACK_AND_VRF_COUNT=1500
GRE_COUNT=4
VLAN_COUNT=4000
exit 0

rm -f batch.ip

for i in $(seq $LOOPBACK_AND_VRF_COUNT); do
	ipv4="10.0.$(($i/256)).$(($i%256))"
	ipv6="1000::$i"

	cat >> batch.ip <<END
link add vrf_$i type vrf table $((10000+$i))
link set vrf_$i up
addr add dev vrf_$i 127.0.0.1/8 scope host
addr add dev vrf_$i ::1/128 scope host

link add lo$i type dummy
link set lo$i master vrf_$i up
addr add dev lo$i $ipv4/32
addr add dev lo$i $ipv6/128
END
done

for i in $(seq 1 $GRE_COUNT); do
	cat >> batch.ip <<END
link add gre-$i type gretap key $i.$i.$i.$i
link set gre-$i up
END
done

for j in $(seq $GRE_COUNT); do
	for i in $(seq $VLAN_COUNT); do
		ipv4="2$j.$(($i/256)).$(($i%256)).1"
		ipv6="200$j::$i:1"
		cat >> batch.ip <<END
link add vlan${j}_${i} link gre-$j type vlan id $(($i + 1))
link set vlan${j}_${i} up
addr add dev vlan${j}_${i} $ipv4/24
addr add dev vlan${j}_${i} $ipv6/120
END
done
done

echo "[$(date)] Executing batch"
mkdir -p up
cd up
perf record -F 1000 --call-graph dwarf ip -n A -batch ../batch.ip
cd ..
echo "[$(date)] Done"

echo "[$(date)] Flushing addresses"
mkdir -p down
cd down
perf record -F 1000 --call-graph dwarf ip -n A address flush scope global
cd ..
echo "[$(date)] Done"
