# tv-recyclerview patch repo

这个目录是给 `com.owen:tv-recyclerview:3.0.0` 做补丁 AAR 用的。

## 已放入的内容

- `original/tv-recyclerview-3.0.0-original.aar`
  原始 AAR
- `scripts/build_patched_aar.sh`
  GitHub Actions / 本地共用的构建脚本
- `.github/workflows/build-aar.yml`
  GitHub Actions 工作流

## 目标

自动完成下面的事情：

1. 解包原始 AAR
2. 解包 `classes.jar`
3. 反编译 `TvRecyclerView.class`
4. 给 `getLastVisibleAndFocusablePosition()` 补 `LayoutManager == null` 判空
5. 重新编译 `TvRecyclerView.java`
6. 替换 `classes.jar` 里的 `TvRecyclerView*.class`
7. 重打出新的 AAR

输出目录：`dist/`

输出文件名：`tv-recyclerview-3.0.0-patched.aar`

## 直接用 GitHub 打包

把整个 `TvRecyclerView` 目录上传到 GitHub 仓库后：

1. 打开仓库的 `Actions`
2. 运行 `Build patched tv-recyclerview aar`
3. 在 Actions Artifacts 里下载 `patched-aar`

## 说明

这个仓库走的是“定点补丁”路线，不需要你先找到原始源码仓库。

如果后面你想长期维护这个库，建议再演进成完整的 Android library module。
