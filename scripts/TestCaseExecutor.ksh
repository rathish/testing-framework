#!/bin/ksh -p
date_stamp=`date +%d%m%y`

##########################################################################
#
#
##########################################################################
Usage()
{
cat <<END

	Synopsis:
		$SCRIPT -f <configuration file> -d <bebug level> 

	Description:
		PROV test executor script

	Options:
		-f	Testcase Cofiguration file
		-d	Debugger Log
			0 - Enable Debugger
			1 - Disable Debugger
		-?	Help message

	Stderr:
		The standard error is used for diagnostic messages.

	Expected Configurations:

		SCRIPT_HOME	- PROV System Test installation directory
		CONF		- System Test configuration directory (default: $SCRIPT_HOME/conf)
		TESTGROUPCONF	- Test Group Configuration
		DATAMODELCONF	- DataModel Configuration
		SCRIPTS		- SystemTest scripts (default: $SCRIPT_HOME/scripts)
		REPORTS_DIR	- Report directory (default: $SCRIPT_HOME/REPORT)
		TESTDATA	- Testdata directory

	Exit Status:
		0 - on success
		1 - on error
END
}

##############################################################################################
# This function is used to get the list of rules, global rules and config files to be 
# run/sourced for the test group execution.
#
# Variables used
#	$GROUPNAME, $TESTGROUPCONF
#
##############################################################################################
GetGroupValues()
{
	if [ $DEBUG ]; then set -x; fi
	
	set -A RULES `sed -n "/^TEST_GROUP:${GROUPNAME}/,/^END_GROUP$/p" $TESTGROUPCONF | \
			grep "^RULE:" | awk -F: '{print $2}'`

	set -A CONFIGS `sed -n "/^TEST_GROUP:${GROUPNAME}/,/^END_GROUP$/p" $TESTGROUPCONF | \
			grep "^CONFIG:" | awk -F: '{print $2}'`
	
	set -A TEST_GROUP_RULES `sed -n "/^TEST_GROUP:${GROUPNAME}/,/^END_GROUP$/p" $TESTGROUPCONF | \
			grep "[!#]TEST_GROUP_RULE:" | awk -F: '{print $2}'`

}

##############################################################################################
#
# This function is used to source the config variables and run the initialize funtion for
# the global rules
#
##############################################################################################
GlobalInitialize()
{
	if [ $DEBUG ]; then set -x; fi

	# Sourcing Global config variables
	#
	grep "^GLOBAL_CONFIG:" $TESTGROUPCONF |awk -F: '{print $2}' |\
	while read glbconf
	do
		. ${CONF}/$glbconf

		if [ $? -ne 0 ]; then
			print "Could not source varibles from $glbconf file"
			return 1
		fi
	done

	# Initializing global rules
	#
	grep "^GLOBAL_RULE:" $TESTGROUPCONF |awk -F: '{print $2}' |\
	while read glbrule
	do
		. ${RULES_DIR}/$glbrule
		initialize

		if [ $? -ne 0 ]; then
			print "Could not initialize global rule $glbrule "
			return 1
		fi
	done
}

##############################################################################################
# This function is used to source the config variables and run the initialize funtion for
# rules and global rules
#
#
##############################################################################################
GlobalCleanup()
{
	if [ $DEBUG ]; then set -x; fi

	#Cleaning up global rules
	grep "^GLOBAL_RULE:" $TESTGROUPCONF |awk -F: '{print $2}' |\
	while read glbrule
	do
		. ${RULES_DIR}/$glbrule
		cleanup

		if [ $? -ne 0 ]; then
			print "Could not cleanup global rule $glbrule "
			return 1
		fi
	done
}



##############################################################################################
# This function is used to source the config variables and run the initialize funtion for 
# rules and test group rules
#
# Variables used
#       $CONFIGS, $TEST_GROUP_RULES, $RULES
#
##############################################################################################
InitialzeAll()
{
	if [ $DEBUG ]; then set -x; fi
	
	# Initialization for Test Case run
	#
	for conf in ${CONFIGS[@]}
	do
		. ${CONF}/$conf
		if [ $? -ne 0 ]; then
			report "Could not source varibles from $conf file"
			return 1
		fi
	done

	# Initializing the Global rules
	#
	for tgrule in ${TEST_GROUP_RULES[@]}
	do
		. ${RULES_DIR}/$tgrule
		initialize

		if [ $? -ne 0 ]; then
			report "Global rule $tgrule initialization failed"
			message=`errorLog 2>&1`
			report $message
			return 1
		fi
	done

	# Initialization of  the rules pertaining to the Test Group
	#
	for rule in ${RULES[@]}
	do
		. ${RULES_DIR}/$rule
		initialize
		
		if [ $? -ne 0 ]; then
			report "Rule $rule initialization failed"
			message=`errorLog 2>&1`
			report $message
			return 1
		fi
	done
}

