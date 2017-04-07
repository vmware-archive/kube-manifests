FROM debian:8
MAINTAINER sre@bitnami.com

RUN adduser --home /home/user --disabled-password --gecos User user

RUN apt-get -q update && apt-get -qy install jq

ADD https://storage.googleapis.com/bitnami-jenkins-tools/jsonnet-0.9.0 /usr/local/bin/jsonnet
RUN chmod +x /usr/local/bin/jsonnet

# NB: 1.5.x kubectl refuses to allow you to modify a different
# namespace when run in-cluster.
# See https://github.com/kubernetes/kubernetes/issues/38744
ADD https://storage.googleapis.com/kubernetes-release/release/v1.4.7/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

USER user
WORKDIR /home/user
CMD ["/bin/bash", "-l"]
