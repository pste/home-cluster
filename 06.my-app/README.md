# Time to deploy

Now the cluster is up and running, has network (can pull from dockerhub) and storage (can run a database).  
It is time to add a custom application, locally developed.

# The docker image

I have three ideas on how-to send my custom image on the cluster:
- I'll build locally then the image will be sent on DockerHub (internet hosted) [docs](https://docs.docker.com/get-started/introduction/build-and-push-first-image/)
  PRO: easy to implement
  CONS: not applicable on WSL2 native, I don't like the idea to build the image on the folder I'm working (what if I have a COPY . . command ?)
- I'll build locally then I'll push the image on the node to a local Registry [docs](https://medium.com/@lumontec/running-container-registries-inside-k8s-6564aed42b3a)
  PRO: easy to implement
  CONS: not applicable on WSL2 native, I don't like the idea to build the image on the folder I'm working (what if I have a COPY . . command ?), requires a new Registry Pod
- I'll build the image on the node with a CICD (Jenkins ?) Pod, pulling the code from GitHub
  PRO: not so hard to implement
  CONS: require some tool (img, kaniko, dind, ..)

~~Actually I'm tempted on the DockerHub solution because my code is already public on GitHub and I can use my local resources for other ...~~  
I'm investigating the "CICD" solution, using a Job (Pod) to launch on demand as a builder/publisher. Actually I've a batch file that does the stuff.

# Your DB migrations

If you'll run a DB on the cluster you also will need to create tables, add data, etc.  
I always use `migrations` to modify databases but...how can I reach my DB Pod?  

The idea is to develop locally my migrations then, thanks to the port-forward command, send the code through this tunnel:
`kubectl port-forward deployment/postgres 5432:5432 -n my-namespace`  
Note that I used the Deployment, to activate the connection to one of my db pods.  
With the port-forward active I'm able to run my migration connection to `localhost:5432` from my WSL2 machine.

# DBeaver Client

I use CloudBeaver as my db client (docker run etc etc) on my Windows host.  

Step 1: To be launced once. To accept TCP connections into my WSL2 world (from the outside) I needed to edit the firewall launching:  
`sudo ufw allow 5432/tcp`

Step 2: port-forward (see previous paragraph) from my linux WSL shell   

Step 3: I'm able to connect to host.docker.internal:5432 from Windows

This is the route:
(windows pc) ==> (wsl2) ==> (tunnel k8s) ==> postgres pod

