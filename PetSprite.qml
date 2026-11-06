import QtQuick
import "pet.js" as Pet

// 双缓冲播放器：新动画在后台那张 AnimatedImage 里加载好再切到前台，避免切换时闪一下空白。
// 素材左朝向；mirrored=true 时水平翻转成右朝向。
Item {
    id: root

    property bool mirrored: false
    property real squashY: 1
    property real feetRatio: Pet.HIT_BOX.y1 / 360

    readonly property string current: _name
    readonly property real durationSec: _front && _front.frameCount > 0 ? _front.frameCount / Pet.FPS : 0

    // 动画切到前台开始播（move 用它对齐位移时间轴）
    signal started(string name)
    // 非循环动画播到最后一帧
    signal finished(string name)

    property string _name: ""
    property bool _loop: false
    property bool _done: false
    property bool _pending: false
    property var _front: null
    property var _back: imgA

    function urlOf(name) {
        return Qt.resolvedUrl("assets/anim/" + name + ".webp");
    }

    function play(name, loop) {
        if (_front && _name === name && loop && _loop)
            return;
        _name = name;
        _loop = !!loop;
        _done = false;
        const back = _front === imgA ? imgB : imgA;
        _back = back;
        back.playing = false;
        _pending = true;
        if (back.source.toString() !== urlOf(name).toString())
            back.source = urlOf(name);
        if (back.status === AnimatedImage.Ready)
            _swap(back);
    }

    function _swap(img) {
        if (img !== _back || !_pending)
            return;
        _pending = false;
        img.currentFrame = 0;
        img.paused = false;
        img.playing = true;
        img.visible = true;
        if (_front && _front !== img) {
            _front.visible = false;
            _front.playing = false;
        }
        _front = img;
        started(_name);
    }

    function _onFrame(img) {
        if (img !== _front || _loop || _done)
            return;
        if (img.frameCount > 1 && img.currentFrame === img.frameCount - 1) {
            _done = true;
            img.paused = true;
            finished(_name);
        }
    }

    transform: [
        Scale {
            origin.x: root.width / 2
            xScale: root.mirrored ? -1 : 1
        },
        Scale {
            origin.y: root.height * root.feetRatio
            yScale: root.squashY
            origin.x: root.width / 2
            xScale: root.squashY < 1 ? 1 + (1 - root.squashY) * 0.5 : 1
        }
    ]

    AnimatedImage {
        id: imgA
        anchors.fill: parent
        visible: false
        playing: false
        cache: false
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        onStatusChanged: if (status === AnimatedImage.Ready) root._swap(imgA)
        onCurrentFrameChanged: root._onFrame(imgA)
    }

    AnimatedImage {
        id: imgB
        anchors.fill: parent
        visible: false
        playing: false
        cache: false
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        onStatusChanged: if (status === AnimatedImage.Ready) root._swap(imgB)
        onCurrentFrameChanged: root._onFrame(imgB)
    }
}
