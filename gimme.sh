#!/bin/bash

boxname=${BOXNAME:-kubebox}
zone="${ZONE:-us-west2-a}"
project=$(gcloud config list project --format "value(core.project)" )
image_name=${IMAGE_NAME:-kubebox}
machine_type=${MACHINE_TYPE:-n1-standard-4}
source_ranges=${SOURCE_RANGES:-0.0.0.0/0}

{

echo 📍 Creating Instance
gcloud compute instances create $boxname --zone=$zone \
    --machine-type=$machine_type \
    --subnet=default \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
	--tags=kube-master \
	--image=${image_name} --image-project=$project \
	--boot-disk-size=100GB \
	--boot-disk-type=pd-standard --boot-disk-device-name=$boxname \
	--metadata-from-file startup-script=startup.sh

echo 👮 Creating Firewall Rule
gcloud compute firewall-rules create default-allow-kubeadm-master \
  --allow tcp:6443 \
  --target-tags kube-master  \
  --source-ranges $source_ranges 1>&2 &

echo -n "🔧 Waiting for kubeadmin setup"

until gcloud compute ssh $boxname --zone $zone  --command='if [ ! -f /etc/kubernetes/admin.conf ]; then echo "No"; else echo "OK"; fi' | grep -q "OK";
do
  echo -n '🔧 '
  sleep 3;
done
echo


echo 💫 Fetching kubeconfig
gcloud compute ssh $boxname --command='sudo chmod +r /etc/kubernetes/admin.conf' --zone $zone
gcloud compute scp -q --zone $zone $boxname:/etc/kubernetes/admin.conf . > /dev/null
sed "s/$(gcloud compute instances describe ${boxname} --zone ${zone} --format='value(networkInterfaces.networkIP)')/$(gcloud compute instances describe ${boxname} --zone ${zone} --format='value(networkInterfaces.accessConfigs[0].natIP)')/" admin.conf > $boxname.conf

export KUBECONFIG=$(pwd)/$boxname.conf
echo -n "🔌 Waiting for API Server"
until kubectl cluster-info | grep -q "running";
do
  echo -n '.'
  sleep 1;
done

echo

echo 💥 Removing master taint to allow workloads on node

kubectl taint nodes $boxname node-role.kubernetes.io/master- 1>&2

} 2> kubebox.log

echo "🖍  Installing cluster networking"
kubectl apply -f https://docs.projectcalico.org/v3.9/manifests/calico.yaml

echo 🎉  Done
echo
echo Now use:
echo
echo export KUBECONFIG=$(pwd)/$boxname.conf
