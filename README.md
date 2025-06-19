# gentoo-from-scratch

```sh
% docker buildx create \
    --buildkitd-flags '--allow-insecure-entitlement security.insecure' \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1,env.BUILDKIT_STEP_LOG_MAX_SPEED=-1 \
    --name gentoo-builder \
    --use
% docker buildx build --allow security.insecure . -o dist
```
