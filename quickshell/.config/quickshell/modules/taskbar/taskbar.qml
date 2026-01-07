import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQml

Instantiator {
    
    model: Quickshell.screens

    delegate: PanelWindow {
        id: root

        screen: modelData

        property color colBg: '#510c114a'
        property color colCyan: "#0db9d7"
        property color colBlue: "#7aa2f7"
        property color colPill: "#e0af68"
        property color colText: "#a9b1d6"
        property color colInactive: "#444b6a"
        property color colWhite: "#ffffff"
        property string fontFamily: "JetBrainsMono Nerd Font"
        property string iconFontFamily: "Font Awesome 7 Free"

        property string cpuVal: "0%"
        property string memVal: "0%"
        property string gpuVal: "0°C"
        property string tempVal: "0°C"
        property string volumeVal: "0%"

        property double volFloat: 0.0 
        property bool showVolBar: false 
        property bool isMuted: false

        property var lastTotal: 0
        property var lastIdle: 0

        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 35
        color: colBg

        Timer {
            id: volHideTimer
            interval: 1000
            onTriggered: root.showVolBar = false
        }

        Timer {
            interval: 100
            running: true
            repeat: true
            onTriggered: volumeProc.running = true
        }

        Timer {
            interval: 2000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                cpuProc.running = true
                memProc.running = true
                tempProc.running = true
                gpuProc.running = true
            }
        }

        Process {
            id: volumeProc
            
            command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
            
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    
                    root.isMuted = data.includes("MUTED")
                    var match = data.match(/Volume:\s+([\d\.]+)/)
                    if (match) {
                        var val = parseFloat(match[1])
                        
                        if (Math.abs(val - root.volFloat) > 0.01 || root.isMuted !== (data.includes("MUTED"))) {
                            root.showVolBar = true
                            volHideTimer.restart()
                        }

                        root.volFloat = val
                    }
                }
            }
        }

        Process {
            id: cpuProc
            command: ["sh", "-c", "head -1 /proc/stat"]
            
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    let lines = data.split("\n")
                    if (lines.length < 1) return
                    
                    var parts = lines[0].split(/\s+/)
                    var idle = parseInt(parts[4])
                    var total = 0
                    for (var i = 1; i < parts.length; i++) {
                        var val = parseInt(parts[i])
                        if (!isNaN(val)) total += val
                    }
                    
                    var diffIdle = idle - root.lastIdle
                    var diffTotal = total - root.lastTotal
                    var usage = (diffTotal > 0) ? (100 * (diffTotal - diffIdle) / diffTotal).toFixed(0) : "0"
                    
                    root.cpuVal = usage + "%"
                    root.lastIdle = idle
                    root.lastTotal = total
                }
            }

            Component.onCompleted: running = true
        }

        Process {
            id: memProc
            command: ["sh", "-c", "free | grep Mem"]
            
            stdout: SplitParser {
                onRead: data => {
                    if (!data ) return
                    let parts = data.trim().split(/\s+/)
                    let total = parseInt(parts[1])
                    let used = parseInt(parts[2])
                    
                    if (total > 0) {
                        root.memVal = Math.round(100 * used / total) + "%"
                    } 
                }
            }

            Component.onCompleted: running = true
        }

        Process {
            id: tempProc
            command: ["sh", "-c", "sensors k10temp-pci-00c3 | grep Tctl"]
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    var match = data.match(/\+(\d+\.\d+)/)
                    if (match) {
                        root.tempVal = Math.round(parseFloat(match[1])) + "°C"
                    }
                }
            }

            Component.onCompleted: running = true
        }

        Process {
            id: gpuProc
            command: ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader"]
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    if (data.trim() !== "") {
                        root.gpuVal = data.trim() + "°C"
                    }
                }
            }

            Component.onCompleted: running = true
        }

        Rectangle {
            id: leftContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 4
            
            width: statsRow.implicitWidth + 20 
            height: 25
            radius: 15
            color: colPill
            clip: true 

            Behavior on width { NumberAnimation { duration: 200 } }

            RowLayout {
                id: statsRow
                anchors.centerIn: parent
                spacing: 12

                RowLayout {
                    spacing: 4
                    Text { text: ""; color: colWhite; font.family: fontFamily }
                    Text { text: "CPU: " + root.cpuVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
                RowLayout {
                    spacing: 4
                    Text { text: ""; color: colWhite; font.family: fontFamily }
                    Text { text: "RAM: " + root.memVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
                RowLayout {
                    spacing: 4
                    Text { text: "󰢮"; color: colWhite; font.family: fontFamily }
                    Text { text: "GPU: " + root.gpuVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
                RowLayout {
                    spacing: 4
                    Text { text: ""; color: colWhite; font.family: fontFamily }
                    Text { text: "Temp: " + root.tempVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
            }
        }

        Rectangle {
            id: workspaceContainer
            anchors.centerIn: parent
            width: workspaceRow.implicitWidth + 20
            height: 25
            radius: 15

            color: colPill

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            RowLayout {
                id: workspaceRow
                anchors.centerIn: parent

                Repeater {
                    model: 8

                    Rectangle {
                        id: workspaceBar

                        property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                        property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)

                        implicitWidth: isActive? 30 : 15
                        implicitHeight: 15
                        radius: 10
                        opacity: isActive ? 1 : 0.2

                        Layout.leftMargin: 1
                        Layout.rightMargin: 1

                        color: colWhite
                        z: isActive ? 100 : 0


                        Behavior on implicitWidth { 
                            NumberAnimation { 
                                duration: 200
                                easing.type: Easing.OutQuad 
                            } 
                        }

                        Behavior on color { 
                            ColorAnimation { duration: 200 } 
                        }

                        MouseArea { 
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch("workspace " + (index + 1))
                            cursorShape: Qt.PointingHandCursor

                            hoverEnabled: true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: rightContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 4

            width: rightRowLayout.implicitWidth + 20
            height: 25

            color: "transparent"

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            RowLayout {
                id: rightRowLayout
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    id: clockContainer
                    width: clockRow.implicitWidth + 20
                    height: 25
                    radius: 15

                    color: colPill

                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }


                    RowLayout {
                        id: clockRow
                        anchors.centerIn: parent

                        SystemClock {
                            id: clock
                            precision: SystemClock.Seconds
                        }

                        Text {
                            text: Qt.formatDateTime(clock.date, "hh:mm:ss")
                            color: colWhite
                            font { pixelSize: 14; bold: true; family: fontFamily; }
                        }
                    }
                }

                Rectangle {
                    id: volPill

                    implicitWidth: root.showVolBar ? 150 : 40
                    height: 25
                    radius: 15
                    
                    color: colPill
                    clip: true

                    Behavior on implicitWidth { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack } 
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: root.isMuted ? "" : (root.volFloat > 0.5 ? "" : (root.volFloat > 0 ? "" : ""))
                            color: colWhite
                            
                            font.family: fontFamily
                            font.pixelSize: 14
                        }

                        Rectangle {
                            id: barTrack
                            width: 100
                            height: 8
                            radius: 15
                            color: "#44000000"
                            
                            visible: root.showVolBar || volPill.implicitWidth > 40
                            opacity: root.showVolBar ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                
                                color: root.isMuted ? "#ff5555" : colWhite
                                
                                width: parent.width * root.volFloat
                                Behavior on width { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                    }
                }

                Rectangle {
                    id: connectionContainer
                    anchors.margins: 4
                    width: connectionIcon.implicitWidth + 20
                    height: 25
                    radius: 15

                    color: colPill

                    Text {
                        id: connectionIcon
                        anchors.centerIn: parent
                        text: ""
                        color: colWhite
                        font { pixelSize: 14; bold: true; family: fontFamily; }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // onClicked: Connection.toggle() // TODO: Add connection menu
                        cursorShape: Qt.PointingHandCursor

                        hoverEnabled: true
                    }
                }

                // Right Power
                Rectangle {
                    id: powerContainer
                    anchors.margins: 4
                    width: powerIcon.implicitWidth + 20
                    height: 25
                    radius: 15

                    color: colPill

                    Text {
                        id: powerIcon
                        anchors.centerIn: parent
                        text: ""
                        color: colWhite
                        font { pixelSize: 14; bold: true; family: fontFamily; }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // onClicked: Power.shutdown() TODO: Add power menu
                        cursorShape: Qt.PointingHandCursor

                        hoverEnabled: true
                    }
                }
            }
        }
    }
}
