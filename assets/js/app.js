import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {Hakushi} from "hakushi"
import {mountSelfLoops} from "./self_loops"

async function loadDrawingFonts(workspace) {
  // Resolve the host's CSS mapping, not a second document-role → family registry.
  // Preload every role so changing document appearance never measures a fallback.
  const probe = document.createElement("div")
  probe.className = workspace.className
  const objectProbe = document.createElement("div")
  objectProbe.className = "drawing-typography"
  probe.append(objectProbe)
  probe.hidden = true
  workspace.append(probe)
  const fonts = new Set()
  try {
    for (const role of ["sans", "heading", "mono", "handwritten"]) {
      probe.dataset.drawingFont = role
      objectProbe.dataset.drawingFont = role
      for (const element of [probe, objectProbe]) {
        const style = getComputedStyle(element)
        const family = style.getPropertyValue("--canvas-text-font").trim()
        for (const suffix of ["", "-large"]) {
          const weight = style.getPropertyValue(`--canvas-text-weight${suffix}`).trim()
          fonts.add(`${weight} 28px ${family}`)
        }
      }
    }
    await Promise.all([...fonts].map(font => document.fonts.load(font)))
  } finally {
    probe.remove()
  }
}

function setFontState(workspace, state) {
  workspace.drawingFontState = state
  workspace.dataset.fontState = state
}

function mountObjectTypography(canvas) {
  const drawStylePanel = canvas.drawStylePanel.bind(canvas)
  canvas.drawStylePanel = () => {
    for (const id of canvas.selected) {
      const node = canvas.nodes.get(id)
      if (node?.type !== "shape") continue
      const object = node.el.querySelector(".drawing-typography")
      const shape = object?.querySelector("[data-hakushi-style]")
      if (!shape) continue
      const style = JSON.parse(shape.dataset.hakushiStyle)
      const font = object.dataset.drawingFont ||
        canvas.root.closest(".canvas-workspace").dataset.drawingFont
      // The inspector shows the effective role without materializing inherited
      // font metadata in the document.
      if (style.font !== font) {
        shape.dataset.hakushiStyle = JSON.stringify({...style, font})
      }
    }
    return drawStylePanel()
  }

  const editText = canvas.editText.bind(canvas)
  canvas.editText = node => {
    const text = node.el.querySelector(".drawing-typography [data-hakushi-text]")
    if (!text || canvas.config.readonly) return editText(node)
    const style = getComputedStyle(text)
    const typography = {
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      lineHeight: style.lineHeight,
      letterSpacing: style.letterSpacing,
      textAlign: style.textAlign,
    }
    editText(node)
    // Hakushi moves the editor outside the object and only copies its family.
    // Copy the remaining metrics synchronously, before typing or commit's
    // scrollHeight measurement; retain its text/save/undo/growth handlers.
    const editor = canvas.labelsEl.lastElementChild
    if (editor?.classList.contains("hakushi-text-editor")) {
      Object.assign(editor.style, typography)
    }
  }
  canvas.drawStylePanel()
}

