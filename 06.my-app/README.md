# Time to deploy

Now the cluster is up and running, has network (can pull from dockerhub) and storage (can run a database).  
It is time to add a custom application, locally developed.

# The docker image

I have three ideas on how-to send my custom image on the cluster:
- I'll build locally then the image will be sent on DockerHub (internet hosted) [docs](https://docs.docker.com/get-started/introduction/build-and-push-first-image/)
- I'll build locally then I'll push the image on the node to a local Registry [docs](https://medium.com/@lumontec/running-container-registries-inside-k8s-6564aed42b3a)
- I'll build the image on the node with a Jenkins Pod, pulling the code from GitHub

Actually I'm tempted on the DockerHub solution because my code is already public on GitHub and I can use my local resources for other ...

# Your DB migrations

If you'll run a DB on the cluster you also will need to create tables, add data, etc.  
I always use `migrations` to modify databases but...how can I reach my DB Pod?  

The idea is to develop locally my migrations then, thanks to the port-forward command, send the code through this tunnel:
`kubectl port-forward deployment/postgres 5432:5432 -n my-namespace`  
Note that I used the Deployment, to activate the connection to one of my db pods.  
With the port-forward active I'm able to run my migration connection to `localhost:5432` from my WSL2 machine.

# DBeaver Client

I use CloudBeaver as my db client (docker run etc etc).  

Step 1: to accept TCP connections into my WSL2 world (from the outside) I needed to edit the firewall launching (once):  
`sudo ufw allow 5432/tcp`

Step 2: port-forward (see previous paragraph)   

Step 3: I'm able to connect to host.docker.internal:5432

This is the route:
(windows pc) ==> (wsl2) ==> (tunnel k8s) ==> postgres pod

# DDBeaver Client tentative
- launch container
- connect to kubelb:5432 (kubelb is on my hosts file)
- timeout ...