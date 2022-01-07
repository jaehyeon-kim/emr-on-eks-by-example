#!/usr/bin/env bash

export OWNER=jaehyeon
export AWS_REGION=ap-southeast-2
export CLUSTER_NAME=emr-eks-example
export S3_BUCKET_NAME=${CLUSTER_NAME}-${AWS_REGION}

mkdir -p config && mkdir -p manifests

echo "create cluster and node group config files..."
cat << EOF > ./manifests/cluster.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  tags:
    Owner: ${OWNER}
EOF

cat << EOF > ./manifests/nodegroup.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  tags:
    Owner: ${OWNER}

managedNodeGroups:
- name: nodegroup
  desiredCapacity: 2
  instanceType: m5.xlarge
EOF

cat << EOF > ./manifests/nodegroup-spot.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  tags:
    Owner: ${OWNER}

managedNodeGroups:
- name: nodegroup-spot
  desiredCapacity: 3
  instanceTypes:
  - m5.xlarge
  - m5a.xlarge
  - m4.xlarge
  spot: true
EOF

echo "create pod templates..."
cat << EOF > ./config/driver_pod_template.yml
apiVersion: v1
kind: Pod
spec:
  nodeSelector:
    eks.amazonaws.com/capacityType: ON_DEMAND
EOF

cat << EOF > ./config/executor_pod_template.yml
apiVersion: v1
kind: Pod
spec:
  nodeSelector:
    eks.amazonaws.com/capacityType: SPOT
EOF

echo "create example python script and download sample data..."
cat << EOF > ./config/health_violations.py
import argparse

from pyspark.sql import SparkSession

def calculate_red_violations(data_source, output_uri):
    """
    Processes sample food establishment inspection data and queries the data to find the top 10 establishments
    with the most Red violations from 2006 to 2020.

    :param data_source: The URI of your food establishment data CSV, such as 's3://DOC-EXAMPLE-BUCKET/food-establishment-data.csv'.
    :param output_uri: The URI where output is written, such as 's3://DOC-EXAMPLE-BUCKET/restaurant_violation_results'.
    """
    with SparkSession.builder.appName("Calculate Red Health Violations").getOrCreate() as spark:
        # Load the restaurant violation CSV data
        if data_source is not None:
            restaurants_df = spark.read.option("header", "true").csv(data_source)

        # Create an in-memory DataFrame to query
        restaurants_df.createOrReplaceTempView("restaurant_violations")

        # Create a DataFrame of the top 10 restaurants with the most Red violations
        top_red_violation_restaurants = spark.sql("""SELECT name, count(*) AS total_red_violations 
          FROM restaurant_violations 
          WHERE violation_type = 'RED' 
          GROUP BY name 
          ORDER BY total_red_violations DESC LIMIT 10""")

        # Write the results to the specified output URI
        top_red_violation_restaurants.write.option("header", "true").mode("overwrite").csv(output_uri)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--data_source', help="The URI for you CSV restaurant data, like an S3 bucket location.")
    parser.add_argument(
        '--output_uri', help="The URI where output is saved, like an S3 bucket location.")
    args = parser.parse_args()

    calculate_red_violations(args.data_source, args.output_uri)
EOF

curl -s -o ./config/food_establishment_data.zip \
  https://docs.aws.amazon.com/emr/latest/ManagementGuide/samples/food_establishment_data.zip \
  && unzip ./config/food_establishment_data.zip -d ./config \
  && rm ./config/food_establishment_data.zip

echo "create Hudi config files and download hudi utility lib..."
cat << EOF > ./config/cdc_events_s3.properties
## base properties
hoodie.upsert.shuffle.parallelism=2
hoodie.insert.shuffle.parallelism=2
hoodie.delete.shuffle.parallelism=2
hoodie.bulkinsert.shuffle.parallelism=2

## datasource properties
hoodie.datasource.hive_sync.mode=hms
hoodie.datasource.hive_sync.database=datalake
hoodie.datasource.hive_sync.table=cdc_events
hoodie.datasource.hive_sync.partition_fields=customer_id,order_id
hoodie.datasource.hive_sync.partition_extractor_class=org.apache.hudi.hive.MultiPartKeysValueExtractor
hoodie.datasource.write.recordkey.field=order_id
hoodie.datasource.write.partitionpath.field=customer_id,order_id
hoodie.datasource.write.keygenerator.class=org.apache.hudi.keygen.ComplexKeyGenerator
hoodie.datasource.write.hive_style_partitioning=true
hoodie.datasource.write.drop.partition.columns=true

## deltastreamer properties
hoodie.deltastreamer.schemaprovider.source.schema.file=s3://${S3_BUCKET_NAME}/config/cdc_events.avsc
hoodie.deltastreamer.source.dfs.root=s3://${S3_BUCKET_NAME}/cdc-events/

## file properties
# 1,024 * 1,024 * 128 = 134,217,728 (128 MB)
hoodie.parquet.small.file.limit=134217728
EOF

cat << EOF > ./config/cdc_events.avsc
{
  "connect.name": "msk.datalake.cdc_events.Value",
  "fields": [
    {
      "name": "order_id",
      "type": {
        "connect.type": "int16",
        "type": "int"
      }
    },
    {
      "name": "customer_id",
      "type": "string"
    },
    {
      "default": null,
      "name": "order_date",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.time.Date",
          "connect.version": 1,
          "type": "int"
        }
      ]
    },
    {
      "default": null,
      "name": "required_date",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.time.Date",
          "connect.version": 1,
          "type": "int"
        }
      ]
    },
    {
      "default": null,
      "name": "shipped_date",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.time.Date",
          "connect.version": 1,
          "type": "int"
        }
      ]
    },
    {
      "default": null,
      "name": "order_items",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.data.Json",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "products",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.data.Json",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "customer",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.data.Json",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "employee",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.data.Json",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "shipper",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.data.Json",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "shipment",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.data.Json",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "updated_at",
      "type": [
        "null",
        {
          "connect.name": "io.debezium.time.ZonedTimestamp",
          "connect.version": 1,
          "type": "string"
        }
      ]
    },
    {
      "default": null,
      "name": "__op",
      "type": ["null", "string"]
    },
    {
      "default": null,
      "name": "__db",
      "type": ["null", "string"]
    },
    {
      "default": null,
      "name": "__table",
      "type": ["null", "string"]
    },
    {
      "default": null,
      "name": "__schema",
      "type": ["null", "string"]
    },
    {
      "default": null,
      "name": "__lsn",
      "type": ["null", "long"]
    },
    {
      "default": null,
      "name": "__source_ts_ms",
      "type": ["null", "long"]
    },
    {
      "default": null,
      "name": "__deleted",
      "type": ["null", "string"]
    }
  ],
  "name": "Value",
  "namespace": "msk.datalake.cdc_events",
  "type": "record"
}
EOF

curl -s -o ./config/hudi-utilities-bundle_2.12-0.10.0.jar \
  https://repo1.maven.org/maven2/org/apache/hudi/hudi-utilities-bundle_2.12/0.10.0/hudi-utilities-bundle_2.12-0.10.0.jar
