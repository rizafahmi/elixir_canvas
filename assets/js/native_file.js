const openError = "Save or reload this canvas before opening another file."
const conflictError = "File changed on disk. Reload before saving; your canvas edits are still here."

const supportsWritableHandle = handle => handle &&
  ["getFile", "createWritable", "queryPermission", "requestPermission"]
    .every(method => typeof handle[method] === "function")

async function readSelectedFile(file) {
  // Keep the exact UTF-8 bytes, including a BOM, for Document.decode and its revision.
  // File.text() would silently replace malformed UTF-8 before server validation.
  const buffer = await file.arrayBuffer()
  return new TextDecoder("utf-8", {fatal: true, ignoreBOM: true}).decode(buffer)
}

async function checkRevision(handle, revision) {
  const file = await handle.getFile()
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer())
  const current = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("")
  if (current !== revision) {
    const error = new Error(conflictError)
    error.fileStatus = "changed"
    throw error
  }
}

function fileError(error, saving = false) {
  if (error.name === "NotAllowedError") {
    return saving
      ? "Permission to save this file was not granted. Your canvas edits are still here."
      : "Permission to read this file was not granted. The current canvas is still here."
  }
  if (error.name === "NotFoundError") return "File is missing or unreadable. Nothing was overwritten."
  return `${saving ? "Could not save file" : "Could not open file"}: ${error.message}`
}

