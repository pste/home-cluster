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
