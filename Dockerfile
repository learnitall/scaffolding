FROM docker.io/fedora:36

RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz
RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && /usr/local/gcloud/google-cloud-sdk/install.sh
RUN dnf install -y --nodocs \
    helm \
    python3-pip && \
  dnf clean all && \
  pip3 install --no-cache-dir \
    ansible-core \
    google-auth \
    requests
RUN curl -LO https://dl.k8s.io/release/v1.24.0/bin/linux/amd64/kubectl && \
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
RUN curl -sSL https://api.github.com/repos/cloud-bulldozer/benchmark-comparison/tarball | tar -xzf - -C /opt && \
  export bc_dir=/opt/$(ls /opt | grep cloud-bulldozer-benchmark-comparison) && \
  pip install $bc_dir && \
  rm -rf $bc_dir
RUN ansible-galaxy collection install \
    community.general \
    google.cloud

COPY . /scaffolding
