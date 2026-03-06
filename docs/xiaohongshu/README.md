# 小红书内容管理

这个目录用于管理 MacBar 的小红书选题、草稿和已发布内容，避免每次都只维护一个孤立的 `docs/xiaohongshu.md`。

## 目录约定

- `docs/xiaohongshu.md`
  当前待发布草稿。默认始终保留最新、可直接发的一篇。
- `docs/xiaohongshu/TEMPLATE.md`
  新稿模板。每次新开一篇时先复制这个结构。
- `docs/xiaohongshu/ideas.md`
  选题池。记录后续想写但还没展开的方向。
- `docs/xiaohongshu/drafts/YYYY-MM-DD-序号-主题.md`
  草稿归档。每次形成一版可读草稿时都落一个文件。
- `docs/xiaohongshu/published/`
  已发布文案归档。发布后再把最终版本移到这里，保留发布时间和平台差异。

## 工作流

1. 新写一篇时，先判断它是全新主题，还是上一条的续篇。
2. 先在 `docs/xiaohongshu/TEMPLATE.md` 基础上起草。
3. 形成一版完整内容后，保存到 `docs/xiaohongshu/drafts/`，文件名带日期和序号。
4. 同时把最新版本同步到 `docs/xiaohongshu.md`，这个文件永远代表“当前待发稿”。
5. 如果用户明确表示某篇已经发布，再把最终定稿复制到 `docs/xiaohongshu/published/`。
6. 每新增一篇，更新下面的内容台账。

## 写作规则

- 如果用户说“这是上一篇的接续”，正文必须承接上一篇，不要重新从零介绍 MacBar。
- 文章重点默认是“产品价值和用户体验”，技术实现只保留用户能感知到的部分。
- 小红书正文虽然保存在 `.md` 文件里，但内容格式按纯文本写，不用 Markdown 标题、列表、加粗、链接语法，避免发布前二次清洗。
- 每篇文案都要明确写出：
  - 这一篇想讲的单一主线
  - 关联改动或使用场景
  - 建议配图
  - 话题标签
- 如果当天有多个改动，优先收敛成一个用户视角主题，不要写成开发日志罗列。

## 内容台账

| 序号 | 状态 | 主题 | 说明 | 文件 |
| --- | --- | --- | --- | --- |
| 001 | 已发布（外部平台） | 我为什么自己做了一个 Mac 剪贴板工具 | 竞品对比 + OCR 动机，源码暂未入库 | 暂无仓库内归档 |
| 002 | 待发布 | 上篇聊为什么做 MacBar，这篇聊我怎么把它改得更顺手了 | 承接上一篇，聚焦今天的交互打磨 | [drafts/2026-03-06-002-ux-polish-followup.md](/Users/patgo/app/MacBar/docs/xiaohongshu/drafts/2026-03-06-002-ux-polish-followup.md) |
