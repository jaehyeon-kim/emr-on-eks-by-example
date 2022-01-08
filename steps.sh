export OWNER=jaehyeon
export AWS_REGION=ap-southeast-2
export CLUSTER_NAME=emr-eks-example
export EMR_ROLE_NAME=${CLUSTER_NAME}-job-execution
export S3_BUCKET_NAME=${CLUSTER_NAME}-${AWS_REGION}
export LOG_GROUP_NAME=/${CLUSTER_NAME}

#### run setup script
## - create config files, sample scripts and download necessary files
./setup.sh

tree -p config -p manifests
# config
# ├── [-rw-r--r--]  cdc_events.avsc
# ├── [-rw-r--r--]  cdc_events_s3.properties
# ├── [-rw-r--r--]  driver_pod_template.yml
# ├── [-rw-r--r--]  executor_pod_template.yml
# ├── [-rw-r--r--]  food_establishment_data.csv
# ├── [-rw-r--r--]  health_violations.py
# └── [-rw-r--r--]  hudi-utilities-bundle_2.12-0.10.0.jar
# manifests
# ├── [-rw-r--r--]  cluster.yaml
# ├── [-rw-r--r--]  nodegroup-spot.yaml
# └── [-rw-r--r--]  nodegroup.yaml

#### create S3 bucket/log group/glue database and upload files to S3
aws s3 mb s3://${S3_BUCKET_NAME}
aws logs create-log-group --log-group-name=${LOG_GROUP_NAME}
aws glue create-database --database-input '{"Name": "datalake"}'

## upload files to S3
for f in $(ls ./config/)
  do
    aws s3 cp ./config/${f} s3://${S3_BUCKET_NAME}/config/
  done
# upload: config/cdc_events.avsc to s3://emr-eks-example-ap-southeast-2/config/cdc_events.avsc
# upload: config/cdc_events_s3.properties to s3://emr-eks-example-ap-southeast-2/config/cdc_events_s3.properties
# upload: config/driver_pod_template.yml to s3://emr-eks-example-ap-southeast-2/config/driver_pod_template.yml
# upload: config/executor_pod_template.yml to s3://emr-eks-example-ap-southeast-2/config/executor_pod_template.yml
# upload: config/food_establishment_data.csv to s3://emr-eks-example-ap-southeast-2/config/food_establishment_data.csv
# upload: config/health_violations.py to s3://emr-eks-example-ap-southeast-2/config/health_violations.py
# upload: config/hudi-utilities-bundle_2.12-0.10.0.jar to s3://emr-eks-example-ap-southeast-2/config/hudi-utilities-bundle_2.12-0.10.0.jar

#### create cluster, node group and configure
eksctl create cluster -f ./manifests/cluster.yaml
eksctl create nodegroup -f ./manifests/nodegroup.yaml

kubectl get nodes
# NAME                                               STATUS   ROLES    AGE     VERSION
# ip-192-168-33-60.ap-southeast-2.compute.internal   Ready    <none>   5m52s   v1.21.5-eks-bc4871b
# ip-192-168-95-68.ap-southeast-2.compute.internal   Ready    <none>   5m49s   v1.21.5-eks-bc4871b

## create namespace and RBAC permissions
kubectl create namespace spark
eksctl create iamidentitymapping --cluster ${CLUSTER_NAME} \
  --namespace spark --service-name "emr-containers"

kubectl describe cm aws-auth -n kube-system
# Name:         aws-auth
# Namespace:    kube-system
# Labels:       <none>
# Annotations:  <none>

# Data
# ====
# mapRoles:
# ----
# - groups:
#   - system:bootstrappers
#   - system:nodes
#   rolearn: arn:aws:iam::<AWS-ACCOUNT-ID>:role/eksctl-emr-eks-example-nodegroup-NodeInstanceRole-15J26FPOYH0AL
#   username: system:node:{{EC2PrivateDNSName}}
# - rolearn: arn:aws:iam::<AWS-ACCOUNT-ID>:role/AWSServiceRoleForAmazonEMRContainers
#   username: emr-containers

