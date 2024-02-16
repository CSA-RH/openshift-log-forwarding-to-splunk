# For downloading splunk: https://www.splunk.com/en_us/download/splunk-enterprise/thank-you-enterprise.html#

# On the splunk server (RHEL)
# Install on /mnt
sudo rpm -i --prefix=/mnt/ splunk-9.2.0.1-d8ae995bf219.x86_64.rpm
export SPLUNK_HOME=/mnt/splunk
# Start and enable Splunk (Set user and password)
sudo $SPLUNK_HOME/bin/splunk start --accept-license
sudo $SPLUNK_HOME/bin/splunk enable boot-start 

# Internal address: http://127.0.0.1:8000
# External address: http://<VM_PUBLIC_IP>:8000/
# Allow traffic on NIC (Azure)
#  On Azure portal VM 
#    rhel-splunk -> 
#       (left pane) Network Settings -> 
#          public  IP interface -> add target port 8000 from any origin
# Allow traffic on VM for Web Console and for HTTP Event Collector
sudo firewall-cmd --add-port=8000/tcp 
sudo firewall-cmd --add-port=8088/tcp 
sudo firewall-cmd --runtime-to-permanent

# Get token form HEC (HTTP Event Collector)
export HEC_TOKEN=<HERE_YOUR_TOKEN>
export SPLUNK_PUBLIC_IP=<VM_PUBLIC_IP>
export SPLUNK_PRIVATE_IP=<VM_PRIVATE_IP>

# Create ClusterLogging for vector
#   => info: https://docs.openshift.com/container-platform/4.12/logging/log_collection_forwarding/cluster-logging-collector.html#creating-logfilesmetricexporter_cluster-logging-collector
cat <<EOF | oc create -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: splunk-cl
  namespace: openshift-logging
spec:
  collection:
    type: vector
EOF
# create secret with HEC token
oc create secret generic vector-splunk-secret \
   --namespace openshift-logging \
   --from-literal hecToken=$HEC_TOKEN

# create service account splunk-forwarder in the openshift-logging namespace
oc create sa splunk-forwarder -n openshift-logging
# add permissions to splunk-forwarder
#  - application logs (ClusterRole added in OpenShift Logging 5.8)
oc adm policy add-cluster-role-to-user \
  collect-infrastructure-logs \
  system:serviceaccount:openshift-logging:splunk-forwarder
#  - infrastructure logs (ClusterRole added in OpenShift Logging 5.8)
oc adm policy add-cluster-role-to-user \
  collect-infrastructure-logs \
  system:serviceaccount:openshift-logging:splunk-forwarder
#  - If apply, audit logs (ClusterRole added in OpenShift Logging 5.8) 
oc adm policy add-cluster-role-to-user \
  collect-audit-logs \
  system:serviceaccount:openshift-logging:splunk-forwarder

# create log forwarder 
cat <<EOF | oc create -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: splunk-lf
  namespace: openshift-logging
spec:
  serviceAccountName: splunk-forwarder
  outputs:
    - name: splunk-receiver 
      secret:
        name: vector-splunk-secret 
      type: splunk 
      url: http://$SPLUNK_PRIVATE_IP:8088
  pipelines: 
    - inputRefs:
        - application
        - infrastructure
      name: 
      outputRefs:
        - splunk-receiver 
EOF

# About how to configure HEC in splunk
#   https://docs.splunk.com/Documentation/SplunkCloud/latest/Data/UsetheHTTPEventCollector
# Enable token in Global Settings (HEC Event Collector)

# For checking port reachability form pods and nodes not having network tools: 
HOST=<HERE_THE_HOST_TO_TEST>
PORT=<HERE_THE_PORT_TO_TEST>
(echo > /dev/tcp/$HOST/$PORT) >/dev/null 2>&1 && echo "It's up" || echo "It's down"

curl -k "http://$SPLUNK_PUBLIC_IP:8088/services/collector/event" \
     -H "Authorization: Splunk $SPLUNK_HEC_TOKEN"   \
     -d '{"event": "Hello, Splunk! This is a test event."}'

