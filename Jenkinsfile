#!groovy

node('docker') {
  def testEnv
  stage('Build') {
    checkout scm

    testEnv = docker.build('jsonnettest',
                           "--build-arg=http_proxy=${env.http_proxy} tests")
  }

  stage('Test') {
    parallel(fmt: {
               testEnv.inside {
                 sh 'tests/test_fmt.sh'
               }
             },
             generated: {
               testEnv.inside {
                 sh 'tests/test_generated.sh'
               }
             },
             validate: {
               withKubeApi(testEnv) {
                 sh 'KUBERNETES_SERVICE_PORT=443 tests/test_valid.sh'
               }
             },
             prometheus: {
               docker.image('prom/prometheus:v1.4.1').inside {
                 sh 'tests/test_prom_rules.sh'
               }
             },
      )
  }

  if (env.BRANCH_NAME == "master") {
    stage('Deploy') {
      withKubeApi(testEnv) {
        // I don't understand why KUBERNETES_SERVICE_PORT doesn't
        // survive withEnv, but I swear it "disappears".
        sh 'KUBERNETES_SERVICE_PORT=443 tools/deploy.sh one.k8s.dev.bitnami.net'
      }
    }
  }
}

def withKubeApi(img, c) {
  def tokenDir = '/var/run/secrets/kubernetes.io/serviceaccount'
  img.inside("-v ${tokenDir}:${tokenDir}") {
    // kubectl writes things to $HOME/.kube - more than just $KUBECONFIG :(
    withEnv(["HOME=${env.WORKSPACE}",
             'KUBERNETES_SERVICE_HOST=kubernetes.default.svc.cluster.local',
             'KUBERNETES_SERVICE_PORT=443']) {
      c()
    }
  }
}
