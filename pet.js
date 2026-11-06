.pragma library

// 动画目录与物理参数，取自 dsh-pet 的 assets/config.jsonc 与 src/shared/physics。

var IDLE = "待机呼吸休闲";
var TURN = "东张西望";
var DRAG = "被鼠标拖拽悬空反馈";
var CLICKS = ["点击回应-开心跃动", "点击回应-害羞惊讶", "点击回应-傲娇生气", "点击回应-挠痒咯咯笑", "点击回应-元气挥手"];
var SLEEP = { start: "睡觉-开始", loop: "睡觉-循环", end: "睡觉-起来" };

var MOVE_DEFAULT = { minDist: 60, maxDist: 240, margin: 20, leadSec: 2, tailSec: 2 };
var MOVES = [
    { name: "螃蟹走路" },
    { name: "原地漂浮踏步", params: { minDist: 40, maxDist: 120 } },
    { name: "原地左转奔跑", params: { minDist: 120, maxDist: 320, leadSec: 1.75, tailSec: 4.8 } }
];

var CATEGORIES = [
    { id: "小动作", weight: 20, actions: ["悠闲哼歌", "超大伸懒腰", "原地敲击桌面互动", "原地重力下蹲压缩", "哈欠连天", "原地小憩沉眠", "女仆屈膝礼仪", "被吓一跳", "小幅度原地360度旋转展示", "偷吃零食被抓住", "用鲸鱼尾巴拍打地面", "打瞌睡被惊醒", "照镜子", "整体换装试色", "轻快记录", "写代码", "摇扇纳凉", "晨间刷牙"] },
    { id: "玩耍", weight: 20, actions: ["原地专心玩魔方", "原地蹲下玩玩具汽车", "鲸鱼吐泡泡特效", "原地跳跃抓碎头顶物品", "玩游戏气急败坏", "玩水枪", "小提琴演奏", "蓝鲸现世", "优雅女仆舞", "轻快摇摆舞", "可爱宅舞", "吹气球", "动物环绕", "放风筝", "拆礼物", "变鸽子", "扑克魔术", "抽陀螺", "吹笛子", "蝴蝶蜜蜂环绕头顶开花", "撸猫", "凭空生花", "骑木马", "三球抛接", "踢毽子", "下五子棋", "荡秋千"] },
    { id: "吃什么", weight: 16, actions: ["吃白饭", "大口吃零食", "吃Token", "吃早餐", "吃午餐", "吃晚餐", "吃冰淇淋融化", "吃大闸蟹", "吃糖葫芦", "吃长寿面", "吃西瓜", "涮火锅"] },
    { id: "时节", weight: 14, actions: ["被落叶淹没", "中秋赏月吃月饼", "堆雪人", "放烟花", "吃粽子", "吃年糕", "吃青团", "吃腊八粥", "吃重阳糕", "收红包", "写福字", "穿针乞巧", "舞狮头", "讨糖南瓜灯", "插茱萸赏菊", "放河灯", "萌化小幽灵", "装点圣诞树", "放孔明灯", "吃汤圆", "吃饺子"] },
    { id: "文字", weight: 10, noMirror: true, actions: ["是啊，吃什么", "深度思考碎碎念"] }
];

var WEIGHTS = { idle: 10, turn: 5, move: 5 };

var SLEEP_START_TEXTS = ["好困……我先睡一会儿。", "那我去睡啦，晚安。"];
var SLEEP_END_TEXTS = ["唔……我醒了。", "睡饱啦，主人！"];
var SLEEP_REFUSE_TEXTS = ["我在睡觉，别烦我……", "唔……让我再睡一会儿。", "呼……呼……（装作没听见）"];

// 素材帧为 640x360 设计稿；命中框（身体）在设计稿里的位置。
var HIT_BOX = { x0: 200, y0: 50, x1: 440, y1: 335 };
var FPS = 15;

var PHYSICS = {
    gravity: 1400,
    restitution: 0.78,
    groundFriction: 2.5,
    restNormal: 40,
    restTangent: 15,
    deadZoneSpeed: 500,
    maxThrowSpeed: 3600,
    releaseWindowMs: 150,
    dragThreshold: 5,
    maxStepDt: 0.05,
    substepPx: 8,
    substepMax: 64
};

