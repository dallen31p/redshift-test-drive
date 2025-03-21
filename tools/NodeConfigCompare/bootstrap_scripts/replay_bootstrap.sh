#!/bin/bash
set -e
echo "bucket_name: $BUCKET_NAME"
echo "simple_replay_overwrite_s3_path: $SIMPLE_REPLAY_OVERWRITE_S3_PATH"
echo "redshift_user_name: $REDSHIFT_USER_NAME"
echo "what_if_timestamp: $WHAT_IF_TIMESTAMP"
echo "extract_prefix: $EXTRACT_PREFIX"
echo "replay_prefix: $REPLAY_PREFIX"
echo "script_prefix: $SCRIPT_PREFIX"
echo "redshift_iam_role: $REDSHIFT_IAM_ROLE"
echo "workload_location: $WORKLOAD_LOCATION"
echo "cluster_endpoint: $CLUSTER_ENDPOINT"
echo "cluster_identifier: $CLUSTER_IDENTIFIER"
echo "execute_unload_statements: $SIMPLE_REPLAY_UNLOAD_STATEMENTS"
echo "snapshot_account_id: $SNAPSHOT_ACCOUNT_ID"
account_id=`aws sts get-caller-identity --query Account --output text`
echo "account_id: $account_id"
echo "endpoint_type: $ENDPOINT_TYPE"
TARGET_CLUSTER_REGION=$(echo $CLUSTER_ENDPOINT | cut -f3 -d'.')
##region = os.environ['AWS_REGION']
yum update -y
yum -y install git
yum -y install python3
yum -y install python3-pip
yum -y install aws-cfn-bootstrap
yum -y install gcc gcc-c++ python3 python3-devel unixODBC unixODBC-devel
mkdir amazonutils
cd amazonutils
git clone https://github.com/dallen31p/redshift-test-drive.git
cd redshift-test-drive
make setup
if [[ "$SIMPLE_REPLAY_OVERWRITE_S3_PATH" != "N/A" ]]; then
  aws s3 cp $SIMPLE_REPLAY_OVERWRITE_S3_PATH config/replay.yaml
fi

sed -i "s#master_username: \".*\"#master_username: \"$REDSHIFT_USER_NAME\"#g" config/replay.yaml
sed -i "s#unload_iam_role: \".*\"#unload_iam_role: \"$REDSHIFT_IAM_ROLE\"#g" config/replay.yaml
sed -i "s#workload_location: \".*\"#workload_location: \"$WORKLOAD_LOCATION\"#g" config/replay.yaml
sed -i "s#target_cluster_endpoint: \".*\"#target_cluster_endpoint: \"$CLUSTER_ENDPOINT\"#g" config/replay.yaml
sed -i "s#target_cluster_region: \".*\"#target_cluster_region: \"$TARGET_CLUSTER_REGION\"#g" config/replay.yaml
sed -i "s#analysis_iam_role: \".*\"#analysis_iam_role: \"$REDSHIFT_IAM_ROLE\"#g" config/replay.yaml
sed -i "s#analysis_output: \".*\"#analysis_output: \"$WORKLOAD_LOCATION\"#g" config/replay.yaml

if [ "$SIMPLE_REPLAY_UNLOAD_STATEMENTS" == "true" ]; then
    sed -i "s#unload_iam_role: \".*\"#unload_iam_role: \"$REDSHIFT_IAM_ROLE\"#g" config/replay.yaml
    sed -i "s#replay_output: \".*\"#replay_output: \"s3://$BUCKET_NAME/$REPLAY_PREFIX/$WHAT_IF_TIMESTAMP/$CLUSTER_IDENTIFIER\"#g" config/replay.yaml
fi


if [[ "$account_id" == "$SNAPSHOT_ACCOUNT_ID" ]]; then
   sed -i "s#execute_copy_statements: \"false\"#execute_copy_statements: \"true\"#g" config/replay.yaml
   aws s3 cp $WORKLOAD_LOCATION/copy_replacements.csv . || true
   sed -z -i "s#,,\n#,,$REDSHIFT_IAM_ROLE\n#g" copy_replacements.csv || true
   aws s3 cp copy_replacements.csv $WORKLOAD_LOCATION/copy_replacements.csv || true
fi
aws s3 cp config/replay.yaml s3://$BUCKET_NAME/$SCRIPT_PREFIX/replay_$CLUSTER_IDENTIFIER.yaml
make replay
if [[ $ENDPOINT_TYPE == 'SERVERLESS' ]]; then
  aws s3 cp s3://$BUCKET_NAME/$SCRIPT_PREFIX/system_config.json .
  aws s3 cp s3://$BUCKET_NAME/$SCRIPT_PREFIX/create_external_schema.py .
  python3 tools/NodeConfigCompare/python_scripts/create_external_schema.py
fi
