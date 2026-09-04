# shellcheck shell=bash

## install the runner

s3_location=${S3_LOCATION_RUNNER_DISTRIBUTION}

if [ -z "$RUNNER_TARBALL_URL" ] && [ -z "$s3_location" ]; then
  echo "Neither RUNNER_TARBALL_URL or s3_location are set"
  exit 1
fi

file_name="actions-runner.tar.gz"

echo "Setting up GH Actions runner tool cache"
# Required for various */setup-* actions to work, location is also know by various environment
# variable names in the actions/runner software : RUNNER_TOOL_CACHE / RUNNER_TOOLSDIRECTORY / AGENT_TOOLSDIRECTORY
# Warning, not all setup actions support the env vars and so this specific path must be created regardless
mkdir -p /opt/hostedtoolcache

echo "Creating actions-runner directory for the GH Action installation"
cd /opt/
mkdir -p actions-runner && cd actions-runner


if [[ -n "$RUNNER_TARBALL_URL" ]]; then
  echo "Downloading the GH Action runner from $RUNNER_TARBALL_URL to $file_name"
  curl -s -o $file_name -L "$RUNNER_TARBALL_URL"
else
  # The IMDS token is a credential. Do not expose it when user-data debug
  # logging enabled shell tracing earlier in the bootstrap.
  set +x
  echo "Retrieving TOKEN from AWS API"
  token="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 180")"

  region="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)"
  echo "Retrieved REGION from AWS API ($region)"

  echo "Downloading the GH Action runner from s3 bucket $s3_location"
  aws s3 cp "$s3_location" "$file_name" --region "$region" --no-progress
fi

echo "Un-tar action runner"
tar xzf ./$file_name
echo "Delete tar file"
rm -rf $file_name

os_id=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
echo OS: $os_id

# Install libicu on non-ubuntu, non-debian
if [[ ! "$os_id" =~ ^(ubuntu|debian).* ]]; then
  max_attempts=5
  attempt_count=1
  while ! dnf install -y libicu; do
    if [ "$attempt_count" -ge "$max_attempts" ]; then
      echo "Failed to install libicu after $max_attempts attempts" >&2
      exit 1
    fi

    attempt_count=$((attempt_count + 1))
    echo "Failed to install libicu; retrying $attempt_count/$max_attempts" >&2
    sleep 5
  done
fi

# Install dependencies for ubuntu and debian
if [[ "$os_id" =~ ^(ubuntu|debian).* ]]; then
    echo "Installing dependencies"
    ./bin/installdependencies.sh
fi

echo "Set file ownership of action runner"
chown -R "$user_name":"$user_name" /opt/actions-runner
chown -R "$user_name":"$user_name" /opt/hostedtoolcache