function mountLineTool(canvas) {
  const workspace = canvas.root.closest(".canvas-workspace")
  const dockObserver = new ResizeObserver(([entry]) => {
    workspace.style.setProperty("--dock-height", `${entry.borderBoxSize[0].blockSize}px`)
  })
  const buildTools = canvas.buildTools.bind(canvas)
  canvas.buildTools = () => {
    buildTools()
    const line = canvas.toolsEl?.querySelector('[data-tool="drawing:straight-line"]')
    if (line) {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
      path.setAttribute("d", "M5 19L19 5")
      line.querySelector("svg").replaceChildren(path)
      line.setAttribute("aria-keyshortcuts", "L")
    }
    dockObserver.disconnect()
    if (canvas.toolsEl) dockObserver.observe(canvas.toolsEl)
  }
  canvas.buildTools()

  const isStraightLineGesture = gesture => gesture?.kind === "shape" && gesture.tool.tool === "straight-line"
  // Shapes.line stores tenths of a canvas pixel; use that precision in the preview.
  const roundLinePoint = point => ({x: Math.round(point.x * 10) / 10, y: Math.round(point.y * 10) / 10})
  const constrainLine = gesture => {
    if (!gesture.square) {
      gesture.end = roundLinePoint(gesture.rawEnd)
      return
    }
    const dx = gesture.rawEnd.x - gesture.start.x
    const dy = gesture.rawEnd.y - gesture.start.y
    // Follow native rotation's angle rounding, with exact axis/diagonal deltas.
    const angle = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4)
    const x = Math.round(Math.cos(angle))
    const y = Math.round(Math.sin(angle))
    const length = Math.hypot(dx, dy) * (x && y ? Math.SQRT1_2 : 1)
    const delta = Math.round(length * 10) / 10
    gesture.end = roundLinePoint({x: gesture.start.x + x * delta, y: gesture.start.y + y * delta})
  }

  const commitShape = canvas.commitShape.bind(canvas)
  canvas.commitShape = gesture => {
    if (gesture.tool.tool !== "straight-line") return commitShape(gesture)
    // Native line gestures attach to shapes. This tool always creates a node.
    if (Math.hypot(gesture.end.x - gesture.start.x, gesture.end.y - gesture.start.y) * canvas.view.zoom < 6) return
    canvas.push("hakushi:draw", {
      tool: `${gesture.tool.kit}:${gesture.tool.tool}`,
      points: [[gesture.start.x, gesture.start.y], [gesture.end.x, gesture.end.y]],
    }, reply => {
      if (typeof reply.drawn === "string") canvas.pendingSelect = [reply.drawn]
      canvas.selectPending()
    })
    canvas.setTool(null)
  }
  const markLineEnd = canvas.markLineEnd.bind(canvas)
  canvas.markLineEnd = (...args) => {
    if (canvas.tool?.tool !== "straight-line") markLineEnd(...args)
  }

  const selectedLine = () => {
    if (canvas.selected.size !== 1 || canvas.tool || canvas.config.readonly) return null
    const node = canvas.nodes.get([...canvas.selected][0])
    return node?.type === "shape-line" && !node.locked && !canvas.gone.has(node.id) ? node : null
  }
  const pendingEndpoints = new Map()
  const pointsOf = node => {
    const pending = pendingEndpoints.get(node.id)
    if (pending) return {from: {...pending.points.from}, to: {...pending.points.to}}
    const aim = node.el.querySelector(".hakushi-shape-line-aim")
    return {
      from: {x: node.x + Number(aim.getAttribute("x1")), y: node.y + Number(aim.getAttribute("y1"))},
      to: {x: node.x + Number(aim.getAttribute("x2")), y: node.y + Number(aim.getAttribute("y2"))},
    }
  }
  const editEndpoints = (node, points) => {
    if (node.locked || canvas.config.readonly) return
    // Keep Shapes.line's 12px padding and relative endpoint convention, including
    // a positive box when the segment is horizontal, vertical, or reversed.
    const roundBox = value => Math.round(value * 10) / 10
    const x = roundBox(Math.min(points.from.x, points.to.x) - 12)
    const y = roundBox(Math.min(points.from.y, points.to.y) - 12)
    const pending = {points}
    pendingEndpoints.set(node.id, pending)
    canvas.push("hakushi:edit", {
      node: node.id,
      action: "endpoints",
      from: [points.from.x - x, points.from.y - y],
      to: [points.to.x - x, points.to.y - y],
      box: [x, y, roundBox(Math.abs(points.to.x - points.from.x) + 24), roundBox(Math.abs(points.to.y - points.from.y) + 24)],
    }, () => {
      if (pendingEndpoints.get(node.id) === pending) pendingEndpoints.delete(node.id)
      canvas.schedule()
    })
  }
  const endpoints = ["from", "to"].map(end => {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "hakushi-resizer drawing-line-endpoint"
    button.dataset.end = end
    button.hidden = true
    button.setAttribute("aria-label", end === "from" ? "Line start endpoint" : "Line end endpoint")
    button.setAttribute("aria-description", "Drag or use the arrow keys to move this endpoint.")
    canvas.ui.append(button)
    return button
  })
  const drawOverlay = canvas.drawOverlay.bind(canvas)
  canvas.drawOverlay = () => {
    drawOverlay()
    const gesture = canvas.gesture?.kind === "line-endpoint" ? canvas.gesture : null
    const node = gesture?.node || selectedLine()
    const visible = node && !node.locked && !canvas.cropping && (!canvas.gesture || gesture)
    const points = visible && (gesture?.points || pointsOf(node))
    for (const button of endpoints) {
      button.hidden = !visible
      if (!visible) continue
      const point = points[button.dataset.end]
      button.style.left = `${point.x * canvas.view.zoom + canvas.view.x}px`
      button.style.top = `${point.y * canvas.view.zoom + canvas.view.y}px`
    }
    if (gesture) {
      const preview = document.createElementNS("http://www.w3.org/2000/svg", "line")
      preview.setAttribute("class", "hakushi-shape-preview")
      for (const [key, value] of Object.entries({x1: points.from.x, y1: points.from.y, x2: points.to.x, y2: points.to.y})) {
        preview.setAttribute(key, value)
      }
      preview.setAttribute("vector-effect", "non-scaling-stroke")
      canvas.overlay.append(preview)
    }
  }
  const pointerDown = canvas.pointerDown.bind(canvas)
  canvas.pointerDown = event => {
    const button = event.target.closest(".drawing-line-endpoint")
    const node = button && selectedLine()
    if ((canvas.gesture?.kind === "line-endpoint" || isStraightLineGesture(canvas.gesture)) && !canvas.pointers.has(event.pointerId)) {
      // Native pointerDown cancels before reading both touches. Restore the first
      // touch after our line cancellation releases its capture/state.
      const pointers = new Map(canvas.pointers)
      canvas.cancelGesture()
      canvas.pointers = pointers
      return pointerDown(event)
    }
    if (!node || canvas.gesture || event.button !== 0 || canvas.space) {
      pointerDown(event)
      const gesture = canvas.gesture
      if (isStraightLineGesture(gesture) && gesture.pointer === event.pointerId) {
        gesture.rawEnd = gesture.start
        gesture.start = roundLinePoint(gesture.start)
        constrainLine(gesture)
      }
      return
    }
    event.preventDefault()
    canvas.bounds = canvas.root.getBoundingClientRect()
    canvas.pointers.set(event.pointerId, canvas.local(event))
    canvas.capture(event)
    button.focus({preventScroll: true})
    const points = pointsOf(node)
    canvas.gesture = {kind: "line-endpoint", pointer: event.pointerId, node, end: button.dataset.end,
      start: canvas.canvasPoint(event), original: points, points: {...points}}
    node.el.classList.add("drawing-line-editing")
    canvas.schedule()
  }
  const pointerMove = canvas.pointerMove.bind(canvas)
  canvas.pointerMove = event => {
    const gesture = canvas.gesture
    if (isStraightLineGesture(gesture)) {
      if (event.pointerId !== gesture.pointer) return
      pointerMove(event)
      // Retain the unconstrained pointer position so releasing Shift never sticks.
      gesture.rawEnd = gesture.end
      constrainLine(gesture)
      return
    }
    if (gesture?.kind !== "line-endpoint") return pointerMove(event)
    if (event.pointerId !== gesture.pointer) return
    const point = canvas.canvasPoint(event)
    const origin = gesture.original[gesture.end]
    // Apply the pointer delta so grabbing the edge of a target never jumps.
    gesture.points[gesture.end] = {
      x: origin.x + Math.round((point.x - gesture.start.x) * 100) / 100,
      y: origin.y + Math.round((point.y - gesture.start.y) * 100) / 100,
    }
    canvas.schedule()
  }
  const finishEndpoint = cancelled => {
    const gesture = canvas.gesture
    canvas.gesture = null
    canvas.pointers.delete(gesture.pointer)
    gesture.node.el.classList.remove("drawing-line-editing")
    if (canvas.root.hasPointerCapture(gesture.pointer)) canvas.root.releasePointerCapture(gesture.pointer)
    if (!cancelled && JSON.stringify(gesture.points) !== JSON.stringify(gesture.original)) {
      editEndpoints(gesture.node, gesture.points)
    }
    canvas.schedule()
  }
  const pointerUp = canvas.pointerUp.bind(canvas)
  canvas.pointerUp = (event, cancelled = false) => {
    if (!cancelled && isStraightLineGesture(canvas.gesture) && event.pointerId === canvas.gesture.pointer) {
      canvas.pointerMove(event)
    }
    if (canvas.gesture?.kind !== "line-endpoint") return pointerUp(event, cancelled)
    if (event.pointerId !== canvas.gesture.pointer) return
    if (!cancelled) canvas.pointerMove(event)
    finishEndpoint(cancelled)
  }
  const cancelGesture = canvas.cancelGesture.bind(canvas)
  canvas.cancelGesture = () => {
    const gesture = canvas.gesture
    if (gesture?.kind === "line-endpoint") return finishEndpoint(true)
    cancelGesture()
    if (isStraightLineGesture(gesture)) {
      canvas.pointers.delete(gesture.pointer)
      if (canvas.root.hasPointerCapture(gesture.pointer)) canvas.root.releasePointerCapture(gesture.pointer)
    }
  }
  const keyDown = canvas.keyDown.bind(canvas)
  canvas.keyDown = event => {
    if (event.key === "Escape" && canvas.gesture?.kind === "line-endpoint") {
      event.preventDefault()
      return canvas.cancelGesture()
    }
    const end = event.target.closest(".drawing-line-endpoint")?.dataset.end
    const node = end && selectedLine()
    const delta = {ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1]}[event.key]
    if (node && delta && (event.metaKey || event.ctrlKey || event.altKey)) return
    if (!node || !delta || canvas.gesture) return keyDown(event)
    event.preventDefault()
    const points = pointsOf(node)
    const step = event.shiftKey ? 10 : 1
    points[end] = {x: points[end].x + delta[0] * step, y: points[end].y + delta[1] * step}
    editEndpoints(node, points)
  }
  const shiftChanged = event => {
    const gesture = canvas.gesture
    if (event.key !== "Shift" || !isStraightLineGesture(gesture) || event.defaultPrevented || event.isComposing) return
    if (event.target.closest("input, textarea, select") || event.target.isContentEditable) return
    gesture.square = event.shiftKey
    constrainLine(gesture)
    canvas.schedule()
  }
  const lostCapture = event => {
    const gesture = canvas.gesture
    if (gesture?.kind === "line-endpoint" || isStraightLineGesture(gesture) && gesture.pointer === event.pointerId) {
      canvas.cancelGesture()
    }
  }
  canvas.root.addEventListener("keydown", shiftChanged)
  canvas.root.addEventListener("keyup", shiftChanged)
  canvas.root.addEventListener("lostpointercapture", lostCapture)
  canvas.schedule()
  return () => {
    canvas.cancelGesture()
    dockObserver.disconnect()
    canvas.root.removeEventListener("keydown", shiftChanged)
    canvas.root.removeEventListener("keyup", shiftChanged)
    canvas.root.removeEventListener("lostpointercapture", lostCapture)
    endpoints.forEach(button => button.remove())
  }
}

