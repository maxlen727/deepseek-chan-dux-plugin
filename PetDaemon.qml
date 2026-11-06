import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "pet.js" as Pet

// 后台组件：插件一启用宠物就出现，不依赖桌面小组件（小窝只是可选的遥控器）。
//
// 配置按顺序取第一个有值的：
//   1. 桌面小组件实例的配置（从小组件那边打开设置时写在这里）
//   2. 「设置 → 插件 → Dux Pet」的全局配置
//   3. ~/.config/dux-pet/config.json（安装脚本写的，改了实时生效）
//   4. 内置默认值
PluginComponent {
    id: root

    // ---------------------------------------------------------------- 配置

    property int settingsRev: 0
    Connections {
        target: SettingsData
        function onPluginSettingsChanged() {
            root.settingsRev++;
        }
        function onDesktopWidgetInstancesChanged() {
            root.settingsRev++;
        }
    }

    property var fileCfg: ({})
    FileView {
        id: cfgFile
        path: Quickshell.env("HOME") + "/.config/dux-pet/config.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.fileCfg = c && typeof c === "object" ? c : {};
            } catch (e) {
                console.warn("[duxPet] config.json 解析失败：", e);
            }
        }
        onLoadFailed: root.fileCfg = ({})
    }

    // 文件不存在时 watchChanges 盯不住，过一会儿再试（安装脚本稍后才写它）
    Timer {
        interval: 5000
        repeat: true
        running: !cfgFile.loaded
        onTriggered: cfgFile.reload()
    }

    readonly property var instanceCfg: {
        root.settingsRev;
        const inst = (SettingsData.desktopWidgetInstances || []).find(i => i.widgetType === "duxPet");
        return inst?.config ?? {};
    }

    function cfg(key, def) {
        root.settingsRev;
        let v = instanceCfg[key];
        if (v === undefined || v === null || v === "")
            v = SettingsData.getPluginSetting("duxPet", key, undefined);
        if (v === undefined || v === null || v === "")
            v = fileCfg[key];
        return v === undefined || v === null || v === "" ? def : v;
    }

    readonly property int petSize: Number(cfg("petSize", 300))
    readonly property bool roam: cfg("roam", true)
    readonly property bool overlayLayer: cfg("overlayLayer", false)
    readonly property int groundOffset: Number(cfg("groundOffset", 0))
    readonly property string multiScreen: cfg("multiScreen", "single")
    readonly property string petScreens: cfg("petScreens", "")
    readonly property string petName: cfg("petName", "大肥鱼")
    readonly property string aiBaseUrl: cfg("aiBaseUrl", "https://api.deepseek.com")
    readonly property string aiApiKey: cfg("aiApiKey", "")
    readonly property string aiModel: cfg("aiModel", "deepseek-chat")
    readonly property string persona: cfg("persona", "")
    readonly property bool whisperEnabled: cfg("whisperEnabled", true)
    readonly property int whisperIntervalSec: Number(cfg("whisperIntervalSec", 300))
    readonly property int chatMemoryRounds: Number(cfg("chatMemoryRounds", 10))
    readonly property bool chatAnimationEnabled: cfg("chatAnimationEnabled", true)
    readonly property bool sleepTalkEnabled: cfg("sleepTalkEnabled", true)
    readonly property int sleepTalkSec: Number(cfg("sleepTalkSec", 90))
    readonly property bool todoNotify: cfg("todoNotify", true)
    readonly property string balanceProvider: cfg("balanceProvider", "auto")
    readonly property string balanceApiKey: cfg("balanceApiKey", "")
    readonly property string balanceBaseUrl: cfg("balanceBaseUrl", "")
    readonly property real balanceFull: Number(cfg("balanceFull", 0)) || 0
    readonly property bool balanceAuto: cfg("balanceAuto", true)
    readonly property int balanceIntervalSec: Number(cfg("balanceIntervalSec", 1800))

    // ---------------------------------------------------------------- 屏幕

    // petScreens：逗号分隔的输出名（如 "eDP-1,HDMI-A-1"），空 = 所有屏
    readonly property var allowedScreens: {
        const names = petScreens.split(",").map(s => s.trim()).filter(s => s !== "");
        const list = names.length ? Quickshell.screens.filter(s => names.indexOf(s.name) >= 0) : Quickshell.screens.slice();
        return list.length ? list : Quickshell.screens.slice();
    }
    readonly property var hostScreens: multiScreen === "perScreen" ? allowedScreens : allowedScreens.slice(0, 1)

    Variants {
        model: root.hostScreens

        PetWindow {
            required property var modelData
            screen: modelData
            allowedScreens: root.multiScreen === "perScreen" ? [modelData] : root.allowedScreens
            isPrimary: modelData === root.allowedScreens[0]
            petSize: root.petSize
            roam: root.roam
            overlayLayer: root.overlayLayer
            groundOffset: root.groundOffset
            petName: root.petName
            aiBaseUrl: root.aiBaseUrl
            // 没填 key 时退回常见环境变量，方便已经 export 过的人
            aiApiKey: root.aiApiKey !== "" ? root.aiApiKey : "env:DEEPSEEK_API_KEY"
            aiModel: root.aiModel
            persona: root.persona
            whisperEnabled: root.whisperEnabled
            whisperIntervalSec: root.whisperIntervalSec
            chatMemoryRounds: root.chatMemoryRounds
            chatAnimationEnabled: root.chatAnimationEnabled
            sleepTalkEnabled: root.sleepTalkEnabled
            sleepTalkSec: root.sleepTalkSec
            todoNotify: root.todoNotify
            balanceProvider: root.balanceProvider
            balanceApiKey: root.balanceApiKey
            balanceBaseUrl: root.balanceBaseUrl
            balanceFull: root.balanceFull
            balanceAuto: root.balanceAuto
            balanceIntervalSec: root.balanceIntervalSec
        }
    }
}
