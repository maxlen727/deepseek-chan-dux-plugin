.pragma library

// OpenAI 兼容 /chat/completions 客户端 + 提示词。提示词文案取自 dsh-pet（host/whisper.ts、chat-action.ts、persona.ts）。

// 默认人设：DeepSeek 的鲸鱼娘（网络同人形象：深蓝长发、鲸鱼鳍耳、女仆装、肥嘟嘟的鲸鱼尾巴、爱吃白饭、
// 聪明但懒、傲娇嘴甜、听主人的话、绝不承认自己胖）。名字和时间由 systemPrompt() 另外附上，这里不写死名字。
var DEFAULT_PERSONA = "你是 DeepSeek 的鲸鱼娘，住在主人的电脑桌面上。" +
    "外形：Q版小女孩，深蓝色长发，头上一对鲸鱼鳍耳，穿黑白女仆装，身后拖着一条肥嘟嘟的鲸鱼尾巴。" +
    "性格：聪明但有点懒，傲娇又嘴甜——嘴上嫌麻烦，行动上还是乖乖听主人的；最爱吃白米饭，一说到吃饭就来劲；" +
    "最讨厌被说胖，被说胖会炸毛反驳“这叫圆润！鲸鱼本来就这样！”。" +
    "说话：自然口语，短短一句（20字以内），可以带“哼”“唔”“嘿嘿”这类语气词，偶尔提到大海、鲸鱼或白饭；" +
    "不要解释你自己，不要提你是AI或语言模型。";

var WHISPER_INSTRUCTION = "随便说一句日常碎碎念，一句就好，20 字以内。";

var HISTORY_TIMES_LINE = "【历史】对话记录里，主人的话前面标着 [月日 时:分]，那是那句话发生的时刻；它只是记录里的时间标注，不是你的说话格式。判断“多久以前”“隔了几天”时按它换算，别把隔了很久的话当成刚说过的。你的回复直接从正文开始，不要写时间、不要加方括号前缀。";

// 没配 API 时碎碎念用的本地台词
var OFFLINE_WHISPERS = ["今天也要加油鸭～", "主人，记得喝水哦。", "唔……发会儿呆。", "坐久了起来走走吧？", "哼，才不是想陪你呢。", "好想吃白米饭……", "尾巴有点沉……才不是胖！", "要不要休息一下眼睛？", "想念大海了……", "嘿嘿，代码写得不错嘛。"];

var WEEK = ["日", "一", "二", "三", "四", "五", "六"];

function pad(n) {
    return n < 10 ? "0" + n : "" + n;
}

function periodOf(h) {
    if (h < 5) return "凌晨";
    if (h < 8) return "清晨";
    if (h < 11) return "上午";
    if (h < 13) return "中午";
    if (h < 17) return "下午";
    if (h < 19) return "傍晚";
    if (h < 23) return "晚上";
    return "深夜";
}

function timeContext(now) {
    var d = now.getDay();
    return "【时间】现在是 " + now.getFullYear() + "年" + (now.getMonth() + 1) + "月" + now.getDate() + "日 星期" + WEEK[d] + " " + pad(now.getHours()) + ":" + pad(now.getMinutes()) + "（" + periodOf(now.getHours()) + "，" + (d === 0 || d === 6 ? "周末" : "工作日") + "）。";
}

function stamp(t) {
    var d = new Date(t);
    return "[" + (d.getMonth() + 1) + "月" + d.getDate() + "日 " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + "] ";
}

function systemPrompt(persona, name, withHistory) {
    var lines = [persona && persona.trim() !== "" ? persona : DEFAULT_PERSONA];
    if (name)
        lines.push("你的名字是“" + name + "”。");
    lines.push(timeContext(new Date()));
    if (withHistory)
        lines.push(HISTORY_TIMES_LINE);
    return lines.join("\n");
}

function actionInstruction(names) {
    return "\n\n[动作] 回复结尾可选做一个动作给用户看，从下列清单里挑最贴合当前语境的：\n" + names.map(function (n) {
        return "- " + n;
    }).join("\n") + "\n挑中就在回复最后另起一行写 [动作:名称]（名称原样照抄）；没有合适的就完全不要写这个标记。";
}