export function mountNativeFile(workspace) {
  const root = workspace.el
  const input = root.querySelector("#canvas-file-input")
  const send = (event, payload) => new Promise(resolve => workspace.pushEvent(event, payload, resolve))
  const generation = () => Number(root.dataset.generation)
  const editVersion = () => Number(root.dataset.editVersion)
  const mode = () => root.dataset.fileMode
  const supportsDirectSave = window.isSecureContext &&
    typeof window.showOpenFilePicker === "function" &&
    supportsWritableHandle(window.FileSystemFileHandle?.prototype)
  let selectedFile = null
  let pickerRequest = null
  let busy = false
  let alive = true

  const isCurrent = request => alive && request.generation === generation()
  const reportError = (message, request) => {
    if (isCurrent(request)) workspace.pushEvent("selected-error", {generation: request.generation, message})
  }
  const syncButtons = () => {
    const disabled = busy || root.dataset.fileBusy === "true"
    root.dataset.nativeBusy = String(busy)
    for (const help of root.querySelectorAll("[data-native-open-help]")) {
      help.textContent = supportsDirectSave
        ? "Choose a canvas JSON file. With your permission, Save writes back to that file while this tab stays open."
        : "This browser cannot save back to a selected file. Open a canvas JSON file, then Save copy downloads JSON without changing the original."
    }
    for (const button of root.querySelectorAll("#save-file, #open-native-file, #empty-open-file, #reload-file, #server-file-options button, #disk-warning .message-action")) {
      button.disabled = disabled || button.id === "save-file" && mode() === "none"
    }
  }
  const setBusy = value => {
    busy = value
    syncButtons()
  }
  const finishPicker = request => {
    setBusy(false)
    if (request?.trigger?.isConnected) request.trigger.focus()
  }

  const acceptFile = async (request, file, handle) => {
    const bytes = await readSelectedFile(file)
    await request.settled
    await workspace.flushEdits()
    if (!isCurrent(request)) return
    const reloading = request.action === "reload" && file.name === request.filename
    if (!reloading && workspace.hasUnsaved()) {
      reportError(openError, request)
      return
    }
    if (reloading && editVersion() !== request.editVersion) {
      reportError("Canvas changed while the file was being read. Reload again to discard those edits.", request)
      return
    }
    const fileMode = supportsDirectSave && supportsWritableHandle(handle) ? "browser_file" : "save_copy"
    const writeGranted = fileMode === "browser_file" &&
      await handle.queryPermission({mode: "readwrite"}) === "granted"
    if (!isCurrent(request) || !reloading && workspace.hasUnsaved()) {
      reportError(openError, request)
      return
    }
    const reply = await send(reloading ? "selected-reload" : "selected-open", {
      filename: file.name,
      bytes,
      mode: fileMode,
      generation: request.generation,
      ...(reloading ? {edit_version: request.editVersion} : {}),
    })
    // A candidate owns no handle until the existing schema/dirty checks accept it.
    if (reply.ok && alive && generation() === reply.generation && mode() === fileMode) {
      selectedFile = {
        handle: fileMode === "browser_file" ? handle : null,
        filename: file.name,
        generation: reply.generation,
        revision: reply.revision,
        writeGranted,
      }
    }
  }

  const onInputChange = async () => {
    const request = pickerRequest
    pickerRequest = null
    const file = input.files[0]
    input.value = ""
    if (!request) return
    try {
      if (file) await acceptFile(request, file, null)
    } catch (error) {
      reportError(fileError(error), request)
    } finally {
      finishPicker(request)
    }
  }
  const onInputCancel = () => {
    const request = pickerRequest
    pickerRequest = null
    input.value = ""
    if (request) finishPicker(request)
  }
  input.addEventListener("change", onInputChange)
  input.addEventListener("cancel", onInputCancel)

  const open = (action = "open") => {
    if (busy || root.dataset.fileBusy === "true") return
    const request = {action, generation: generation(), filename: root.dataset.fileName, trigger: document.activeElement}
    if (action === "open") {
      document.activeElement?.blur()
      if (workspace.hasUnsaved()) {
        reportError(openError, request)
        return
      }
    } else if (workspace.hasUnsaved() && !window.confirm(
      mode() === "save_copy"
        ? `Discard unsaved canvas edits and select "${request.filename}" again to reload it?`
        : "Discard unsaved canvas edits and reload the selected file from disk?",
    )) return

    setBusy(true)
    // Start the flush, but never await it before opening the user-activated picker.
    request.settled = workspace.flushEdits()
    request.editVersion = editVersion()
    if (action === "reload" && mode() === "browser_file") {
      const selected = selectedFile
      if (!selected || selected.generation !== request.generation) {
        reportError("The selected file is no longer connected to this tab. Open it again to reload it.", request)
        finishPicker(request)
        return
      }
      ;(async () => {
        try {
          await acceptFile(request, await selected.handle.getFile(), selected.handle)
        } catch (error) {
          reportError(fileError(error), request)
        } finally {
          finishPicker(request)
        }
      })()
    } else if (action === "open" && supportsDirectSave) {
      // This call must stay in the original click/keyboard gesture, before any await.
      let picker
      try {
        picker = window.showOpenFilePicker({
          multiple: false,
          types: [{description: "Canvas JSON", accept: {"application/json": [".json"]}}],
        })
      } catch (error) {
        reportError(fileError(error), request)
        finishPicker(request)
        return
      }
      ;(async () => {
        let handle
        try {
          ;[handle] = await picker
        } catch (error) {
          // AbortError is the picker's native cancellation, not a read/write fallback.
          if (error.name !== "AbortError") reportError(fileError(error), request)
          finishPicker(request)
          return
        }
        try {
          await acceptFile(request, await handle.getFile(), handle)
        } catch (error) {
          reportError(fileError(error), request)
        } finally {
          finishPicker(request)
        }
      })()
    } else {
      pickerRequest = request
      // Reset before every dialog so choosing the same file emits change again.
      input.value = ""
      try {
        input.click()
      } catch (error) {
        pickerRequest = null
        reportError(fileError(error), request)
        finishPicker(request)
      }
    }
  }

  const save = async () => {
    if (busy || root.dataset.fileBusy === "true" || mode() === "none") return
    const request = {generation: generation()}
    const selected = selectedFile
    let reply
    let written = false
    setBusy(true)
    try {
      let permission
      if (mode() === "browser_file") {
        if (!selected?.handle || selected.generation !== request.generation) {
          throw new Error("The selected file is no longer connected to this tab. Open it again before saving.")
        }
        // A permission prompt consumes user activation; request it synchronously,
        // before text blur, the pending Hakushi reply chain, or the server snapshot.
        permission = selected.writeGranted
          ? Promise.resolve("granted")
          : selected.handle.requestPermission({mode: "readwrite"})
      }
      const settled = workspace.flushEdits()
      if (permission) {
        selected.writeGranted = await permission === "granted"
        if (!selected.writeGranted) throw new DOMException("Write permission denied", "NotAllowedError")
      }
      await settled
      if (!isCurrent(request)) return
      reply = await send("save", {generation: request.generation})
      if (!reply.ok || !reply.token) return
      if (!isCurrent(request) || reply.generation !== request.generation ||
          reply.mode !== mode() || reply.filename !== root.dataset.fileName ||
          !selected || selected !== selectedFile || selected.generation !== request.generation ||
          selected.revision !== reply.revision) {
        throw new Error("The selected file changed before saving. Nothing was overwritten.")
      }

      if (reply.mode === "save_copy") {
        const url = URL.createObjectURL(new Blob([reply.bytes], {type: "application/json"}))
        const link = document.createElement("a")
        link.href = url
        link.download = reply.filename
        root.append(link)
        try {
          link.click()
        } finally {
          link.remove()
          // Let the native download consume the URL, then release the JSON buffer.
          setTimeout(() => URL.revokeObjectURL(url), 0)
        }
        await send("selected-copy-downloaded", {token: reply.token, generation: reply.generation})
        return
      }

      await checkRevision(selected.handle, reply.revision)
      const writable = await selected.handle.createWritable({mode: "exclusive"})
      try {
        await writable.write(reply.bytes)
        // External editors do not participate in the browser's exclusive writer lock.
        await checkRevision(selected.handle, reply.revision)
        await writable.close()
        written = true
      } catch (error) {
        try {
          await writable.abort()
        } catch (abortError) {
          error.message += ` Temporary write cleanup failed: ${abortError.message}`
        }
        throw error
      }
      const acknowledgment = await send("selected-saved", {token: reply.token, generation: reply.generation})
      if (!acknowledgment.ok) throw new Error("The file was written, but the canvas could not confirm the save. Reload before saving again.")
      if (isCurrent(request) && selectedFile === selected) selected.revision = reply.saved_revision
    } catch (error) {
      if (error.name === "NotAllowedError" && selected) selected.writeGranted = false
      const message = written ? error.message : fileError(error, true)
      if (reply?.token) {
        await send("selected-save-error", {
          token: reply.token,
          generation: reply.generation,
          message,
          status: error.fileStatus || (error.name === "NotFoundError" ? "unavailable" : undefined),
        })
      } else reportError(message, request)
    } finally {
      setBusy(false)
    }
  }

  syncButtons()

  return {
    open: () => open("open"),
    reload: () => open("reload"),
    save,
    updated() {
      if (selectedFile && (selectedFile.generation !== generation() || selectedFile.filename !== root.dataset.fileName || mode() === "server_file" || mode() === "none")) {
        selectedFile = null
      }
      syncButtons()
    },
    destroyed() {
      alive = false
      selectedFile = null
      pickerRequest = null
      input.removeEventListener("change", onInputChange)
      input.removeEventListener("cancel", onInputCancel)
    },
  }
}