#################################################################
# This function is used to run the execute funtion for the rules
#
# Variables used
#	$RULES
#
#################################################################
ExecuteAll()
{
	if [ $DEBUG ]; then set -x; fi

	for rule in ${RULES[@]}
	do
		. ${RULES_DIR}/$rule
		execute $*
		if [ $? -ne 0 ]; then
			report "Rule $rule execute failed"
			message=`errorLog 2>&1`
			report $message
			return 1
		fi
	done
}

#################################################################
# This function is used to run the cleanup funtion for the rules
#
# Variables used
#       $TEST_GROUP_RULES, $RULES
#
#################################################################
FinishAll()
{
	if [ $DEBUG ]; then set -x; fi

	for rule in ${RULES[@]};do

		. ${RULES_DIR}/$rule
		message=`finish`

		if [ $? -ne 0 ]; then
			report "Rule $rule cleanup failed"
			report $message
			return 1
		fi
	done

	# Finishing the Global rules
	#
	for tgrul in ${TEST_GROUP_RULES[@]};do

		. ${RULES_DIR}/$tgrul
		message=`finish`

		if [ $? -ne 0 ]; then
			report "Test Group rule $tgrul cleanup failed"
			report $message
			return 1
		fi
	done

}

##############################################################################################
# This function is used to remove the first element from the array. Its used here to remove
# the group name from the DATA array
#
# Parameters
#       $* - Input array
#
##############################################################################################
RemoveFirstElement()
{
	shift
	set -A DATA `echo $*`
}

##############################################################################################
# This function is used to write to the test case report
#
# Parameters
#       $* - Contains the message
#
##############################################################################################
report()
{
	echo "$*" >> ${TMP}/${GROUPNAME}_REPORT.log
}

##############################################################################################
# This function is used to generate the final report. It parses the Test Group config file
# and creates seperate final reports for each Test Group
#
##############################################################################################
GenFinalReport()
{
	if [ $DEBUG ]; then set -x; fi

	grep "^TEST_GROUP:" $TESTGROUPCONF | awk -F: '{print $2}' |\
	while read line
	do
		FINAL_REPORT=${REPORTS_DIR}/${line}_REPORT_${date_stamp}.rpt

		typeset -i run=0
		typeset -i pass=0
		typeset -i fail=0
		
		#Commented for compatability with ksh M-11/16/88i
		#eval run=run$line
		#eval pass=pass$line
		#eval fail=fail$line

		eval run=$\run$line
                eval pass=$\pass$line
                eval fail=$\fail$line

	
	print "\n*******************************************************************************\n" > $FINAL_REPORT
	print "GROUP NAME		:	$line \n" >> $FINAL_REPORT
	print "No. of testcases run       : $run"  >> $FINAL_REPORT
	print "No. of testcases passed    : $pass" >> $FINAL_REPORT
	print "No. of testcases failed    : $fail" >> $FINAL_REPORT
	print "\n*******************************************************************************\n" >> $FINAL_REPORT

	cat ${TMP}/${line}_REPORT.log >> $FINAL_REPORT 2>/dev/null

	done

	return 0

}


