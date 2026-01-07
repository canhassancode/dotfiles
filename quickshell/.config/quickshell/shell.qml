import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    // Theme
    property color colBg: '#510c114a'
    property color colCyan: "#0db9d7"
    property color colBlue: "#7aa2f7"
    property color colPill: "#e0af68"
    property color colText: "#a9b1d6"
    property color colInactive: "#444b6a"
    property color colWhite: "#ffffff"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string iconFontFamily: "Font Awesome 7 Free"

    // System Data
    property string cpuVal: "0%"
    property string memVal: "0%"
    property string gpuVal: "0°C"
    property string tempVal: "0°C"
    property string volumeVal: "0%"

    property double volFloat: 0.0 
    property bool showVolBar: false 

    property var lastTotal: 0
    property var lastIdle: 0

    // Layout
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

    Process {
        id: volumeProc
        // awk prints just the number (e.g. 0.55)
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}'"]
        
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                
                // Parse "0.55" or "0.55 [MUTED]"
                var val = parseFloat(data.trim())
                if (isNaN(val)) return

                // LOGIC: Did volume change?
                // We use 0.01 tolerance to avoid floating point glitches
                if (Math.abs(val - root.volFloat) > 0.01) {
                    root.showVolBar = true
                    volHideTimer.restart() // Keep bar open while changing
                }

                root.volFloat = val
                root.volumeVal = Math.round(val * 100) + "%"
            }
        }
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

    // Center Elements
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

    // Right Container
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

            // Right Clock
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

            // --- Volume Widget ---
            Rectangle {
                id: volPill
                
                // Animation Logic
                // If showing bar: Width is 100. If not: Width is 30 (Icon only)
                implicitWidth: root.showVolBar ? 100 : 30
                height: 25
                radius: 15
                color: colPill
                clip: true // Important! Cuts off the bar when it shrinks

                // Smooth Animation
                Behavior on implicitWidth { 
                    NumberAnimation { duration: 300; easing.type: Easing.OutBack } 
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    // 1. The Icon (Always visible)
                    Text {
                        text: root.volFloat > 0.5 ? "" : (root.volFloat > 0 ? "" : "")
                        color: colWhite
                        font.family: fontFamily
                        font.pixelSize: 14
                    }

                    // 2. The Bar (Revealed on change)
                    Rectangle {
                        id: barTrack
                        width: 50 // Fixed width for the bar area
                        height: 6
                        radius: 3
                        color: "#44000000" // Dark background for track
                        
                        // Prevent the bar from squishing the icon when shrinking
                        visible: root.showVolBar || volPill.width > 35

                        // The Fill Level
                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            color: colWhite
                            
                            // Width based on volume %
                            width: parent.width * root.volFloat
                            
                            Behavior on width { NumberAnimation { duration: 100 } }
                        }
                    }
                }
            }

            // Right Connection
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