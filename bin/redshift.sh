#!/bin/sh

#
#
# Redshift clusters start/stop script
#
# Stops/starts redshift clusters listed in etc/redshift.conf (json format)
# Sends notifications to Slack 
#
# A json file for each cluster: ${HOME}/.aws/redshift-clusters/
#
# Author: G. Doumergue <gdoumergue@squidsolutions.com>
# 
#
#
#

JQ=`which jq`
AWS=`which aws`

[ -x "${JQ}" ] || (echo "Please install jq";exit 1;)
[ -x "${AWS}" ] || (echo "Please install awscli";exit 1;)

WORKDIR=`dirname $0`

send_slack() {
:
}

CONF_DIR="${WORKDIR}/../etc/"
AUTO_SNAPSHOT_SUFFIX="yesterday"


if [ -r ${CONF_DIR}/redshift.conf ];then
	. ${CONF_DIR}/redshift.conf
else
	echo "Please configure me in ${CONF_DIR}/redshift.conf"
	exit 2
fi


usage() {

	echo "Usage: $0  -a {start|stop|save} -r aws_region -c cluster_name [-p awscli-profile]"
	exit 1

}

start() {
	START_OPTIONS=""
	MODIFY_OPTIONS=""
	# IS the cluster already started ?
	echo -n "-> Cluster ${CLUSTER}"
	if [ ! -z "${ALREADY_STARTED}" ];then

		echo " already running"
		send_slack "Redshift cluster *${CLUSTER}* is already running in region *${REGION}*."
		return 4
	fi

	# Do we have a snapshot ?
	if [ -z "${SNAPSHOT_EXISTS}" ];then
		echo " NOT restored: No shapshot named ${SNAPSHOT_NAME}"
		send_slack "No shapshot named *${SNAPSHOT_NAME}*, can't restore redshift cluster *${CLUSTER}* in region *${REGION}*"
		return 5

	fi

	# Configuration JSON file ?
	if [ ! -r ${CLUSTER_CONF_FILE} ];then
		echo "NOT restored. No json file ${CLUSTER_CONF_FILE} found. Did you run '$0 save' before ?"
		send_slack "Redshift Cluster *${CLUSTER}* not started: no json configuration file found"
		return 6
	fi

	# RESTORE
	TMPCONF=`mktemp`
	${JQ} '.CreateConf' < ${CLUSTER_CONF_FILE} > ${TMPCONF}
	AWS_MSG=`${AWS} --region ${REGION} redshift restore-from-cluster-snapshot --cli-input-json file://${TMPCONF} 2>&1`
	if [ $? = 0 ];then
		rm -f ${TMPCONF}
		
		# Tags ?
		TAG_NB=`${JQ} '.Tags.Tags | length' < ${CLUSTER_CONF_FILE}`
		if [ ${TAG_NB} -gt 0 ];then
			TMPTAGS=`mktemp`
			${JQ} '.Tags' < ${CLUSTER_CONF_FILE} > ${TMPTAGS}
			${AWS} --region ${REGION} redshift create-tags --cli-input-json file://${TMPTAGS} > /dev/null 2>&1
			echo " tagged and restored in region ${REGION}."
			send_slack "Redshift cluster *${CLUSTER}* restored with tags in region *${REGION}*"
		else
			echo " restored without any tag in region ${REGION}."
			send_slack "Redshift cluster *${CLUSTER}* restored without any tags in region *${REGION}*"
		fi
			
	else
		echo " NOT restored. Error:"
		echo ${AWS_MSG}
		SLACK_ICON=":bangbang:" send_slack "Could not restore Redshift cluster *${CLUSTER}* in region *${REGION}*,\
			 with snapshot *${SNAPSHOT_NAME}*. Error: ${AWS_MSG}"
	fi


}

stop() {

echo -n "-> Cluster ${CLUSTER}"

AUTOSHUT=`echo ${CLUSTER_PARAM} | ${JQ} -r '.shutdown'`

	if [ ! -z "${ALREADY_STARTED}" ];then
		# Do we have a snapshot ?
		if [ ! -z "${SNAPSHOT_EXISTS}" ];then
			# The snapshot exists. Need to delete it.
			${AWS} --region ${REGION} redshift delete-cluster-snapshot --snapshot-identifier ${SNAPSHOT_NAME} > /dev/null 2>&1
		fi
		AWS_MSG=`${AWS} --region ${REGION} redshift delete-cluster --cluster-identifier ${CLUSTER} --no-skip-final-cluster-snapshot \
			--final-cluster-snapshot-identifier ${SNAPSHOT_NAME} 2>&1`
		if [ $? = 0 ];then
			echo " shut down"
			send_slack "Redshift cluster *${CLUSTER}* shut down in region *${REGION}*, with snapshot *${SNAPSHOT_NAME}*."
		else
			echo " NOT shut down. Error:"
			echo ${AWS_MSG}
			SLACK_ICON=":bangbang:" send_slack "Could not shut Redshift cluster *${CLUSTER}* down in region *${REGION}*, with snapshot *${SNAPSHOT_NAME}*. Error: ${AWS_MSG}"
		fi
	else
		echo " already shut down"
		send_slack "Redshift cluster *${CLUSTER}* is already shut down in region *${REGION}*."
	fi


}