# mapUsers:
# ----
# []

# Events:  <none>

## enable IAM roles for service account
eksctl utils associate-iam-oidc-provider \
  --cluster ${CLUSTER_NAME} --approve

aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[1]"
# {
#     "Arn": "arn:aws:iam::<AWS-ACCOUNT-ID>:oidc-provider/oidc.eks.ap-southeast-2.amazonaws.com/id/6F3C18F00D8610088272FEF11013B8C5"
# }

## create IAM role for job execution
aws iam create-role \
  --role-name ${EMR_ROLE_NAME} \
  --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticmapreduce.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

aws iam put-role-policy \
  --role-name ${EMR_ROLE_NAME} \
  --policy-name ${EMR_ROLE_NAME}-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "glue:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": [
                "arn:aws:logs:*:*:*"
            ]
        }
    ]
}'

## update trust relationship for job execution role
aws emr-containers update-role-trust-policy \
  --cluster-name ${CLUSTER_NAME} \
  --namespace spark \
  --role-name ${EMR_ROLE_NAME}

aws iam get-role --role-name ${EMR_ROLE_NAME} --query "Role.AssumeRolePolicyDocument.Statement[1]"
# {
#     "Effect": "Allow",
#     "Principal": {
#         "Federated": "arn:aws:iam::<AWS-ACCOUNT-ID>:oidc-provider/oidc.eks.ap-southeast-2.amazonaws.com/id/6F3C18F00D8610088272FEF11013B8C5"
#     },
#     "Action": "sts:AssumeRoleWithWebIdentity",
#     "Condition": {
#         "StringLike": {
#             "oidc.eks.ap-southeast-2.amazonaws.com/id/6F3C18F00D8610088272FEF11013B8C5:sub": "system:serviceaccount:spark:emr-containers-sa-*-*-<AWS-ACCOUNT-ID>-93ztm12b8wi73z7zlhtudeipd0vpa8b60gchkls78cj1q"
#         }
#     }
# }

## register EKS cluster with EMR
aws emr-containers create-virtual-cluster \
  --name ${CLUSTER_NAME} \
  --container-provider '{
    "id": "'${CLUSTER_NAME}'",
    "type": "EKS",
    "info": {
        "eksInfo": {
            "namespace": "spark"
        }
    }
}'

aws emr-containers list-virtual-clusters --query "sort_by(virtualClusters, &createdAt)[-1]"
# {
#     "id": "9wvd1yhms5tk1k8chrn525z34",
#     "name": "emr-eks-example",
#     "arn": "arn:aws:emr-containers:ap-southeast-2:<AWS-ACCOUNT-ID>:/virtualclusters/9wvd1yhms5tk1k8chrn525z34",
#     "state": "RUNNING",
#     "containerProvider": {
#         "type": "EKS",
#         "id": "emr-eks-example",
#         "info": {
#             "eksInfo": {
#                 "namespace": "spark"
#             }
#         }
#     },
#     "createdAt": "2022-01-07T01:26:37+00:00",
#     "tags": {}
# }

#### example 1
# export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name=='${CLUSTER_NAME}'].id" --output text)
export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "sort_by(virtualClusters, &createdAt)[-1].id" --output text)
export EMR_ROLE_ARN=$(aws iam get-role --role-name ${EMR_ROLE_NAME} --query Role.Arn --output text)

## create job request
cat << EOF > ./request-health-violations.json
{
    "name": "health-violations",
    "virtualClusterId": "${VIRTUAL_CLUSTER_ID}",
    "executionRoleArn": "${EMR_ROLE_ARN}",
    "releaseLabel": "emr-6.2.0-latest",
    "jobDriver": {
        "sparkSubmitJobDriver": {
            "entryPoint": "s3://${S3_BUCKET_NAME}/config/health_violations.py",
            "entryPointArguments": [
                "--data_source", "s3://${S3_BUCKET_NAME}/config/food_establishment_data.csv",
                "--output_uri", "s3://${S3_BUCKET_NAME}/output"
            ],
            "sparkSubmitParameters": "--conf spark.executor.instances=2 \
                --conf spark.executor.memory=2G \
                --conf spark.executor.cores=1 \
                --conf spark.driver.cores=1 \
                --conf spark.driver.memory=2G"
        }
    },
    "configurationOverrides": {
        "monitoringConfiguration": {
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "${LOG_GROUP_NAME}",
                "logStreamNamePrefix": "health"
            },
            "s3MonitoringConfiguration": {
                "logUri": "s3://${S3_BUCKET_NAME}/logs/"
            }
        }
    }
}
EOF