var SQ_DURATION_MS = 220;
var SQ_SQUASH = 0.55;

function pick(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
}

function rand(a, b) {
    return a + Math.random() * (b - a);
}

function categoryOf(name) {
    for (var i = 0; i < CATEGORIES.length; i++)
        if (CATEGORIES[i].actions.indexOf(name) >= 0)
            return CATEGORIES[i];
    return null;
}

function noMirror(name) {
    var c = categoryOf(name);
    return !!(c && c.noMirror);
}

// 按权重抽下一个动作：{ kind: "idle"|"turn"|"move"|"action", name, move? }
function nextAction(allowMove) {
    var pool = [{ kind: "idle", w: WEIGHTS.idle }, { kind: "turn", w: WEIGHTS.turn }];
    if (allowMove)
        pool.push({ kind: "move", w: WEIGHTS.move });
    for (var i = 0; i < CATEGORIES.length; i++)
        pool.push({ kind: "action", w: CATEGORIES[i].weight, cat: CATEGORIES[i] });
    var total = 0;
    for (var j = 0; j < pool.length; j++)
        total += pool[j].w;
    var r = Math.random() * total;
    var hit = pool[pool.length - 1];
    for (var k = 0; k < pool.length; k++) {
        r -= pool[k].w;
        if (r < 0) {
            hit = pool[k];
            break;
        }
    }
    if (hit.kind === "idle")
        return { kind: "idle", name: IDLE };
    if (hit.kind === "turn")
        return { kind: "turn", name: TURN };
    if (hit.kind === "move") {
        var m = pick(MOVES);
        var p = {};
        for (var key in MOVE_DEFAULT)
            p[key] = (m.params && m.params[key] !== undefined) ? m.params[key] : MOVE_DEFAULT[key];
        return { kind: "move", name: m.name, move: p };
    }
    return { kind: "action", name: pick(hit.cat.actions) };
}

// 落地挤压深度：撞击越快压得越扁（dsh-pet landingSquash）。
function landingSquash(speed) {
    var t = Math.min(Math.max((Math.abs(speed) - 300) / (1500 - 300), 0), 1);
    return Math.min(0.8, 1 - t * (1 - 0.55));
}

// 挤压回弹曲线：先 ease-in 压扁，再 easeOutBack 回弹（dsh-pet squashScale）。
function squashScale(u, squash) {
    if (u < 0.45) {
        var p = u / 0.45;
        return 1 - (1 - squash) * p * p;
    }
    var q = (u - 0.45) / 0.55;
    var c1 = 1.70158, c3 = c1 + 1;
    var f = 1 + c3 * Math.pow(q - 1, 3) + c1 * Math.pow(q - 1, 2);
    return Math.min(1.12, squash + (1 - squash) * Math.max(f, 0));
}

// 拖拽轨迹估算松手速度：取最近 releaseWindowMs 内首尾两点。
function releaseVelocity(trail, now) {
    var win = [];
    for (var i = 0; i < trail.length; i++)
        if (now - trail[i].t <= PHYSICS.releaseWindowMs)
            win.push(trail[i]);
    if (win.length < 2)
        return { vx: 0, vy: 0 };
    var a = win[0], b = win[win.length - 1];
    var dt = Math.max(20, b.t - a.t) / 1000;
    var vx = (b.x - a.x) / dt, vy = (b.y - a.y) / dt;
    var sp = Math.sqrt(vx * vx + vy * vy);
    if (sp < PHYSICS.deadZoneSpeed)
        return { vx: 0, vy: 0 };
    if (sp > PHYSICS.maxThrowSpeed) {
        vx *= PHYSICS.maxThrowSpeed / sp;
        vy *= PHYSICS.maxThrowSpeed / sp;
    }
    return { vx: vx, vy: vy };
}

