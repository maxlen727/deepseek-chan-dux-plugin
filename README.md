# DeepSeek 鲸鱼娘桌宠 · Dux shell 插件

DeepSeek 的鲸鱼娘「大肥鱼」住进你的 Dux shell（DankMaterialShell 系）桌面：
她会在屏幕底部溜达、玩耍、吃白饭；可以被拖着甩出去，撞墙会反弹；还会定时碎碎念、陪你聊天、提醒待办、
帮你盯着 API 余额。专门为 niri 这类平铺窗口管理器设计，那里普通桌宠窗口很难摆。

动画素材、动作表、物理参数和提示词写法都移植自 [PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet)（MIT），
默认人设参考了网络上 DeepSeek 拟人「鲸鱼娘」的同人形象。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/maxlen727/deepseek-chan-dux-plugin/main/install.sh | bash
```

或者先克隆再装（以后 `git pull` 就能更新）：

```bash
git clone https://github.com/maxlen727/deepseek-chan-dux-plugin.git
cd deepseek-chan-dux-plugin && ./install.sh
```

安装脚本会依次做这些事：

1. **检查依赖**：`git`、`ffmpeg`（需要带 libvpx 和 libwebp，Arch 自带的就行）、`dms`。
2. **安装插件**：把插件链接到 `~/.config/dms/plugins/duxPet`。
3. **准备素材**：从 dsh-pet 拉取原始动画（约 56MB），转换成透明 WebP，大约一两分钟。
4. **交互式配置**：名字、大小、AI 服务商（DeepSeek / OpenRouter / 硅基流动 / Ollama / 自定义）、API Key、
   碎碎念间隔、余额提醒、多屏。API Key 存到 `~/.config/dux-pet/api-key`（权限 600），配置里只记它的路径。
5. **启用插件**：宠物马上出现，不需要添加任何桌面小组件。

其他用法：

```bash
./install.sh --configure          # 只重新配置
./install.sh --yes                # 不提问，全部用默认值
./install.sh --uninstall --purge  # 卸载；--purge 连配置、聊天记录、待办一起删
```

## 原理

- **`PetDaemon.qml`（后台组件）**：插件一启用就把宠物养起来。
  - 配置按顺序取第一个有值的：桌面小组件实例的配置 → 设置 → 插件 → `~/.config/dux-pet/config.json`（安装脚本写的，改了实时生效）→ 默认值。
- **`PetWindow.qml`**：一个整屏透明的 layer surface（`Top` 层，可选 `Overlay`）。
  - `mask` 只包住宠物身体和打开着的面板，其余区域点击穿透。
  - 宠物在这个层里移动，不需要合成器帮它摆窗口，所以在 niri 上也能用。
- **`DesktopPet.qml`**：可选的桌面「小窝」小组件，左键把宠物叫到这块屏，中键睡觉/起来。
  - Dux shell 的桌面小组件窗口在 `Bottom` 层，而且位置固定，所以宠物本身不放在这里。
- **透明动画**：用 `AnimatedImage` 播放动画 WebP；`PetSprite.qml` 用两张图做双缓冲，切换动画时不会闪空白。
  - 原仓库的 VP9-alpha webm 不能直接用：Qt Multimedia 的 FFmpeg 后端会丢掉 alpha 通道。

> 开发提示：改了 `PetWindow.qml` 这类被引用的文件后，`plugin-scan reload` 不会重新加载它们（Qt 会缓存类型），
> 需要执行 `dms restart`。

## 交互

| 操作 | 效果 |
|---|---|
| 左键点击 | Q 弹挤压，随机播一个点击回应；睡着时把它叫醒 |
| 拖拽后松手 | 按松手速度甩出去，碰到屏幕边缘会反弹，落地时有挤压效果 |
| 右键 | 菜单：随便玩、按分类播动作、聊聊天、说句话、待办、转身、睡觉/起来、原地待着/自由走动、回到右下角、去别的屏 |
| 头顶「待办」小牌 | 打开待办面板 |
| 小窝 左键 / 中键 | 叫回来 / 睡觉或起来 |

## 碎碎念与对话

走任意 OpenAI 兼容的 `/chat/completions` 接口（DeepSeek、OpenAI、Ollama 等），在插件设置里填写：

- **人设**：默认是 DeepSeek 鲸鱼娘。她深蓝长发、长着鲸鱼鳍耳、穿女仆装、拖着一条肥嘟嘟的鲸鱼尾巴；聪明但有点懒，
  傲娇嘴甜，最爱白米饭，最讨厌被说胖。在设置的「人设」里可以整段替换。
- **接口地址 / 模型**：默认是 `https://api.deepseek.com` 和 `deepseek-chat`。
- **API Key**：设置文件里存的是明文，所以建议写 `env:变量名` 或 `file:~/路径` 来引用。
  留空时读环境变量 `DEEPSEEK_API_KEY`，前提是 shell 进程能看到这个变量。本地地址（localhost）可以不填 key。
- **碎碎念**：按间隔（默认 300 秒）自己说一句，同时播放碎碎念动画。没配好接口时用内置台词。
  睡觉、聊天框打开、正在被拖着的时候都不会说。