aws emr-containers start-job-run \
    --cli-input-json file://./request-health-violations.json

aws emr-containers list-job-runs --virtual-cluster-id ${VIRTUAL_CLUSTER_ID} --query "jobRuns[?name=='health-violations']"
# [
#     {
#         "id": "00000002vhi7od3su5d",
#         "name": "health-violations",
#         "virtualClusterId": "9wvd1yhms5tk1k8chrn525z34",
#         "arn": "arn:aws:emr-containers:ap-southeast-2:<AWS-ACCOUNT-ID>:/virtualclusters/9wvd1yhms5tk1k8chrn525z34/jobruns/00000002vhi7od3su5d",
#         "state": "COMPLETED",
#         "clientToken": "055d2acd-25bb-42fb-aa95-bf7184312a03",
#         "executionRoleArn": "arn:aws:iam::<AWS-ACCOUNT-ID>:role/emr-eks-example-job-execution",
#         "releaseLabel": "emr-6.2.0-latest",
#         "createdAt": "2022-01-07T01:53:57+00:00",
#         "createdBy": "arn:aws:sts::<AWS-ACCOUNT-ID>:assumed-role/AWSReservedSSO_AWSFullAccountAdmin_fb6fa00561d5e1c2/jaehyeon.kim@cevo.com.au",
#         "finishedAt": "2022-01-07T01:55:03+00:00",
#         "stateDetails": "JobRun completed successfully. It ran for 41 Seconds",
#         "tags": {}
#     }
# ]

export OUTPUT_FILE=$(aws s3 ls s3://${S3_BUCKET_NAME}/output/ | grep .csv | awk '{print $4}')
aws s3 cp s3://${S3_BUCKET_NAME}/output/${OUTPUT_FILE} - | head -n 15
# name,total_red_violations
# SUBWAY,322
# T-MOBILE PARK,315
# WHOLE FOODS MARKET,299
# PCC COMMUNITY MARKETS,251
# TACO TIME,240
# MCDONALD'S,177
# THAI GINGER,153
# SAFEWAY INC #1508,143
# TAQUERIA EL RINCONSITO,134
# HIMITSU TERIYAKI,128

#### example 2
export VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters --query "sort_by(virtualClusters, &createdAt)[-1].id" --output text)
export EMR_ROLE_ARN=$(aws iam get-role --role-name ${EMR_ROLE_NAME} --query Role.Arn --output text)

## create spot node group
eksctl create nodegroup -f ./manifests/nodegroup-spot.yaml

kubectl get nodes \
  --label-columns=eks.amazonaws.com/nodegroup,eks.amazonaws.com/capacityType \
  --sort-by=.metadata.creationTimestamp
# NAME                                                STATUS   ROLES    AGE    VERSION               NODEGROUP        CAPACITYTYPE
# ip-192-168-33-60.ap-southeast-2.compute.internal    Ready    <none>   52m    v1.21.5-eks-bc4871b   nodegroup        ON_DEMAND
# ip-192-168-95-68.ap-southeast-2.compute.internal    Ready    <none>   51m    v1.21.5-eks-bc4871b   nodegroup        ON_DEMAND
# ip-192-168-79-20.ap-southeast-2.compute.internal    Ready    <none>   114s   v1.21.5-eks-bc4871b   nodegroup-spot   SPOT
# ip-192-168-1-57.ap-southeast-2.compute.internal     Ready    <none>   112s   v1.21.5-eks-bc4871b   nodegroup-spot   SPOT
# ip-192-168-34-249.ap-southeast-2.compute.internal   Ready    <none>   97s    v1.21.5-eks-bc4871b   nodegroup-spot   SPOT

