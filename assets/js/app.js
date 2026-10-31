import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {Hakushi} from "hakushi"

async function loadDrawingFonts(workspace) {
  // Resolve the host's CSS mapping, not a second document-role → family registry.
  // Preload every role so changing document appearance never measures a fallback.
  const probe = document.createElement("div")
  probe.className = workspace.className
  probe.hidden = true
  workspace.append(probe)
  const fonts = new Set()
  try {
    for (const role of ["sans", "heading", "mono", "handwritten"]) {
      probe.dataset.drawingFont = role
      const style = getComputedStyle(probe)
      const family = style.getPropertyValue("--canvas-text-font").trim()
      for (const suffix of ["", "-large"]) {
        const weight = style.getPropertyValue(`--canvas-text-weight${suffix}`).trim()
        fonts.add(`${weight} 28px ${family}`)
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
    this.zoomObserver?.disconnect()
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
