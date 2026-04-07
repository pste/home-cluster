# Time to deploy

Now the cluster is up and running, has network (can pull from dockerhub) and storage (can run a database).  
It is time to add a custom application, locally developed.

# The docker image

Development happens on WSL2, which means building images locally and pushing directly to the cluster is not a viable option.

## Chosen approach: GitHub Actions → DockerHub → ArgoCD

1. Code is pushed to GitHub
2. A GitHub Actions workflow builds the Docker image and pushes it to DockerHub
3. ArgoCD detects the new image tag and deploys it to the cluster

This keeps the build pipeline outside the cluster and off the local machine, with DockerHub as the registry. See the app repository for the GitHub Actions workflow definition.

## Alternative approaches considered

**Local build → DockerHub** ([docs](https://docs.docker.com/get-started/introduction/build-and-push-first-image/))  
Build the image manually on the dev machine and push to DockerHub. Simple but not usable from WSL2 natively, and building in the working directory is risky if the Dockerfile has a `COPY . .` instruction.

**Local build → in-cluster Registry** ([docs](https://medium.com/@lumontec/running-container-registries-inside-k8s-6564aed42b3a))  
Run a registry Pod inside the cluster and push images directly to it. Keeps images local to the network but has the same WSL2 build limitations, plus requires maintaining a registry Pod.

**In-cluster build (Kaniko / Jenkins)**  
A Pod inside the cluster pulls the source from GitHub and builds the image without needing a Docker daemon. Tools like [Kaniko](https://github.com/GoogleContainerTools/kaniko) (daemonless, runs as a Job) or Jenkins work well for this. More infrastructure to maintain but fully self-hosted and independent from external CI.

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