## create job request
cat << EOF > ./request-cdc-events.json
{
    "name": "cdc-events",
    "virtualClusterId": "${VIRTUAL_CLUSTER_ID}",
    "executionRoleArn": "${EMR_ROLE_ARN}",
    "releaseLabel": "emr-6.4.0-latest",
    "jobDriver": {
        "sparkSubmitJobDriver": {
            "entryPoint": "s3://${S3_BUCKET_NAME}/config/hudi-utilities-bundle_2.12-0.10.0.jar",
            "entryPointArguments": [
              "--table-type", "COPY_ON_WRITE",
              "--source-ordering-field", "__source_ts_ms",
              "--props", "s3://${S3_BUCKET_NAME}/config/cdc_events_s3.properties",
              "--source-class", "org.apache.hudi.utilities.sources.JsonDFSSource",
              "--target-base-path", "s3://${S3_BUCKET_NAME}/hudi/cdc-events/",
              "--target-table", "datalake.cdc_events",
              "--schemaprovider-class", "org.apache.hudi.utilities.schema.FilebasedSchemaProvider",
              "--enable-hive-sync",
              "--min-sync-interval-seconds", "60",
              "--continuous",
              "--op", "UPSERT"
            ],
            "sparkSubmitParameters": "--class org.apache.hudi.utilities.deltastreamer.HoodieDeltaStreamer \
            --jars local:///usr/lib/spark/external/lib/spark-avro_2.12-3.1.2-amzn-0.jar,s3://${S3_BUCKET_NAME}/config/hudi-utilities-bundle_2.12-0.10.0.jar \
            --conf spark.driver.cores=1 \
            --conf spark.driver.memory=2G \
            --conf spark.executor.instances=2 \
            --conf spark.executor.memory=2G \
            --conf spark.executor.cores=1 \
            --conf spark.sql.catalogImplementation=hive \
            --conf spark.serializer=org.apache.spark.serializer.KryoSerializer"
        }
    },
    "configurationOverrides": {
        "applicationConfiguration": [
            {
                "classification": "spark-defaults",
                "properties": {
                  "spark.hadoop.hive.metastore.client.factory.class":"com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
                  "spark.kubernetes.driver.podTemplateFile":"s3://${S3_BUCKET_NAME}/config/driver_pod_template.yml",
                  "spark.kubernetes.executor.podTemplateFile":"s3://${S3_BUCKET_NAME}/config/executor_pod_template.yml"
                }
            }
        ],
        "monitoringConfiguration": {
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "${LOG_GROUP_NAME}",
                "logStreamNamePrefix": "cdc"
            },
            "s3MonitoringConfiguration": {
                "logUri": "s3://${S3_BUCKET_NAME}/logs/"
            }
        }
    }
}
EOF

aws emr-containers start-job-run \
    --cli-input-json file://./request-cdc-events.json

aws emr-containers list-job-runs --virtual-cluster-id ${VIRTUAL_CLUSTER_ID} --query "jobRuns[?name=='cdc-events']"
# [
#     {
#         "id": "00000002vhi9hivmjk5",
#         "name": "cdc-events",
#         "virtualClusterId": "9wvd1yhms5tk1k8chrn525z34",
#         "arn": "arn:aws:emr-containers:ap-southeast-2:<AWS-ACCOUNT-ID>:/virtualclusters/9wvd1yhms5tk1k8chrn525z34/jobruns/00000002vhi9hivmjk5",
#         "state": "RUNNING",
#         "clientToken": "63a707e4-e5bc-43e4-b11a-5dcfb4377fd3",
#         "executionRoleArn": "arn:aws:iam::<AWS-ACCOUNT-ID>:role/emr-eks-example-job-execution",
#         "releaseLabel": "emr-6.4.0-latest",
#         "createdAt": "2022-01-07T02:09:34+00:00",
#         "createdBy": "arn:aws:sts::<AWS-ACCOUNT-ID>:assumed-role/AWSReservedSSO_AWSFullAccountAdmin_fb6fa00561d5e1c2/jaehyeon.kim@cevo.com.au",
#         "tags": {}
#     }
# ]