// 抛体一步：s = {x,y,vx,vy}，b = {left,right,top,bottom}（包围盒左上角的活动范围）。
// 返回 { s, impact (最大撞击速度，0=无碰撞), atRest }
function flightStep(s, dt, b, gravity, restitution, friction) {
    var sp = Math.max(Math.abs(s.vx), Math.abs(s.vy));
    var n = Math.min(PHYSICS.substepMax, Math.max(1, Math.ceil(sp * dt / PHYSICS.substepPx)));
    var h = dt / n;
    var x = s.x, y = s.y, vx = s.vx, vy = s.vy, impact = 0;
    for (var i = 0; i < n; i++) {
        vy += gravity * h;
        x += vx * h;
        y += vy * h;
        if (x < b.left) {
            x = b.left;
            if (vx < 0) { impact = Math.max(impact, -vx); vx = -vx * restitution; }
        } else if (x > b.right) {
            x = b.right;
            if (vx > 0) { impact = Math.max(impact, vx); vx = -vx * restitution; }
        }
        if (y < b.top) {
            y = b.top;
            if (vy < 0) { impact = Math.max(impact, -vy); vy = -vy * restitution; }
        } else if (y >= b.bottom) {
            y = b.bottom;
            if (vy > 0) {
                if (vy > PHYSICS.restNormal) impact = Math.max(impact, vy);
                vy = -vy * restitution;
                if (Math.abs(vy) < PHYSICS.restNormal) vy = 0;
            }
            vx *= Math.exp(-friction * h);
        }
    }
    var onGround = y >= b.bottom - 0.5;
    var atRest = onGround && vy === 0 && Math.abs(vx) < PHYSICS.restTangent;
    return { s: { x: x, y: y, vx: atRest ? 0 : vx, vy: vy }, impact: impact, atRest: atRest };
}

var WHISPER_ANIMS = ["碎碎念-擦桌碎碎念", "碎碎念-发呆碎碎念", "碎碎念-对屏碎碎念"];

// ---------------------------------------------------------------- 跨模块共享
// .pragma library 的模块在同一引擎里只有一份，可以当全局表用
var registry = { primary: null, list: [] };

// ---------------------------------------------------------------- 多屏
// 屏幕用全局逻辑坐标 {x, y, width, height}

function vOverlap(a, b) {
    return Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
}

// cur 的 dir 侧（-1 左 / 1 右）紧挨着的屏（容差 2px，纵向要有重叠）
function neighbor(screens, cur, dir) {
    for (var i = 0; i < screens.length; i++) {
        var s = screens[i];
        if (s === cur || vOverlap(s, cur) <= 0)
            continue;
        if (dir > 0 && Math.abs(s.x - (cur.x + cur.width)) <= 2)
            return s;
        if (dir < 0 && Math.abs(s.x + s.width - cur.x) <= 2)
            return s;
    }
    return null;
}

// 全局点 (gx, gy) 落在哪块屏；横向命中、纵向不命中时取纵向最近的
function screenAt(screens, gx, gy) {
    var best = null, bestD = Infinity;
    for (var i = 0; i < screens.length; i++) {
        var s = screens[i];
        if (gx < s.x || gx >= s.x + s.width)
            continue;
        var d = gy < s.y ? s.y - gy : gy >= s.y + s.height ? gy - (s.y + s.height - 1) : 0;
        if (d < bestD) {
            bestD = d;
            best = s;
        }
    }
    return best;
}

// ---------------------------------------------------------------- 梦话

var SLEEP_TALK_INSTRUCTION = "你正在睡觉，随便嘟囔一句梦话，一句就好，20 字以内；含糊、半梦半醒，不要清醒地回应任何人。";
var OFFLINE_SLEEP_TALKS = ["呼……布丁……再来一份……", "唔……主人别走……", "嗯……再睡五分钟……", "鲸鱼……游走了……", "zzZ……嘿嘿……", "代码……没有 bug……"];

// ---------------------------------------------------------------- 待办

var TODO_ANIM = "轻快记录";

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

