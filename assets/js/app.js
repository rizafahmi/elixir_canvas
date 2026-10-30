import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {Hakushi} from "hakushi"

// Text commits can enqueue an automatic resize in their reply callback.
// Track the whole chain, not an arbitrary delay after blurring the editor.
const FileCanvas = {
  ...Hakushi,
  mounted() {
    this.el.pendingFileEdits = 0
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
    Hakushi.mounted.call(this)
  },
}

const Workspace = {
  mounted() {
    this.pending = () => this.el.querySelector('[phx-hook="Hakushi"]')?.pendingFileEdits || 0
    this.flushSave = () => {
      if (this.saveRequested && this.pending() === 0) {
        this.saveRequested = false
        this.pushEvent("save", {})
      }
    }
    this.requestSave = () => {
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
    this.beforeUnload = event => {
      if (this.el.dataset.dirty === "true" || this.pending() > 0 || this.el.querySelector(".hakushi-text-editor")) {
        event.preventDefault()
        event.returnValue = ""
      }
    }
    this.el.addEventListener("canvas:save", this.requestSave)
    this.el.addEventListener("canvas:settled", this.flushSave)
    window.addEventListener("keydown", this.saveKey, true)
    window.addEventListener("beforeunload", this.beforeUnload)
  },
  destroyed() {
    this.el.removeEventListener("canvas:save", this.requestSave)
    this.el.removeEventListener("canvas:settled", this.flushSave)
    window.removeEventListener("keydown", this.saveKey, true)
    window.removeEventListener("beforeunload", this.beforeUnload)
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: document.querySelector("meta[name='csrf-token']").content},
  hooks: {Hakushi: FileCanvas, Workspace},
})
liveSocket.connect()
window.liveSocket = liveSocket
