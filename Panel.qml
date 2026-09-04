import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "kdm.touchpad-guard"
  ipcTarget: "kdm.touchpad-guard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool confirmingReset: false
  property int focusIndex: 0
  property int modeCursorIndex: 0
  readonly property var definitions: Model.settingDefinitions()
  readonly property var modeValues: ["normal", "safe", "off"]
  readonly property int resetIndex: definitions.length + 1
  readonly property var guardStatus: hostWidget
    ? hostWidget.guardStatus : Model.normalizeStatus("")
  readonly property bool busy: hostWidget ? hostWidget.busy : false
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color background: root.bar ? root.bar.background : Color.background
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function open() {
    confirmingReset = false
    focusIndex = 0
    modeCursorIndex = Math.max(0, modeValues.indexOf(guardStatus.mode))
    controller.show()
    if (hostWidget) hostWidget.refresh()
  }

  function close() {
    confirmingReset = false
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function requestMode(mode) {
    if (hostWidget && !busy) hostWidget.requestMode(mode)
  }

  function requestSetting(key, value) {
    if (hostWidget && !busy && Model.settingEnabled(guardStatus.mode, key))
      hostWidget.requestSetting(key, value)
  }

  function definitionAtFocus() {
    var index = focusIndex - 1
    return index >= 0 && index < definitions.length ? definitions[index] : null
  }

  function optionIndex(definition, value) {
    if (!definition || !Array.isArray(definition.options)) return -1
    for (var i = 0; i < definition.options.length; i++)
      if (String(definition.options[i].value) === String(value)) return i
    return -1
  }

  function moveCursor(dx, dy) {
    if (dy !== 0) {
      focusIndex = Math.max(0, Math.min(resetIndex, focusIndex + dy))
      if (focusIndex === 0)
        modeCursorIndex = Math.max(0, modeValues.indexOf(guardStatus.mode))
      Qt.callLater(ensureCursorVisible)
      return
    }
    if (dx === 0 || busy) return

    if (focusIndex === 0) {
      modeCursorIndex = Math.max(0,
        Math.min(modeValues.length - 1, modeCursorIndex + dx))
      return
    }

    var definition = definitionAtFocus()
    if (!definition || !Model.settingEnabled(guardStatus.mode, definition.key)) return
    var current = Model.settingValue(guardStatus, definition.key)

    if (definition.type === "slider") {
      var next = Number(current) + dx * Number(definition.step)
      next = Math.max(definition.minimum, Math.min(definition.maximum, next))
      requestSetting(definition.key, Math.round(next * 100) / 100)
    } else if (definition.type === "enum") {
      var index = optionIndex(definition, current)
      var target = Math.max(0, Math.min(definition.options.length - 1, index + dx))
      requestSetting(definition.key, definition.options[target].value)
    }
  }

  function activateCursor() {
    if (busy) return
    if (focusIndex === 0) {
      requestMode(modeValues[modeCursorIndex])
      return
    }
    if (focusIndex === resetIndex) {
      if (!confirmingReset) confirmingReset = true
      else if (hostWidget) {
        confirmingReset = false
        hostWidget.requestReset()
      }
      return
    }

    var definition = definitionAtFocus()
    if (!definition || !Model.settingEnabled(guardStatus.mode, definition.key)) return
    if (definition.type === "toggle") {
      requestSetting(definition.key,
        !Boolean(Model.settingValue(guardStatus, definition.key)))
    }
  }

  function ensureCursorVisible() {
    if (!settingsScroll || !content) return
    var target = null
    if (focusIndex === 0) target = modes
    else if (focusIndex === resetIndex) target = resetButton
    else target = settingsRepeater.itemAt(focusIndex - 1)
    if (!target) return
    var point = target.mapToItem(content, 0, 0)
    if (point.y < settingsScroll.contentY)
      settingsScroll.contentY = Math.max(0, point.y - Style.spacing.md)
    else if (point.y + target.height > settingsScroll.contentY + settingsScroll.height)
      settingsScroll.contentY = Math.min(
        settingsScroll.contentHeight - settingsScroll.height,
        point.y + target.height - settingsScroll.height + Style.spacing.md)
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(500))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: settingsScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: settingsScroll.width
          spacing: Style.spacing.lg

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Column {
              width: parent.width - busyLabel.width - parent.spacing
              spacing: Style.spacing.xs

              Text {
                width: parent.width
                text: "Touchpad Guard"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                width: parent.width
                text: Model.modeLabel(root.guardStatus.mode)
                textFormat: Text.PlainText
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Text {
              id: busyLabel
              visible: root.busy
              text: "Applying…"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            text: "Choose protection first. Fine-tune your Normal preferences below."
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ButtonGroup {
            id: modes
            options: [
              { value: "normal", label: "Normal", icon: "󰟸" },
              { value: "safe", label: "Typing Safe", icon: "󰒘" },
              { value: "off", label: "Off", icon: "󰟾" }
            ]
            value: root.guardStatus.mode
            cursorIndex: root.focusIndex === 0 ? root.modeCursorIndex : -1
            foreground: root.foreground
            background: root.background
            onChanged: function(value) { root.requestMode(value) }
            onHovered: function(index, hovered) {
              if (!hovered) return
              root.focusIndex = 0
              root.modeCursorIndex = index
            }
          }

          BorderSurface {
            width: parent.width
            implicitHeight: deviceColumn.implicitHeight + Style.spacing.lg * 2
            color: Style.controlFill(false, false, root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            radius: Style.cornerRadius

            Column {
              id: deviceColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.spacing.lg
              spacing: Style.spacing.xs

              Text {
                text: root.guardStatus.devices.length === 0
                  ? "No touchpad detected" : (root.guardStatus.devices.length === 1
                    ? "Detected touchpad" : "Detected touchpads")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Repeater {
                model: root.guardStatus.devices
                Text {
                  required property string modelData
                  width: deviceColumn.width
                  text: modelData
                  elide: Text.ElideMiddle
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            visible: root.guardStatus.mode === "safe"
            width: parent.width
            text: root.guardStatus.settings.protectKeyboardFocus
              ? "Typing Safe: taps and tap-drag are off; pointer focus changes are blocked."
              : "Typing Safe: taps and tap-drag are off; scrolling, movement, and physical presses remain available."
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: !root.guardStatus.ok
            width: parent.width
            text: root.guardStatus.error
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            id: settingsRepeater
            model: root.definitions

            delegate: Column {
              id: settingRow
              required property var modelData
              required property int index
              width: settingsScroll.width
              spacing: Style.spacing.sm
              readonly property var definition: modelData
              readonly property bool controlEnabled:
                Model.settingEnabled(root.guardStatus.mode, definition.key)
              readonly property var savedValue:
                Model.settingValue(root.guardStatus, definition.key)
              readonly property bool firstInGroup:
                index === 0 || root.definitions[index - 1].group !== definition.group

              Text {
                visible: settingRow.firstInGroup
                width: parent.width
                topPadding: settingRow.index === 0 ? 0 : Style.spacing.md
                text: settingRow.definition.group
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Toggle {
                visible: settingRow.definition.type === "toggle"
                width: parent.width
                enabled: settingRow.controlEnabled && !root.busy
                opacity: settingRow.controlEnabled ? 1 : 0.52
                label: settingRow.definition.label
                description: settingRow.controlEnabled
                  ? settingRow.definition.description
                  : (root.guardStatus.mode === "safe"
                    ? "Disabled in Typing Safe. Your Normal preference is preserved."
                    : "Stored while the touchpad is Off.")
                checked: Boolean(settingRow.savedValue)
                hasCursor: root.focusIndex === settingRow.index + 1
                foreground: root.foreground
                accent: Color.accent
                onClicked: root.requestSetting(settingRow.definition.key, !checked)
                onHovered: function(hovered) {
                  if (hovered) root.focusIndex = settingRow.index + 1
                }
              }

              BorderSurface {
                visible: settingRow.definition.type === "slider"
                width: parent.width
                implicitHeight: sliderColumn.implicitHeight + Style.spacing.lg * 2
                opacity: settingRow.controlEnabled ? 1 : 0.52
                color: Style.controlFill(false,
                  root.focusIndex === settingRow.index + 1,
                  root.foreground, Color.accent)
                borderSpec: Border.controlSpec(
                  root.focusIndex === settingRow.index + 1 ? "hover-cursor" : "normal",
                  root.foreground, Color.accent)
                radius: Style.cornerRadius

                Column {
                  id: sliderColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.spacing.lg
                  spacing: Style.spacing.sm

                  Row {
                    width: parent.width

                    Text {
                      width: parent.width - sliderValue.width
                      text: settingRow.definition.label
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                    }

                    Text {
                      id: sliderValue
                      text: Model.formatSetting(settingRow.definition.key,
                        slider.dragging ? slider.liveValue : settingRow.savedValue)
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  Text {
                    width: parent.width
                    text: settingRow.definition.description
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  PanelSlider {
                    id: slider
                    width: parent.width
                    bar: root.bar
                    enabled: settingRow.controlEnabled && !root.busy
                    minimum: settingRow.definition.minimum === undefined
                      ? 0 : settingRow.definition.minimum
                    maximum: settingRow.definition.maximum === undefined
                      ? 1 : settingRow.definition.maximum
                    step: settingRow.definition.step === undefined
                      ? 0.05 : settingRow.definition.step
                    value: settingRow.definition.type === "slider"
                      ? Number(settingRow.savedValue) : 0
                    onReleased: function(value) {
                      root.requestSetting(settingRow.definition.key,
                        Math.round(value * 100) / 100)
                    }
                  }
                }

                HoverHandler {
                  onHoveredChanged: {
                    if (hovered) root.focusIndex = settingRow.index + 1
                  }
                }
              }

              Column {
                visible: settingRow.definition.type === "enum"
                width: parent.width
                spacing: Style.spacing.xs
                opacity: settingRow.controlEnabled ? 1 : 0.52

                Text {
                  width: parent.width
                  text: settingRow.definition.label
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: settingRow.definition.description
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                ButtonGroup {
                  enabled: settingRow.controlEnabled && !root.busy
                  options: settingRow.definition.options || []
                  value: String(settingRow.savedValue)
                  cursorIndex: root.focusIndex === settingRow.index + 1
                    ? root.optionIndex(settingRow.definition, settingRow.savedValue) : -1
                  foreground: root.foreground
                  background: root.background
                  onChanged: function(value) {
                    root.requestSetting(settingRow.definition.key,
                      Model.coerceSetting(settingRow.definition.key, value))
                  }
                  onHovered: function(index, hovered) {
                    if (hovered) root.focusIndex = settingRow.index + 1
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Reset reloads Hyprland, imports the resulting Omarchy values, and returns to Normal."
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.spacing.md

            Button {
              id: resetButton
              text: root.confirmingReset ? "Confirm reset" : "Reset to current Omarchy config"
              iconText: root.confirmingReset ? "󰜉" : "󰑐"
              bordered: true
              selected: root.confirmingReset
              hasCursor: root.focusIndex === root.resetIndex
              enabled: !root.busy
              foreground: root.foreground
              background: root.background
              onClicked: {
                root.focusIndex = root.resetIndex
                root.activateCursor()
              }
              onHovered: function(hovered) {
                if (hovered) root.focusIndex = root.resetIndex
              }
            }

            Button {
              visible: root.confirmingReset
              text: "Cancel"
              bordered: true
              foreground: root.foreground
              background: root.background
              onClicked: root.confirmingReset = false
            }
          }
        }
      }
    }
  }
}