save () {

	# Save the configuration of a running redshift cluster into a json file
	# A json file for each cluster

	if [ ! -z "${ALREADY_STARTED}" ];then
		ACCOUNT_ID=`${AWS} iam get-user --query 'User.Arn' | cut -d: -f5`

		CLUSTER_DESC=`${AWS} --region ${REGION} redshift describe-clusters --cluster-identifier ${CLUSTER} --query 'Clusters[0]'`

		# Get all the relevant informations
		BASE_DESC=`echo ${CLUSTER_DESC} | ${JQ} \
		"{CreateConf:{ClusterIdentifier:.ClusterIdentifier,
                                ClusterParameterGroupName:.ClusterParameterGroups[0].ParameterGroupName,
                                ClusterSecurityGroups:.ClusterSecurityGroups,
                                ClusterSubnetGroupName:.ClusterSubnetGroupName,
                                ElasticIp:.ElasticIp,
                                PubliclyAccessible:.PubliclyAccessible,
                                VpcSecurityGroupIds:[.VpcSecurityGroups|map(select(.Status == \"active\"))[]|.VpcSecurityGroupId],
                                SnapshotIdentifier:\"${SNAPSHOT_NAME}\" },Tags:{ResourceName:\"arn:aws:redshift:${REGION}:${ACCOUNT_ID}:cluster:${CLUSTER}\",Tags:.Tags}}"`
		# Wipe out empty attributes
		echo ${BASE_DESC} | ${JQ} 'if .CreateConf.ElasticIp  | length == 0 then del(.CreateConf.ElasticIp) else . end' \
			| ${JQ} 'if .CreateConf.ClusterSecurityGroups  | length == 0 then del(.CreateConf.ClusterSecurityGroups) else . end' \
			| ${JQ} 'if .CreateConf.ClusterSubnetGroupName  | length == 0 then del(.CreateConf.ClusterSubnetGroupName) else . end' \
			| ${JQ} 'if .CreateConf.VpcSecurityGroupIds  | length == 0 then del(.CreateConf.VpcSecurityGroupIds) else . end' \
			> ${CLUSTER_CONF_FILE}

	else
		echo " already shut down"
		send_slack "Redshift cluster *${CLUSTER}* is already shut down in region *${REGION}*. Can't save its configuration"
	fi
	

}

# MAIN

while getopts a:p:r:c: OPT;do
	case ${OPT} in

		a)	ACTION=${OPTARG}
			if echo "${ACTION}" | egrep -q "(start|stop|save)";then
				echo "Action: ${ACTION}"
			else
				usage
			fi
		;;
		p)	export AWS_DEFAULT_PROFILE=${OPTARG}
		;;
		r)	REGION=${OPTARG}
		;;
		c)	CLUSTER=${OPTARG}
		;;
		"?")	usage
		;;

	esac

done
#shift `expr $OPTIND - 1`

[ -z "${ACTION}" ] && usage
[ -z "${REGION}" ] && usage
[ -z "${CLUSTER}" ] && usage

STARTED_CLUSTERS=`${AWS} --region ${REGION} redshift describe-clusters`
CLUSTER_CONF_FILE="${CONF_DIR}/${REGION}-${CLUSTER}.json"
CLUSTER_PARAM=`echo ${REDSHIFT_CLUSTERS} | ${JQ} -r '.["'${REGION}'"] | map(select(.name =="'${CLUSTER}'"))[0]' `
SNAPSHOT_NAME=`echo "${CLUSTER}-${AUTO_SNAPSHOT_SUFFIX}" |sed "s/_/-/g"`
ALREADY_STARTED=`echo ${STARTED_CLUSTERS} | ${JQ} -r '.Clusters[] | .ClusterIdentifier' | grep ${CLUSTER}`
SNAPSHOT_EXISTS=`${AWS} --region ${REGION} redshift describe-cluster-snapshots --cluster-identifier ${CLUSTER} \
	| ${JQ} -r '.Snapshots[] | .SnapshotIdentifier' | grep "${SNAPSHOT_NAME}"`

case "${ACTION}" in

	"start")
		start
	;;
	"stop")
		save
		stop
	;;
	"save")
		save
	;;
	"*")
		usage
	;;

esac

send_slack "End of *${0}* script. Please see ${WORKDIR}/../etc/redshift.conf for its configuration."
