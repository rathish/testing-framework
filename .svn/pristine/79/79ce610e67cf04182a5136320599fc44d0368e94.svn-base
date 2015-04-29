#!/bin/ksh -p

########################################################################
# This function sets the varibles reqired for the rule script.
# 
# Parameters
#	$1 - The list of variable names required by the rule script
#	$2-till end - These are the parameters specified in data model
#		      The parameters should be in NAME=VALUE format
#
########################################################################

function arrange
{
	if [ $DEBUG ]; then set -x; PS4="ArgumentArranger: "; fi

	#Setting the list of required variables in an array
	set -A REQ_VARS `echo $1`

	shift

	#Setting the rest of the variables in an array
	set -A ALL_VARS `echo $*`

	for arg in ${REQ_VARS[@]};do
		
		for VAR in ${ALL_VARS[@]}; do
		
			if [[ "$arg" == "${VAR%=*}" ]]; then
		
				export ${VAR}
				break

			fi

		done
	done

	return 0
		
}
	
