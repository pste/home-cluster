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
With the port-forward active I'm able to run my migration connectiong to `localhost:5432`.

Final note: I'm on WSL2 so to use a pg client from my windows host I needed to allow TCP connections from the outside. Launching:  
`sudo ufw allow 5432/tcp`  
on my Ubuntu WSL2 machine I was able to use DBeaver from my Windows host.  

With the newly implemented firewall rule I was able to connect to localhost:5432 through this route:
(windows pc) ==> (wsl2) ==> (tunnel k8s) ==> postgres pod