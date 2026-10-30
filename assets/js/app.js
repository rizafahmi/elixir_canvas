import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {Hakushi} from "hakushi"

let drawingFonts
function loadDrawingFonts() {
  return drawingFonts ||= Promise.all([
    document.fonts.load('700 28px "Amatic SC"'),
    document.fonts.load('400 12px "Roboto Mono"'),
  ]).then(fonts => {
    if (fonts.some(faces => faces.length === 0)) {
      throw new Error("Local drawing font files are unavailable")
    }
  })
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
      await loadDrawingFonts()
    } catch (error) {
      if (this.el.isConnected) setFontState(workspace, "error")
      console.error("Local drawing fonts could not load", error)
      return
    }
    if (!this.el.isConnected) return
    setFontState(workspace, "ready")
    // Keep initialization outside the font catch: a canvas error is not a font error.
    Hakushi.mounted.call(this)
    this.el.fileCanvasReady = true
    this.el.dispatchEvent(new CustomEvent("canvas:settled", {bubbles: true}))
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