kubectl get pod -n spark
# NAME                                                            READY   STATUS    RESTARTS   AGE
# pod/00000002vhi9hivmjk5-wf8vp                                   3/3     Running   0          14m
# pod/delta-streamer-datalake-cdcevents-5397917e324dea27-exec-1   2/2     Running   0          12m
# pod/delta-streamer-datalake-cdcevents-5397917e324dea27-exec-2   2/2     Running   0          12m
# pod/spark-00000002vhi9hivmjk5-driver                            2/2     Running   0          13m

for n in $(kubectl get nodes -l eks.amazonaws.com/capacityType=ON_DEMAND --no-headers | cut -d " " -f1)
  do echo "Pods on instance ${n}:";kubectl get pods -n spark  --no-headers --field-selector spec.nodeName=${n}
     echo
  done
# Pods on instance ip-192-168-33-60.ap-southeast-2.compute.internal:
# No resources found in spark namespace.

# Pods on instance ip-192-168-95-68.ap-southeast-2.compute.internal:
# spark-00000002vhi9hivmjk5-driver   2/2   Running   0     17m

for n in $(kubectl get nodes -l eks.amazonaws.com/capacityType=SPOT --no-headers | cut -d " " -f1)
  do echo "Pods on instance ${n}:";kubectl get pods -n spark  --no-headers --field-selector spec.nodeName=${n}
     echo
  done
# Pods on instance ip-192-168-1-57.ap-southeast-2.compute.internal:
# delta-streamer-datalake-cdcevents-5397917e324dea27-exec-2   2/2   Running   0     16m

# Pods on instance ip-192-168-34-249.ap-southeast-2.compute.internal:
# 00000002vhi9hivmjk5-wf8vp   3/3   Running   0     18m

# Pods on instance ip-192-168-79-20.ap-southeast-2.compute.internal:
# delta-streamer-datalake-cdcevents-5397917e324dea27-exec-1   2/2   Running   0     16m

aws glue get-table --database-name datalake --name cdc_events \
    --query "Table.[DatabaseName, Name, StorageDescriptor.Location, CreateTime, CreatedBy]"
# [
#     "datalake",
#     "cdc_events",
#     "s3://emr-eks-example-ap-southeast-2/hudi/cdc-events",
#     "2022-01-07T13:18:49+11:00",
#     "arn:aws:sts::590312749310:assumed-role/emr-eks-example-job-execution/aws-sdk-java-1641521928075"
# ]

#### clean up
# delete virtual cluster
export JOB_RUN_ID=$(aws emr-containers list-job-runs --virtual-cluster-id ${VIRTUAL_CLUSTER_ID} --query "jobRuns[?name=='cdc-events'].id" --output text)
aws emr-containers cancel-job-run --id ${JOB_RUN_ID} \
  --virtual-cluster-id ${VIRTUAL_CLUSTER_ID}
aws emr-containers delete-virtual-cluster --id ${VIRTUAL_CLUSTER_ID}
# delete s3
aws s3 rm s3://${S3_BUCKET_NAME} --recursive
aws s3 rb s3://${S3_BUCKET_NAME} --force
# delete log group
aws logs delete-log-group --log-group-name ${LOG_GROUP_NAME}
# delete glue table/database
aws glue delete-table --database-name datalake --name cdc_events
aws glue delete-database --name datalake
# delete iam role/policy
aws iam delete-role-policy --role-name ${EMR_ROLE_NAME} --policy-name ${EMR_ROLE_NAME}-policy
aws iam delete-role --role-name ${EMR_ROLE_NAME}
# delete eks cluster
eksctl delete cluster --name ${CLUSTER_NAME}
