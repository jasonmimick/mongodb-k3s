# mongodb-k8s

All-in-one Enterprise MongoDB running in Kubernetes.

## Get started

To install all base components and start
a MongoDB database:

```
helm install mongodb mongodb-k8s
kubectl port-forward mongodb-ops-manager-0 8080:8080
```

You can connect to the database with the `uri` found
in the binding secret.


