# EMR on EKS by Example

[EMR on EKS by Example](https://cevo.com.au/post/emr-on-eks-by-example/)
- [EMR on EKS](https://aws.amazon.com/emr/features/eks/) provides a deployment option for [Amazon EMR](https://aws.amazon.com/emr/) that allows you to automate the provisioning and management of open-source big data frameworks on [Amazon EKS](https://aws.amazon.com/eks/). While a wide range of open source big data components are available in EMR on EC2, only Apache Spark is available in EMR on EKS. It is more flexible, however, that applications of different EMR versions can be run in multiple availability zones on either EC2 or Fargate. Also other types of containerized applications can be deployed on the same EKS cluster. Therefore, if you have or plan to have, for example, [Apache Airflow](https://airflow.apache.org/), [Apache Superset](https://superset.apache.org/) or [Kubeflow](https://www.kubeflow.org/) as your analytics toolkits, it can be an effective way to manage big data (as well as non-big data) workloads. While Glue is more for ETL, EMR on EKS can also be used for other types of tasks such as machine learning. Moreover it allows you to build a Spark application, not a Gluish Spark application. For example, while you have to use custom connectors for [Hudi](https://aws.amazon.com/marketplace/pp/prodview-zv3vmwbkuat2e) or [Iceberg](https://aws.amazon.com/marketplace/pp/prodview-iicxofvpqvsio) for Glue, you can use their native libraries with EMR on EKS. In this post, we’ll discuss EMR on EKS with simple and elaborated examples.