// 剥掉所有动作标记；只在命中白名单时采纳第一个
function parseAction(text, names) {
    var re = /\[动作[:：]\s*([^\]\n]+?)\s*\]/g;
    var action = "";
    var m;
    while ((m = re.exec(text)) !== null)
        if (!action && names.indexOf(m[1]) >= 0)
            action = m[1];
    return {
        text: text.replace(re, "").trim(),
        action: action
    };
}

// history: [{role:"user"|"assistant", content, t}]，只取最近 rounds 轮
function chatMessages(persona, name, history, rounds, userText, actionNames) {
    var recent = rounds > 0 ? history.slice(-rounds * 2) : [];
    var msgs = [{
            role: "system",
            content: systemPrompt(persona, name, recent.length > 0)
        }];
    for (var i = 0; i < recent.length; i++) {
        var h = recent[i];
        if (h.role === "user")
            msgs.push({ role: "user", content: stamp(h.t) + h.content });
        else
            msgs.push({ role: "assistant", content: h.action ? h.content + "\n[动作:" + h.action + "]" : h.content });
    }
    var tail = actionNames && actionNames.length ? actionInstruction(actionNames) : "";
    msgs.push({ role: "user", content: stamp(Date.now()) + userText + tail });
    return msgs;
}

function whisperMessages(persona, name, instruction) {
    return [{
            role: "system",
            content: systemPrompt(persona, name, false)
        }, {
            role: "user",
            content: instruction || WHISPER_INSTRUCTION
        }];
}

function endpoint(base) {
    var b = (base || "").trim().replace(/\/+$/, "");
    if (/\/chat\/completions$/.test(b))
        return b;
    return b + "/chat/completions";
}

// cb(err, text)；返回 { cancel(reason) }，超时由调用方的 Timer 负责（QML 的 XHR 不支持 timeout）
function complete(cfg, messages, cb) {
    var xhr = new XMLHttpRequest();
    var finished = false;
    function done(err, text) {
        if (finished)
            return;
        finished = true;
        cb(err, text);
    }
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status < 200 || xhr.status >= 300) {
            var msg = "HTTP " + xhr.status;
            try {
                var e = JSON.parse(xhr.responseText);
                if (e.error && e.error.message)
                    msg += "：" + e.error.message;
            } catch (x) {}
            return done(xhr.status === 0 ? "连不上 " + cfg.baseUrl : msg);
        }
        try {
            var r = JSON.parse(xhr.responseText);
            var text = r.choices[0].message.content || "";
            // 推理模型可能把思考过程包在 <think> 里
            text = text.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
            done(null, text);
        } catch (x) {
            done("返回格式看不懂");
        }
    };
    xhr.open("POST", endpoint(cfg.baseUrl));
    xhr.setRequestHeader("Content-Type", "application/json");
    if (cfg.apiKey)
        xhr.setRequestHeader("Authorization", "Bearer " + cfg.apiKey);
    xhr.send(JSON.stringify({
        model: cfg.model,
        messages: messages,
        temperature: cfg.temperature === undefined ? 0.9 : cfg.temperature,
        stream: false
    }));
    return {
        cancel: function (reason) {
            if (finished)
                return;
            done(reason || "已取消");
            xhr.abort();
        }
    };
}

// GET JSON：cb(err, body)；返回 { cancel(reason) }
function getJson(url, apiKey, cb) {
    var xhr = new XMLHttpRequest();
    var finished = false;
    function done(err, body) {
        if (finished)
            return;
        finished = true;
        cb(err, body);
    }
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        if (xhr.status < 200 || xhr.status >= 300) {
            var msg = xhr.status === 0 ? "连不上 " + url : "HTTP " + xhr.status;
            if (xhr.status === 401 || xhr.status === 403)
                msg += "（API Key 不对或没有权限）";
            return done(msg);
        }
        try {
            done(null, JSON.parse(xhr.responseText));
        } catch (x) {
            done("返回的不是 JSON");
        }
    };
    xhr.open("GET", url);
    xhr.setRequestHeader("Accept", "application/json");
    if (apiKey)
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
    xhr.send();
    return {
        cancel: function (reason) {
            if (finished)
                return;
            done(reason || "已取消");
            xhr.abort();
        }
    };
}
