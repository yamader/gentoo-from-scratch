# gentoo-from-scratch

```sh
% docker buildx create \
    --buildkitd-flags '--allow-insecure-entitlement security.insecure' \
    --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1,env.BUILDKIT_STEP_LOG_MAX_SPEED=-1 \
    --name gentoo-builder \
    --use
% docker buildx build --allow security.insecure --progress plain -o dist .
```

## Rust

todo: そのうち自動化する

```sh
USE='mrustc-bootstrap system-llvm' emerge -1j dev-lang/rust:1.74.1
```

`llvm-core/llvm:17`に当てるpatch💩

```diff
--- a/llvm/tools/sancov/sancov.cpp
+++ b/llvm/tools/sancov/sancov.cpp
@@ -505,7 +505,7 @@
   static std::unique_ptr<SpecialCaseList> createUserIgnorelist() {
     if (ClIgnorelist.empty())
       return std::unique_ptr<SpecialCaseList>();
-    return SpecialCaseList::createOrDie({{ClIgnorelist}},
+    return SpecialCaseList::createOrDie({ClIgnorelist},
                                         *vfs::getRealFileSystem());
   }
   std::unique_ptr<SpecialCaseList> DefaultIgnorelist;
```
