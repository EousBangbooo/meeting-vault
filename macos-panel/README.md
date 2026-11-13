# Meeting Vault · macOS 常驻浮窗

默认是一条 256 × 34 点的状态条。你可以在元宝和审核窗口之间切换，从浮窗直接看到待审、审核中和待你决定。鼠标移上去可置顶、展开或关闭。展开会显示当前会议、下一步和「查看详情」。关闭浮窗后，可从菜单栏恢复。

浮窗读取会议库中的 `inbox/` 和 `.meeting-review/`。会议转写由已有剪贴板监听器或其他入箱流程写入，审核与确认仍在原审核窗口进行。读取中断时，浮窗会标出过期状态。可从菜单栏重新选择会议库或手动刷新。

## 从源码运行

需要 **macOS 13 或更高版本**和 Xcode Command Line Tools（需包含 Swift）。在仓库根目录运行。已有会议库的用户请将 `vault_path` 设为自己的绝对路径。

```bash
vault_path="$HOME/MeetingVault"
./bin/setup.sh "$vault_path"
./macos-panel/build.sh
open -g -a "$PWD/macos-panel/MeetingVaultPanel.app" --args --vault "$vault_path"
```

构建脚本在本地生成 App 并用临时签名签署；此方式不添加登录项。通过菜单栏选择「退出 Meeting Vault」可以结束运行。若已有浮窗进程运行，第二份实例会退出；需要切换会议库时可用菜单栏「选择会议库…」。

`./macos-panel/test.sh` 使用 Python 3 生成虚构测试数据，验证状态、去重、刷新和权限错误，不需启动浮窗。

## English

The optional compact status panel reads `inbox/` and `.meeting-review/` in your Meeting Vault. It shows pending, in-review, and awaiting-decision counts. Hover to reveal pin, expand, and close controls. Expand to see the current meeting and its next step. Use the macOS menu bar to restore the panel or select a vault.

The commands above initialize a vault, build the app with Swift on macOS 13 or later, and launch it against your vault. Set `vault_path` to the absolute path of an existing vault if you have one. Use the menu bar to quit. The optional clipboard watcher and your existing review workflow continue to handle capture and review. `./macos-panel/test.sh` requires Python 3 and uses generated fixtures.