// 从一句话里解析到期时间，返回 { text, due }（due 为毫秒时间戳，0 = 不限时）
// 支持：30分钟后 / 2小时后 / 1.5h / 18:30 / 18点 / 18点半 / 今天|明天|后天 + 时间 / @18:30
function parseTodo(input, now) {
    var s = (input || "").trim();
    now = now || Date.now();
    var base = new Date(now);
    var due = 0;
    var m;

    m = /(\d+(?:\.\d+)?)\s*(分钟|min|m|小时|个小时|钟头|h)\s*(以?后)?/i.exec(s);
    if (m) {
        var n = parseFloat(m[1]);
        var unit = /分钟|min|^m$/i.test(m[2]) ? 60000 : 3600000;
        due = now + Math.round(n * unit);
        s = (s.slice(0, m.index) + s.slice(m.index + m[0].length)).trim();
        return { text: s.replace(/^[，,。\s@]+|[，,。\s@]+$/g, ""), due: due };
    }

    var dayOff = 0;
    m = /(今天|明天|后天|今晚|明早)/.exec(s);
    if (m) {
        dayOff = { "今天": 0, "今晚": 0, "明天": 1, "明早": 1, "后天": 2 }[m[1]];
        s = (s.slice(0, m.index) + s.slice(m.index + m[0].length)).trim();
    }
    m = /@?\s*(上午|早上|下午|晚上|中午)?\s*(\d{1,2})\s*(?:[:：](\d{2})|点\s*(半|\d{1,2}分?)?)/.exec(s);
    if (m) {
        var h = parseInt(m[2], 10);
        var min = m[3] ? parseInt(m[3], 10) : m[4] === "半" ? 30 : m[4] ? parseInt(m[4], 10) : 0;
        if ((m[1] === "下午" || m[1] === "晚上") && h < 12)
            h += 12;
        if (h < 24 && min < 60) {
            var d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + dayOff, h, min, 0, 0);
            if (dayOff === 0 && d.getTime() <= now)
                d.setDate(d.getDate() + 1);
            due = d.getTime();
            s = (s.slice(0, m.index) + s.slice(m.index + m[0].length)).trim();
        }
    } else if (dayOff > 0) {
        due = new Date(base.getFullYear(), base.getMonth(), base.getDate() + dayOff, 9, 0, 0, 0).getTime();
    }
    return { text: s.replace(/^[，,。\s@]+|[，,。\s@]+$/g, ""), due: due };
}

function fmtDue(due, now) {
    if (!due)
        return "";
    var d = new Date(due), n = new Date(now || Date.now());
    var dayDiff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(n.getFullYear(), n.getMonth(), n.getDate())) / 86400000);
    var prefix = dayDiff === 0 ? "" : dayDiff === 1 ? "明天 " : dayDiff === 2 ? "后天 " : (d.getMonth() + 1) + "/" + d.getDate() + " ";
    return prefix + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function fmtLeft(ms) {
    var m = Math.round(Math.abs(ms) / 60000);
    if (m === 0)
        return "就是现在";
    var t = m < 60 ? m + " 分钟" : m < 1440 ? Math.floor(m / 60) + " 小时" + (m % 60 ? " " + (m % 60) + " 分钟" : "") : Math.floor(m / 1440) + " 天";
    return ms >= 0 ? "还有 " + t : "已经过了 " + t;
}

// 下一次该提醒的间隔：越临近越密。不限时的每 2 小时提一次，过期后每 10 分钟
function remindGap(todo, now) {
    if (!todo.due)
        return 2 * 3600000;
    var left = todo.due - now;
    if (left <= 0)
        return 10 * 60000;
    return Math.max(2 * 60000, Math.min(60 * 60000, left / 4));
}

function shouldRemind(todo, now) {
    var last = todo.lastRemind || todo.created || 0;
    // 到点那一刻一定提醒一次
    if (todo.due && now >= todo.due && !todo.dueFired)
        return true;
    return now - last >= remindGap(todo, now);
}

function remindText(todo, now) {
    var tail = todo.due ? "（" + fmtLeft(todo.due - now) + "）" : "";
    var tpl = todo.due && now >= todo.due
        ? ["主人！「%s」到时间啦%t", "「%s」该做了哦%t", "别忘了「%s」%t"]
        : ["主人，记得「%s」%t", "提醒一下：「%s」%t", "「%s」还没做哦%t"];
    return pick(tpl).replace("%s", todo.text).replace("%t", tail);
}
