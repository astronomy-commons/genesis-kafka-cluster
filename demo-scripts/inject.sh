#!/bin/bash
#
# inject.sh <topic> <interval_seconds> <chunk_size> [limit]
#
# Inject <chunk_size> number of alerts every <interval_seconds> into topic
# <topic>. Stop after injecting <limit>, if given.
#
# Assumes the alerts are in individual .avro files, in the current directory.
#

TOPIC=$1
INTERVAL=$2
CHUNKSIZE=$3
LIMIT=$4
shift
shift
shift

## Prepare the chunks for injection
echo -n "Preparing chunks ($CHUNKSIZE alerts each)..."
rm -f tmp-visit.*
ls | grep -E '\.avro$' | split -l $CHUNKSIZE - tmp-visit.
set -- tmp-visit.*
echo " done ($# chunks)."

if [[ -z $LIMIT ]]; then
	LIMIT=$#
fi

inject() {
	echo -n "[$(date)] injecting $1 to $TOPIC ... "
	T="$(date +%s)"

	# Split the input
	NPARTS=8
	rm -f tmp-splits.*
	split -n l/$NPARTS $1 tmp-splits.

	# Parallel-launch injectors
	for CHUNK in tmp-splits.*; do
		kafkacat -P -b localhost -t $TOPIC $(cat $CHUNK)  &
	done

	# wait for the injectors to finish
	wait

	T="$(($(date +%s)-T))"
	echo "done ($T seconds)"
}

sp="/-\|"
echo -n '  '

while /bin/true; do
	DT=$(( $INTERVAL - 1 - ($(date +%s) % $INTERVAL) ))
	if [[ $DT == 0 ]]; then
		printf "\b\b"
		inject $1
		shift
		sleep 1

		LIMIT=$(($LIMIT - 1))
		if [[ $LIMIT == 0 ]]; then
			break
		fi
	else
		printf "\b\b  \b\b$DT"
		sleep 0.5
	fi
done
