# gentoo-from-scratch

```sh
% docker buildx create \
    --buildkitd-flags '--allow-insecure-entitlement security.insecure' \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1,env.BUILDKIT_STEP_LOG_MAX_SPEED=-1 \
    --name gentoo-builder \
    --use
% docker buildx build --allow security.insecure --build-arg FULL_BOOTSTRAP=1 -o dist .
```

## debug

```sh
% docker buildx build --load --progress plain -t guix --target guix-base . && docker run --rm -it guix
% docker buildx build --load --progress plain -t prefix --target prefix . && docker run --rm -it prefix
% docker buildx build --load --progress plain -t catalyst --target catalyst . && docker run --rm -it --privileged catalyst
```
