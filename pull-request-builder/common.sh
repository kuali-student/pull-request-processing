#!/usr/bin/env bash
#
# common.sh
#
# common shell fuctions for the pull-request-builder
#


# only print out the message if we are in debug mode.
# debug mode only if debug exists and is 1
debug () {

	MSG=$1

	if test -n "$DEBUG"
	then

		if test 1 -eq $DEBUG
		then
			echo $MSG

		fi
	fi

}

# EOF
