#!/bin/bash -e

install_with_retry() {
  local max_attempts=5
  local attempt_count=1

  while ! dnf install -y "$@"; do
    if [ "$attempt_count" -ge "$max_attempts" ]; then
      echo "Failed to install $* after $max_attempts attempts" >&2
      return 1
    fi

    attempt_count=$((attempt_count + 1))
    echo "Failed to install $*; retrying $attempt_count/$max_attempts" >&2
    sleep 5
  done
}

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# AWS suggest to create a log for debug purpose based on https://aws.amazon.com/premiumsupport/knowledge-center/ec2-linux-log-user-data/
# As side effect all command, set +x disable debugging explicitly.
#
# An alternative for masking tokens could be: exec > >(sed 's/--token\ [^ ]* /--token\ *** /g' > /var/log/user-data.log) 2>&1

set +x

%{ if enable_debug_logging }
set -x
%{ endif }

${pre_install}

max_attempts=5
attempt_count=1
while ! dnf upgrade-minimal -y; do
  if [ "$attempt_count" -ge "$max_attempts" ]; then
    echo "Failed to run dnf upgrade-minimal -y after $max_attempts attempts" >&2
    exit 1
  fi

  attempt_count=$((attempt_count + 1))
  echo "Failed to run dnf upgrade-minimal -y; retrying $attempt_count/$max_attempts" >&2
  sleep 5
done

# Install docker
install_with_retry docker

service docker start
usermod -a -G docker ec2-user

install_with_retry amazon-cloudwatch-agent jq git
install_with_retry --allowerasing curl

user_name=ec2-user

${install_runner}

${post_install}

# Register runner job hooks
# Ref: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/running-scripts-before-or-after-a-job
%{ if hook_job_started != "" }
cat > /opt/actions-runner/hook_job_started.sh <<'EOF'
${hook_job_started}
EOF
echo ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hook_job_started.sh | tee -a /opt/actions-runner/.env
%{ endif }

%{ if hook_job_completed != "" }
cat > /opt/actions-runner/hook_job_completed.sh <<'EOF'
${hook_job_completed}
EOF
echo ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/actions-runner/hook_job_completed.sh | tee -a /opt/actions-runner/.env
%{ endif }

${start_runner}