// Text commits can enqueue an automatic resize in their reply callback.
// Track the whole chain, not an arbitrary delay after blurring the editor.
const FileCanvas = {
  ...Hakushi,
  async mounted() {
    this.el.pendingFileEdits = 0
    this.el.fileCanvasReady = false
    const workspace = this.el.closest("#workspace")
    const push = this.pushEventTo.bind(this)
    this.pushEventTo = (target, event, payload, onReply) => {
      this.el.pendingFileEdits++
      return push(target, event, payload, (reply, ref) => {
        try {
          onReply?.(reply, ref)
        } finally {
          if (--this.el.pendingFileEdits === 0) {
            this.el.dispatchEvent(new CustomEvent("canvas:settled", {bubbles: true}))
          }
        }
      })
    }
    setFontState(workspace, "loading")
    try {
      await loadDrawingFonts(workspace)
    } catch (error) {
      if (this.el.isConnected) setFontState(workspace, "error")
      console.error("Local drawing fonts could not load", error)
      return
    }
    if (!this.el.isConnected) return
    setFontState(workspace, "ready")
    // Keep initialization outside the font catch: a canvas error is not a font error.
    Hakushi.mounted.call(this)
    mountSelfLoops(this.canvas)
    this.destroyLineTool = mountLineTool(this.canvas)
    mountObjectTypography(this.canvas)
    this.typographyObserver = new MutationObserver(() => this.canvas.drawStylePanel())
    this.typographyObserver.observe(workspace, {
      attributes: true,
      attributeFilter: ["data-drawing-font"],
    })
    const exportImage = this.canvas.exportImage.bind(this.canvas)
    this.canvas.exportImage = async options => {
      await loadDrawingFonts(workspace)
      return exportImage(options)
    }
    this.mountZoomControls()
    this.zoomKey = event => {
      if ((!event.metaKey && !event.ctrlKey) || event.altKey || event.isComposing) return
      let factor
      if (event.key === "+" || event.key === "=") factor = 1.25
      else if (event.key === "-") factor = 1 / 1.25
      else return
      event.preventDefault()
      event.stopPropagation()
      this.canvas.zoomBy(factor)
    }
    window.addEventListener("keydown", this.zoomKey, true)
    this.el.fileCanvasReady = true
    this.el.dispatchEvent(new CustomEvent("canvas:settled", {bubbles: true}))
  },
  mountZoomControls() {
    const root = this.canvas.root
    const controls = root.querySelector(".hakushi-controls")
    const reset = controls.querySelector(".hakushi-zoom")
    // Retarget Hakushi's live label; its original button keeps the reset handler.
    // A new disclosure must not inherit that handler and reset zoom when opened.
    const trigger = reset.cloneNode(false)
    trigger.textContent = reset.textContent
    reset.replaceWith(trigger)
    this.canvas.zoomLabel = trigger
    const zoomOut = controls.querySelector('[data-action="zoom-out"]')
    const zoomIn = controls.querySelector('[data-action="zoom-in"]')
    zoomIn.title = "Zoom in (⌘+ / Ctrl++)"
    zoomIn.setAttribute("aria-keyshortcuts", "Meta+= Control+= Meta+Shift+= Control+Shift+=")
    zoomOut.title = "Zoom out (⌘− / Ctrl+-)"
    zoomOut.setAttribute("aria-keyshortcuts", "Meta+- Control+-")
    const fit = controls.querySelector('[data-action="fit"]')
    const popover = document.createElement("div")
    popover.id = `${root.id}-zoom`
    popover.className = "zoom-popover"
    popover.setAttribute("popover", "auto")
    popover.setAttribute("role", "dialog")
    popover.setAttribute("aria-label", "Zoom controls")

    const stepper = document.createElement("div")
    stepper.className = "zoom-stepper"
    const value = document.createElement("output")
    value.className = "zoom-value"
    zoomOut.autofocus = true
    stepper.append(zoomOut, value, zoomIn)

    const fitLabel = document.createElement("span")
    fitLabel.textContent = "Fit to screen"
    fit.append(fitLabel)
    reset.classList.remove("hakushi-zoom")
    reset.textContent = "Reset to 100%"
    reset.setAttribute("aria-label", "Reset to 100%")
    reset.title = "Reset to 100%"
    popover.append(stepper, fit, reset)
    // Stay inside the native pointer boundary so clicks cannot start canvas gestures.
    controls.append(popover)

    // Keep the native zoom label and actions, but make its button a disclosure.
    trigger.dataset.action = "zoom-toggle"
    trigger.setAttribute("popovertarget", popover.id)
    trigger.setAttribute("aria-haspopup", "dialog")
    trigger.setAttribute("aria-controls", popover.id)
    trigger.setAttribute("aria-expanded", "false")
    trigger.title = "Zoom controls"
    trigger.addEventListener("click", event => {
      event.stopPropagation()
      // Safari does not focus clicked buttons; give light-dismiss a return target.
      trigger.focus()
    })
    popover.addEventListener("toggle", event => {
      trigger.setAttribute("aria-expanded", String(event.newState === "open"))
    })
    const syncZoom = () => {
      value.textContent = trigger.textContent
      trigger.setAttribute("aria-label", `Zoom controls (${trigger.textContent})`)
    }
    this.zoomObserver = new MutationObserver(syncZoom)
    this.zoomObserver.observe(trigger, {childList: true, characterData: true, subtree: true})
    syncZoom()
    controls.prepend(
      controls.querySelector('[data-action="undo"]'),
      controls.querySelector('[data-action="redo"]'),
      trigger,
    )
  },
  destroyed() {
    window.removeEventListener("keydown", this.zoomKey, true)
    this.destroyLineTool?.()
    this.zoomObserver?.disconnect()
    this.typographyObserver?.disconnect()
    Hakushi.destroyed.call(this)
  },
}

