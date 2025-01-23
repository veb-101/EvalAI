#!/bin/bash

# installing AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
echo "### AWS CLI Installed"

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access $AWS_SECRET_ACCESS_KEY
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_DEFAULT_REGION
echo "### AWS CLI Configured"

# Install iam-authenticator
curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.7/2020-07-08/bin/linux/amd64/aws-iam-authenticator
chmod +x ./aws-iam-authenticator
mkdir -p $HOME/bin && cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
echo "### iam-authenticator Installed"

# Configure kubeconfig
aws eks --region $AWS_DEFAULT_REGION update-kubeconfig --name $CLUSTER_NAME

# Install kubectl
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl
echo "### Kubectl Installed"

# Install aws-container-insights
# Create amazon-cloudwatch namespace
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
# Create configmap for fluent bit
kubectl create configmap fluent-bit-cluster-info \
--from-literal=cluster.name=$CLUSTER_NAME \
--from-literal=http.server='On' \
--from-literal=http.port='2020' \
--from-literal=read.head='On' \
--from-literal=read.tail='Off' \
--from-literal=logs.region=$AWS_DEFAULT_REGION -n amazon-cloudwatch
# Use FluentD compatible FluentBit insights
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit-compatible.yaml
echo "### Container Insights Installed"

# Setup EFS as persistent volume
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/ecr/?ref=release-1.7"
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"

# Using STATIC PVC, PV, StorageClass
# https://github.com/kubernetes-sigs/aws-efs-csi-driver/tree/master/examples/kubernetes/static_provisioning
# # If you want to update persistent_volume_storage_class.yaml file.
# # Either delete the old one or rename and use new one with new name and change the reference in other yaml file as well.
# kubectl delete pvc efs-claim``
# kubectl delete pv efs-pv
# kubectl delete storageclass efs-sc

cat ./scripts/workers/code_upload_worker_utils/persistent_volume.yaml | sed "s/{{EFS_ID}}/$EFS_ID/" | kubectl apply -f -

kubectl apply -f /code/scripts/workers/code_upload_worker_utils/persistent_volume_claim.yaml
kubectl apply -f /code/scripts/workers/code_upload_worker_utils/persistent_volume_storage_class.yaml

# Install cilium
# Cilium is being used to provide networking and network policy
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-install.yaml
echo "### Cilium Installed"

sleep 120s;

# Apply cilium network policy
# echo "### Setting up Cilium Network Policy..."
# cat /code/scripts/workers/code_upload_worker_utils/network_policies.yaml | sed "s/{{EVALAI_DNS}}/$EVALAI_DNS/" | kubectl apply -f -
# echo "### Cilium EvalAI Network Policy Installed"

# --- Load Certificate Data into Environment Variable ---
# Retrieve the base64-encoded CA data from the EKS cluster and store it in the CERTIFICATE variable.
export CERTIFICATE=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_DEFAULT_REGION" \
    --query "cluster.certificateAuthority.data" \
    --output text)
echo "### Certificate Data loaded into CERTIFICATE variable"

# Set ssl-certificate
echo $CERTIFICATE | base64 --decode > scripts/workers/certificate.crt
echo "### Certificate Authority file created at scripts/workers/certificate.crt"


# Install cluster autoscaler 
cat ./scripts/workers/code_upload_worker_utils/cluster-autoscaler-autodiscover.yaml | sed "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/" | kubectl apply -f -

kubectl patch deployment cluster-autoscaler -n kube-system -p '{"spec":{"template": {"metadata": {"annotations": {"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'


# Running Submission Worker
chmod +x scripts/workers/code_upload_submission_worker.py
python scripts/workers/code_upload_submission_worker.py
echo "### Worker Started"