- **对话**：右键菜单选「聊聊天」打开聊天框，先点一下输入框（这时它才拿到键盘焦点），回车发送，Esc 关闭。
  每次请求带上最近 N 轮历史和时间戳。开启「对话时做动作」后，模型可以在回复末尾加 `[动作:名称]`，宠物会当场演出来。
- **聊天记录**：保存在 `~/.local/state/quickshell/by-shell/<hash>/duxPet-chat.json`，最多 200 条，聊天框里的「清空」可以删掉。

提示词（人设拼接、时间背景、碎碎念指令、动作指令）沿用 dsh-pet 的写法，见 `ai.js`。

## 待办

右键菜单选「待办」，或点头顶的小牌，打开待办面板。输入一句话，可以带时间：

`18:30 开会`、`开会 @18:30`、`30分钟后 喝水`、`1.5h 出门`、`下午3点半 取快递`、`明天 9点 交周报`、`明天 交周报`（默认 9:00）、`买牛奶`（不限时）

- **今天的时间已经过了**：自动算成明天的这个时间。
- **到期前**：剩余时间越少，提醒越频繁（间隔是剩余时间的 1/4，最短 2 分钟，最长 1 小时）。
- **到点和过期**：到点时提醒一次，并发一条系统通知（可以在设置里关掉）；过期后每 10 分钟提醒一次。
- **不限时的待办**：每 2 小时提醒一次。
- **睡着时**：不弹提醒气泡，系统通知照常发。
- **完成和删除**：点圆圈算完成，点 ✕ 删除。
- **保存位置**：`duxPet-todos.json`，和聊天记录放在同一个目录。

## 余额

右键菜单「查余额」立刻查一次。打开「定时报余额」后，每隔一段时间（默认 30 分钟）查一次并报出来。
宠物会弹气泡显示余额和一句评价，按已用比例播放 6 档钱袋动画（0–20–40–60–80–100%，用完单独一档）。睡着时不报。

| 服务商 | 接口 | 已用比例怎么算 |
|---|---|---|
| DeepSeek | `GET /user/balance` | 1 − 余额 ÷ 满额参考（默认 ¥20 / $5，和 dsh-pet 一样）；气泡里标出当前是峰时段还是谷时段 |
| OpenRouter | `GET /credits` | 已用 ÷ 总额 |
| 硅基流动 | `GET /user/info` | 1 − 余额 ÷ 满额参考（默认 ¥20） |

- **服务商**：选「自动」时按 AI 接口地址来猜。
- **API Key**：默认和 AI 用同一个，也可以单独填，同样支持 `env:` / `file:`。
- **满额参考**：可以改。比如平时充 ¥100，就填 100。

## 梦话

睡着以后，每隔一段时间（默认 90 秒）嘟囔一句，只弹气泡。配了 AI 就由模型生成（用 dsh-pet 的梦话指令），没配就用内置台词。

## 多屏

宠物在哪些屏出现，由设置里的「宠物出现在哪些屏」决定（填输出名，逗号分隔，留空表示所有屏）。「多屏」有两种模式：

- **一只宠物（默认）**：只有排在最前的那块屏养宠物。它走路或被甩到屏边时，如果那一侧紧挨着另一块屏，
  就会过到那块屏上（换屏时会重建 layer surface）；没有相邻屏的一侧照样是墙。
  其他屏上的小窝点一下，就把宠物叫到那块屏；右键菜单里也有「去 XXX」。
- **每块屏各一只**：每块屏各养一只，互不相干。

## IPC

```bash
dms ipc call duxPet state                 # 当前状态 JSON
dms ipc call duxPet play 玩耍             # 小动作 / 玩耍 / 吃什么 / 时节 / 文字
dms ipc call duxPet say "你好呀"
dms ipc call duxPet whisper               # 立刻碎碎念一句
dms ipc call duxPet chat "今天吃什么"     # 发一句对话，回复用 state 查
dms ipc call duxPet openChat
dms ipc call duxPet todoAdd "18:30 开会" | todoList | todoDone <id> | todoCheck
dms ipc call duxPet balance               # 立刻查余额并报出来；balanceState 看上次结果
dms ipc call duxPet sleepTalk             # 睡着时立刻说一句梦话
dms ipc call duxPet summon eDP-1          # 叫到指定屏
dms ipc call duxPet sleep | wake | home
dms ipc call duxPet toss -- -1800 -1500   # 以给定速度（px/s）把它抛出去；负数前面要加 --
```

「每块屏各一只」模式下，只有排在最前那块屏上的宠物响应 IPC。

## 设置

在「设置 → 插件 → DeepSeek-chan Desktop Pet」里改，或者直接编辑 `~/.config/dux-pet/config.json`。可以设置：
宠物名字和大小、地面高度（底部有 dock 时调高）、随机走动、显示在全屏窗口之上、显示小窝、多屏、AI 接口和人设、
碎碎念、梦话、对话、待办通知、余额查询。

## 致谢与许可

- 动画素材、动作与权重表、物理常量、提示词写法：[PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet)（MIT）
- 本插件代码：MIT，见 [LICENSE](LICENSE)

## 还没做

表情包配图、语音、多只宠物互相碰撞、自定义宠物种类。
