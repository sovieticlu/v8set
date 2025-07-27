I0727 16:41:09.499583   17968 patchnode.go:31] [patchnode] Uploading the CRI Socket information "unix:///var/run/containerd/containerd.sock" to the Node API object "raspberrypi" as an annotation
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node raspberrypi as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[bootstrap-token] Using token: 0gaeou.gf46b3qepu404ckt
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
I0727 16:41:10.591886   17968 clusterinfo.go:47] [bootstrap-token] loading admin kubeconfig
I0727 16:41:10.592696   17968 clusterinfo.go:58] [bootstrap-token] copying the cluster from admin.conf to the bootstrap kubeconfig
I0727 16:41:10.594997   17968 clusterinfo.go:70] [bootstrap-token] creating/updating ConfigMap in kube-public namespace
I0727 16:41:10.604179   17968 clusterinfo.go:84] creating the RBAC rules for exposing the cluster-info ConfigMap in the kube-public namespace
I0727 16:41:10.629510   17968 kubeletfinalize.go:90] [kubelet-finalize] Assuming that kubelet client certificate rotation is enabled: found "/var/lib/kubelet/pki/kubelet-client-current.pem"
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
I0727 16:41:10.630857   17968 kubeletfinalize.go:134] [kubelet-finalize] Restarting the kubelet to enable client certificate rotation
[addons] Applied essential addon: CoreDNS

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes by copying certificate authorities
and service account keys on each node and then running the following as root:

  kubeadm join 10.2.0.2:6443 --token 0gaeou.gf46b3qepu404ckt \
        --discovery-token-ca-cert-hash sha256:3200d957e8ed5db04901de4e8bf5f4660738412e19b6cd062bcc09bf36f3c8c1 \
        --control-plane 

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.2.0.2:6443 --token 0gaeou.gf46b3qepu404ckt \
        --discovery-token-ca-cert-hash sha256:3200d957e8ed5db04901de4e8bf5f4660738412e19b6cd062bcc09bf36f3c8c1 
[WARN] Waiting for API server to start... (60s remaining)