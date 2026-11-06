import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "duxPet"

    SliderSetting {
        settingKey: "petSize"
        label: "宠物大小"
        description: "素材帧显示宽度，身体约占三分之一"
        defaultValue: 300
        minimum: 150
        maximum: 600
        unit: "px"
    }

    SliderSetting {
        settingKey: "groundOffset"
        label: "地面高度"
        description: "离屏幕底边的距离，底部有 dock 时调高"
        defaultValue: 0
        minimum: 0
        maximum: 200
        unit: "px"
    }

    ToggleSetting {
        settingKey: "roam"
        label: "随机走动"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "overlayLayer"
        label: "显示在全屏窗口之上"
        description: "关闭时宠物在普通窗口之上、全屏窗口之下"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showHouse"
        label: "显示桌面小窝"
        description: "只对「桌面小组件」里添加的小窝有效（小窝是可选的，宠物不靠它）。关掉后那块区域完全透明、点击穿透"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "multiScreen"
        label: "多屏"
        defaultValue: "single"
        options: [
            { label: "一只宠物，可以走到/甩到相邻屏", value: "single" },
            { label: "每块屏各一只", value: "perScreen" }
        ]
    }

    StringSetting {
        settingKey: "petScreens"
        label: "宠物出现在哪些屏"
        description: "输出名，逗号分隔（niri msg outputs 可查，如 eDP-1,HDMI-A-1）；留空 = 所有屏，一只宠物模式下从第一块屏出生"
        placeholder: "所有屏"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "petName"
        label: "宠物名字"
        defaultValue: "大肥鱼"
    }

    StringSetting {
        settingKey: "aiBaseUrl"
        label: "AI 接口地址"
        description: "OpenAI 兼容接口，例如 https://api.deepseek.com、https://api.openai.com/v1、http://localhost:11434/v1（Ollama）"
        placeholder: "https://api.deepseek.com"
        defaultValue: "https://api.deepseek.com"
    }

    StringSetting {
        settingKey: "aiModel"
        label: "模型"
        placeholder: "deepseek-chat"
        defaultValue: "deepseek-chat"
    }

    StringSetting {
        settingKey: "aiApiKey"
        label: "API Key"
        description: "会明文存进设置文件。建议写 env:变量名 或 file:/路径 来引用；留空则读环境变量 DEEPSEEK_API_KEY"
        placeholder: "env:DEEPSEEK_API_KEY"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "persona"
        label: "人设"
        description: "系统提示词；留空用默认的 DeepSeek 鲸鱼娘。名字和当前时间会自动附上"
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "whisperEnabled"
        label: "碎碎念"
        description: "定时自己说一句；没配 AI 时用内置台词"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "whisperIntervalSec"
        label: "碎碎念间隔"
        defaultValue: 300
        minimum: 30
        maximum: 1800
        unit: "秒"
    }

    SliderSetting {
        settingKey: "chatMemoryRounds"
        label: "对话记忆轮数"
        description: "每次对话带上最近几轮历史（1 轮 = 一问一答）"
        defaultValue: 10
        minimum: 0
        maximum: 30
    }

    ToggleSetting {
        settingKey: "sleepTalkEnabled"
        label: "说梦话"
        description: "睡着时隔一阵嘟囔一句，只弹气泡"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "sleepTalkSec"
        label: "梦话间隔"
        defaultValue: 90
        minimum: 20
        maximum: 600
        unit: "秒"
    }

    ToggleSetting {
        settingKey: "todoNotify"
        label: "待办到期发系统通知"
        description: "到点时额外弹一条 notify-send 通知（睡着也会发）"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "chatAnimationEnabled"
        label: "对话时做动作"
        description: "让模型在合适的时候挑一个动作演出来"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "balanceProvider"
        label: "余额查询"
        description: "按已用比例播 6 档钱袋动画并报余额；「自动」按 AI 接口地址猜"
        defaultValue: "auto"
        options: [
            { label: "自动", value: "auto" },
            { label: "DeepSeek", value: "deepseek" },
            { label: "OpenRouter", value: "openrouter" },
            { label: "硅基流动", value: "siliconflow" },
            { label: "关闭", value: "off" }
        ]
    }

    StringSetting {
        settingKey: "balanceApiKey"
        label: "余额查询用的 API Key"
        description: "留空 = 和 AI 用同一个；同样支持 env: / file:"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "balanceFull"
        label: "满额参考（元 / 美元）"
        description: "余额等于这个数算「满」，用来算已用比例。留空 = DeepSeek 按 ¥20 / $5，硅基流动按 ¥20；OpenRouter 用账户总额，不看这里"
        placeholder: "20"
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "balanceAuto"
        label: "定时报余额"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "balanceIntervalSec"
        label: "报余额间隔"
        defaultValue: 1800
        minimum: 300
        maximum: 7200
        unit: "秒"
    }

    StringSetting {
        settingKey: "balanceBaseUrl"
        label: "余额接口地址（可选）"
        description: "走代理或自建转发时才需要改，留空用服务商官方地址"
        defaultValue: ""
    }
}