##############################################################################################
# This function is used for reading the config file and doing the variable initializations
#
# Parameters
#       $* - Contains the message
#
##############################################################################################
ReadConfig()
{
	if [ $DEBUG ]; then set -x; fi

	. ${CONFIG_FILE}

	if [[ -z $SCRIPTS ]]; then $SCRIPTS=$SCRIPT_HOME/scripts; fi
	if [[ -z $REPORTS_DIR ]]; then $REPORTS_DIR=$SCRIPT_HOME/REPORT; fi

	if [[ ! -d $SCRIPT_HOME ]]; then print "Invalid SCRIPT_HOME path"; return 1; fi
	if [[ ! -d $CONF ]]; then  print "Invalid CONF path"; return 1; fi
	if [[ ! -d $SCRIPTS ]]; then  print "Invalid SCRIPTS path"; return 1; fi
	if [[ ! -d $REPORTS_DIR ]]; then  print "Invalid REPORTS_DIR path"; return 1; fi
	if [[ ! -f $TESTGROUPCONF ]]; then print "Invalid TESTGROUPCONF path"; return 1; fi
	if [[ ! -f $DATAMODELCONF ]]; then print "Invalid DATAMODELCONF path"; return 1; fi
	if [[ ! -d $TESTDATA ]]; then print "Invalid TESTDATA path"; return 1; fi

	LIB=${SCRIPT_HOME}/lib
	TMP=${SCRIPT_HOME}/tmp
	RULES_DIR=${SCRIPT_HOME}/rules

	if [[ ! -d $LIB ]]; then  print "lib directory not present inside $SCRIPTS directory"; return 1; fi
	if [[ ! -d $TMP ]]; then mkdir $TMP; return 1; fi

	touch $TMP/test

	rm $TMP/*

	#Adding security for script variables
	typeset -r CONFIG_FILE SCRIPTS REPORTS_DIR SCRIPT_HOME CONF LIB TMP
	typeset -r TESTGROUPCONF DATAMODELCONF TESTDATA RULES_DIR

	return 0
}

##############################################################################################
# This function is used for reading the config file and doing the variable initializations
#
# Parameters
#       $* - Contains the message
#
##############################################################################################
Main()
{
	if [ $# == 0 ]
	then
		print "invalid input provided: "
		Usage
		exit 1
	fi
		
	while getopts f:d o
	do
		case $o in
		f)
			CONFIG_FILE=${OPTARG}
			;;
		d)
			DEBUG=1
			;;
		?)
			Usage
			exit 0
			;;
		*)
			Usage
			exit 1
			;;
		esac
	done

	if [ $DEBUG ]; then set -x; PS4="TCE : "; fi

	if [ ! -f $CONFIG_FILE ]
	then
		print "$CONFIG_FILE: Config File not present - Quiting"
		exit 1
	fi

	# Function for reading the configurable values
	#
	ReadConfig

	if [ $? != 0 ]
	then
		print "The required configuration parameters are not defined"
		exit 1
	fi

	GlobalInitialize

	if [ $? != 0 ]
	then
		print "Global initialization failed"
		exit 1
	fi

	# Reading Data Model config
	#
	while read line
	do
		# FLAG for checking the status of the test case
		#
		typeset -i FLAG=0

		typeset -i run=0
		typeset -i pass=0
		typeset -i fail=0

		# Parsing a line from Data Model into an array
		#
		set -A DATA `echo $line | sed -e 's/ /@/g' -e 's/:/ /g'`

		TESTCASE=${DATA[0]}
		GROUPNAME=${DATA[0]%_*}
		
		# Setting the Test Group level count of testcases passed, failed and run
		#

		#Commented for compatability with ksh M-11/16/88i
		#eval run=run$GROUPNAME
		#eval pass=pass$GROUPNAME
		#eval fail=fail$GROUPNAME

		eval run=$\run$GROUPNAME
                eval pass=$\pass$GROUPNAME
                eval fail=$\fail$GROUPNAME

		RemoveFirstElement ${DATA[*]}
		GetGroupValues

		report "\n$TESTCASE :-"
		report "Testcase start Time : `date`"
		
		((run+=1))

		InitialzeAll

		if [[ $? -ne 0 ]]; then
			report "Testcase $TESTCASE initialization failed"
			FLAG=1
		fi

		# ExecuteAll function should be executed only if
		# InitialzeAll was successfull
		#
		[[ $FLAG -eq 0 ]] && ExecuteAll ${DATA[*]}

		if [[ $? -ne 0 && $FLAG -eq 0 ]]; then
			report "Testcase $TESTCASE execution failed"
			FLAG=2
		fi

		# CompleteAll function should be executed
		# if InitialzeAll was successfull
		#
		[[ $FLAG -ne 1 ]] && FinishAll

		if [[ $? -ne 0 && $FLAG -ne 1 ]]; then
			report "Testcase $TESTCASE completion failed"
			FLAG=1
		fi
	
		echo

		if [[ $FLAG -ne 0 ]]; then
			report "Testcase $TESTCASE failed"
			echo "\t\t Execution Status : FAILED"
			(( fail+=1 ))
		else
			report "Testcase $TESTCASE completed successfully"
			echo "\t\t Execution Status : SUCCESS"
			(( pass+=1 ))
		fi

		report "Testcase end time `date`"
		echo "\t\t Execution Time : `date`"
		echo "========================================================== "
		echo 
		echo
		eval run$GROUPNAME=$run
		eval pass$GROUPNAME=$pass
		eval fail$GROUPNAME=$fail

	done < $DATAMODELCONF


	GenFinalReport


	GlobalCleanup

	if [ $? != 0 ] ; then
		print "Global cleanup failed"
		exit 1
	fi

	exit 0
}

Main $*