const Workspace = {
  mounted() {
    this.activeCanvas = () => this.el.querySelector('[phx-hook="Hakushi"]')
    this.pending = () => {
      const canvas = this.activeCanvas()
      return canvas ? (canvas.fileCanvasReady ? canvas.pendingFileEdits || 0 : 1) : 0
    }
    this.flushSave = () => {
      if (!this.activeCanvas()) {
        this.saveRequested = false
      } else if (this.saveRequested && this.pending() === 0) {
        this.saveRequested = false
        this.pushEvent("save", {})
      }
    }
    this.requestSave = () => {
      if (!this.activeCanvas()) return
      this.saveRequested = true
      document.activeElement?.blur()
      this.flushSave()
    }
    this.saveKey = event => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault()
        this.requestSave()
      }
    }
    this.closeOverlays = event => {
      if (event.key === "Escape") this.pushEvent("close-overlays", {})
    }
    this.beforeUnload = event => {
      if (this.el.dataset.dirty === "true" || this.pending() > 0 || document.querySelector(".hakushi-text-editor")) {
        event.preventDefault()
        event.returnValue = ""
      }
    }
    this.el.addEventListener("canvas:save", this.requestSave)
    this.el.addEventListener("canvas:settled", this.flushSave)
    window.addEventListener("keydown", this.saveKey, true)
    window.addEventListener("keydown", this.closeOverlays, true)
    window.addEventListener("beforeunload", this.beforeUnload)
  },
  updated() {
    this.el.dataset.fontState = this.el.drawingFontState || "loading"
    this.flushSave()
  },
  destroyed() {
    this.el.removeEventListener("canvas:save", this.requestSave)
    this.el.removeEventListener("canvas:settled", this.flushSave)
    window.removeEventListener("keydown", this.saveKey, true)
    window.removeEventListener("keydown", this.closeOverlays, true)
    window.removeEventListener("beforeunload", this.beforeUnload)
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: document.querySelector("meta[name='csrf-token']").content},
  hooks: {Hakushi: FileCanvas, Workspace},
})
liveSocket.connect()
window.liveSocket = liveSocket
