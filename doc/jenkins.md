Jenkins Post-Setup Notes
------------------------

(These notes are poorly formatted and brief.  Good luck! :)

Start container jobs.

Have to enable "crumb proxy compatibility" before we can submit
jenkins forms via the service endpoint:
```
pod=$(kubectl -n jenkins get pod -o name -l name=jenkins | cut -d/ -f2)
kubectl port-forward -n jenkins $pod 0:8080
```
Point browser at the forwarded port.

The "admin" user (aka "Unlock Jenkins") password is:
```
kubectl -n jenkins exec $pod -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Install suggested plugins.

"Continue as admin" (ie: *don't* create an admin user)

Manage Jenkins -> Configure Global Security
- Enable: Check Crumbs -> Enable proxy compatibility

Kill the port foward, go to the real k8s jenkins service endpoint.

Manage Jenkins -> Manage plugins -> Available. Install:
- CloudBees Docker Build and Publish plugin
- CloudBees Docker Custom Build Environment Plugin
- Google Container Registry Auth Plugin
- Google Login Plugin
- Kubernetes plugin
- Prometheus metrics plugin
- Phabricator Differential Plugin
- Blue Ocean beta  (optional / nice-to-have)

Install and restart when finished.  Will take a minute or so to come back.

Manage Jenkins -> Configure Global Security
- Access Control -> Login with Google:
- Go to https://console.developers.google.com/
- project: jenkins-k8s (or create a new project)
- API Manager -> Credentials -> Create credentials
  -> OAuth Client ID -> Web application
  - Authorised origins: $elb_url (with no trailing /)
  - Authorised redirect URIs: $elb_url/securityRealm/finishLogin
- Client Id: <from above>
- Client Secret: <from above>
- Google Apps Domain: bitnami.com   <- Important!

Logout as admin, verify you can log in with your @bitnami.com Google
account.

Manage Jenkins -> Configure System
(Deep breath)
- Top:
  - # of executors: 0
  - Labels: master
  - Usage: Only build jobs with label matching this node
- Phabricator:
  - Default Phabricator Credentials: Add
    - Kind: Phabricator Conduit Key
    - Phab URL: http://phabricator.bitnami.com:8080/
    - Description:
    - Conduit token: (phab: Settings -> Conduit API Tokens -> Generate API Token)
- Jenkins Location:
  - System admin email address: sre@bitnami.com
- Pipeline Model Definition:
  - Docker label: docker
- Cloud -> Add Kubernetes:
  - name: something
  - K8s URL: https://kubernetes.default.svc.cluster.local/
  - Kubernetes namespace: jenkins
  - Jenkins URL: http://jenkins/
  - Jenkins tunnel: jenkins-discovery:50000
  - Add pod template:
    - name: jnlp-slave
    - labels: jnlp debian
    - containers:
      - name: jnlp  <- Important!
      - image: gcr.io/bitnami-images/jenkins-jnlp-debian:latest
      - always pull
      - Command: <empty>
      - Arguments: ${computer.jnlpmac} ${computer.name}
      - no tty
      - env vars: DOCKER_HOST=tcp://localhost:2375
  - Add pod template:
    - name: jnlp-docker
    - labels: docker
    - template-to-inherit-from: jnlp
    - containers:
      - name: docker-in-docker
      - image: docker:1.12-dind
      - command: /usr/local/bin/dockerd-entrypoint.sh
      - args: --storage-driver=overlay
      - no tty
      - env vars: http_proxy=http://proxy.webcache:80/  (or whatever)
      - Advanced: Run in privileged mode  <- Important!
    - Volume: Add emptydir volume
      - path: /var/lib/docker
    - time to retain idle: 7  (optional)

Credentials -> Global credentials
- Add: Kubernetes Service Account
  - description: Jenkins Service Account

Github bitnami org
- Github user: bitnami-bot
- Generate a new "repo" scoped personal access token
- Credentials -> Global credentials
- Add: Username with password
  - username: bitnami-bot
  - password: <token from above>
