# WARNING: SRE Kube Manifests is no longer actively maintained by VMware.
VMware has made the difficult decision to stop driving this project and therefore we will no longer actively respond to issues or pull requests. If you would like to take over maintaining this project independently from VMware, please let us know so we can add a link to your forked project here.

Thank You.

# Bitnami kube-manifests

A collection of misc kubernetes configs for various jobs, as used in
Bitnami's production clusters.  This is probably not useful directly
for anyone else, but we hope it serves as a non-demo example of "real"
Kubernetes configuration.

Most of the code comments and instructions below are intended for
Bitnami employees making changes to our production clusters.

Uses [jsonnet](http://jsonnet.org/) and
[kubectl](https://kubernetes.io/docs/user-guide/prereqs/) command line
tools.  See `Makefile` for a docker container with these installed.


## Cheat Sheet
```
# Rebuild generated json (from jsonnet).
# Any modified files should be included in your git commit.
make build

# Run test-suite
make test

# Create resources
./tools/kubecfg.sh squid.jsonnet create
# Update resources
./tools/kubecfg.sh squid.jsonnet update

# Same thing directly for whatever reason
jsonnet -J lib squid.jsonnet | kubectl replace -f -
# .. or using the generated json
kubectl replace -R -f generated/one.k8s.dev.bitnami.net/squid
```

## Workflow

- Usual github pull-request workflow: Fork the github repo, clone
  locally and make your desired change to the jsonnet files using your
  favourite editor.

- Run `make` to regenerate the JSON.  *Add the generated files to your
  commit*.  You (and your reviewer) can use these to confirm that your
  jsonnet change does what you expect.

- If you need to iterate interactively, you can push your change
  to our `dev` cluster using
  `./tools/kubecfg.sh one.k8s.dev.bitnami.net/foo.jsonnet update`. Try
  to clean up after yourself.

- When ready, push to personal github fork and create a pull request
  in the usual github way.

- Our jenkins instance will run `tests/test_*.sh` and report
  success/failure on the pull-request.

- After jenkins success and appropriate reviewer approval, merge the
  pull request into the `master` branch.

- Jenkins will now automatically run `./tools/deploy.sh` against each
  cluster.

## Tests

`./tests/test_*.sh` will be run against the codebase before merge.

Note that `tests/test_generated.sh` asserts that `generated/` is up to
date, effectively requiring every substantive jsonnet change to run
`tools/rebuild.sh`.

## Directory Layout

The interesting bit is these directories:

```
├── common
│   └── config
├── one.k8s.dev.bitnami.net
│   └── config
├── one.k8s.int.bitnami.net
│   └── config
└── one.k8s.web.bitnami.net
    └── config
```

Most of the configuration is in per-component files in `common/`.
These files are then assembled and "specialised" in per-cluster files
below each of the cluster-named directories.  There is a similar
`foo/config/` directory stack used in a similar way for non-Kubernetes
config files (mostly prometheus at the moment).

The jsonnet files rely heavily on `lib/kube.libsonnet`, which contains
jsonnet black-magic to help construct objects that conform to the
regular Kubernetes (JSON/YAML) API schema.
